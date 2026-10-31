#!/usr/bin/env node
/**
 * Schema completeness gate: schema.sql must carry every table and every added
 * column that the migration chain creates.
 *
 * WHY THIS EXISTS
 * ---------------
 * schema.sql is documented as the "Full DDL (bootstrap)" — the file you run to
 * stand up a fresh database. By 2026-10-31 it had fallen seven tables and one
 * column behind the migrations, so a fresh build produced a database that:
 *
 *   - had no `coupons` / `shipping_rules`, so `quote_order()` could not run
 *   - had no `admins`, so `is_admin()` could never be granted
 *   - had no `customer_addresses` / `customer_wishlists`
 *   - had no `attribute_definitions`, so the attribute trigger had no contract
 *   - had no `orders.user_id`, so signed-in order history had nowhere to bind
 *
 * `check-schema-parity.mjs` did not catch any of it: it compares `products`
 * COLUMNS against a harvested fingerprint, and is structurally blind to any
 * other table. A table-level check alone would still have missed
 * `orders.user_id`, which is an ALTER, not a CREATE. So this gate parses both
 * forms.
 *
 * WHAT IT DOES NOT COVER (deliberate)
 * -----------------------------------
 * CONSTRAINTS ARE ALSO OUT OF SCOPE — deliberately, but know the limit.
 * This gate compares TABLES and COLUMNS. A CHECK, UNIQUE or FK added by a
 * migration is not compared, so `schema.sql` could drift from the chain at the
 * constraint level and stay green. The convention that covers it is the
 * `20261101` precedent: a CHECK lives in BOTH places — inline in schema.sql for
 * a fresh build, and guarded in the migration by
 * `if not exists (select 1 from pg_constraint where conname = ...)`. Follow it.
 *
 * Policies, functions, triggers and grants are owned by the migration chain —
 * schema.sql cannot express the final form of them (e.g. the storage policy
 * needs `is_admin()`, which a migration creates). This gate scopes to tables
 * and columns. The boundary is stated in schema.sql's own header.
 *
 * Usage: node backend/scripts/check-schema-completeness.mjs
 * Exit 0 = complete, exit 1 = drift (prints both directions).
 */

import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '../..');
const MIGRATIONS = resolve(REPO, 'backend/migrations');

const schema = readFileSync(resolve(REPO, 'backend/schema.sql'), 'utf8');

// ---------------------------------------------------------------------------
// Parse schema.sql
// ---------------------------------------------------------------------------

/** Tables created in schema.sql, and the column set of each. */
const schemaTables = new Map();

for (const m of schema.matchAll(
  /create table if not exists public\.([a-z_]+)\s*\(/gi,
)) {
  const name = m[1];
  const start = m.index + m[0].length;
  // Walk to the matching close paren at column 0 (`^);`) rather than the first
  // `);` — a block may legitimately contain nested parens (checks, defaults).
  const end = schema.slice(start).search(/^\);/m);
  const body = end < 0 ? '' : schema.slice(start, start + end);

  const cols = new Set();
  for (const line of body.split('\n')) {
    if (/^\s*constraint\b/i.test(line)) continue;
    // Same column regex as check-schema-parity.mjs, so the gates agree.
    const cm = line.match(/^\s{2}([a-z_]+)\s+[a-z(\[]/);
    if (cm) cols.add(cm[1]);
  }
  schemaTables.set(name, cols);
}

/** Columns schema.sql adds to an existing table via ALTER. */
const schemaAltered = new Map();
for (const m of schema.matchAll(
  /alter table public\.([a-z_]+)([\s\S]*?);/gi,
)) {
  const table = m[1].toLowerCase();
  if (!schemaAltered.has(table)) schemaAltered.set(table, new Set());
  for (const a of m[2].matchAll(/add column(?: if not exists)? ([a-z_]+)/gi)) {
    schemaAltered.get(table).add(a[1].toLowerCase());
  }
}

/** schema.sql has column `col` on `table`, however it got there. */
function schemaHasColumn(table, col) {
  return (
    schemaTables.get(table)?.has(col) ||
    schemaAltered.get(table)?.has(col) ||
    false
  );
}

// ---------------------------------------------------------------------------
// Parse the migration chain
// ---------------------------------------------------------------------------

const files = readdirSync(MIGRATIONS)
  .filter((f) => f.endsWith('.sql'))
  .sort();

/** Tables the migrations create (table -> first file that creates it). */
const migrationTables = new Map();
/** Columns the migrations add (table -> col -> first file). */
const migrationAltered = new Map();

for (const file of files) {
  const sql = readFileSync(resolve(MIGRATIONS, file), 'utf8');
  const code = stripSqlComments(sql);

  for (const m of code.matchAll(
    /create table if not exists public\.([a-z_]+)/gi,
  )) {
    if (!migrationTables.has(m[1].toLowerCase())) {
      migrationTables.set(m[1].toLowerCase(), file);
    }
  }

  for (const m of code.matchAll(/alter table public\.([a-z_]+)([\s\S]*?);/gi)) {
    const table = m[1].toLowerCase();
    if (!migrationAltered.has(table)) migrationAltered.set(table, new Map());
    for (const a of m[2].matchAll(/add column(?: if not exists)? ([a-z_]+)/gi)) {
      if (!migrationAltered.get(table).has(a[1].toLowerCase())) {
        migrationAltered.get(table).set(a[1].toLowerCase(), file);
      }
    }
  }
}

/**
 * Comments must be stripped before parsing: several migrations DISCUSS tables
 * and columns in prose (e.g. "add `attribute_definitions` to the loop"), and a
 * naive match would treat those mentions as real DDL.
 */
function stripSqlComments(sql) {
  return sql
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/--[^\n]*/g, '');
}

// ---------------------------------------------------------------------------
// Diff
// ---------------------------------------------------------------------------

const missingTables = [...migrationTables.keys()]
  .filter((t) => !schemaTables.has(t))
  .sort();

const missingColumns = [];
for (const [table, cols] of [...migrationAltered.entries()].sort()) {
  // Only meaningful for tables the baseline is meant to carry. A table that is
  // itself missing is already reported above; adding its columns again is
  // noise.
  if (!schemaTables.has(table)) continue;
  for (const [col, file] of cols) {
    if (!schemaHasColumn(table, col)) {
      missingColumns.push({ table, col, file });
    }
  }
}

/**
 * Column-set parity for tables that exist on BOTH sides.
 *
 * Existence checks alone let a hand-copy error through: restore seven table
 * bodies by hand, drop one column from `coupons`, and every table still
 * "exists". The baseline would then be quietly narrower than the migration
 * chain and `price_cart()` would fail at runtime on a fresh build.
 *
 * Only tables the chain also creates are compared — baseline-only tables
 * (e.g. `universes`) have no migration counterpart to diff against.
 */
const columnDrift = [];
for (const [table, cols] of [...schemaTables.entries()].sort()) {
  if (!migrationTables.has(table)) continue;

  // Rebuild the chain's own column set for this table: CREATE body, then
  // every ADD COLUMN, minus every DROP COLUMN, replayed in file order.
  const chainCols = new Set();
  for (const file of files) {
    const code = stripSqlComments(readFileSync(resolve(MIGRATIONS, file), 'utf8'));

    const createRe = new RegExp(
      `create table if not exists public\\.${table}\\s*\\(`, 'i',
    );
    const cm = createRe.exec(code);
    if (cm) {
      const bodyStart = cm.index + cm[0].length;
      const close = code.slice(bodyStart).search(/^\);/m);
      const body = close < 0 ? '' : code.slice(bodyStart, bodyStart + close);
      for (const line of body.split('\n')) {
        if (/^\s*constraint\b/i.test(line)) continue;
        const lm = line.match(/^\s{2}([a-z_]+)\s+[a-z(\[]/i);
        if (lm) chainCols.add(lm[1].toLowerCase());
      }
    }

    for (const stmt of code.split(/;\s*(?:\r?\n|$)/)) {
      if (!new RegExp(`alter table public\\.${table}\\b`, 'i').test(stmt)) continue;
      for (const a of stmt.matchAll(/add column(?: if not exists)? ([a-z_]+)/gi)) {
        chainCols.add(a[1].toLowerCase());
      }
      for (const a of stmt.matchAll(/drop column(?: if exists)? ([a-z_]+)/gi)) {
        chainCols.delete(a[1].toLowerCase());
      }
    }
  }

  if (chainCols.size === 0) continue; // created by a form this parser missed

  const have = schemaTables.get(table);
  const missing = [...chainCols].filter((c) => !have.has(c)).sort();
  const extra = [...have].filter((c) => !chainCols.has(c)).sort();
  if (missing.length || extra.length) {
    columnDrift.push({ table, missing, extra });
  }
}

// ---------------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------------

const created = [...migrationTables.keys()].filter((t) => schemaTables.has(t));

console.log('schema completeness  (schema.sql vs migrations/)');
console.log(`  migrations scanned         : ${files.length}`);
console.log(`  tables in schema.sql       : ${schemaTables.size}`);
console.log(`  tables created by chain    : ${migrationTables.size}`);
console.log(`  …already in schema.sql     : ${created.length}`);
console.log(`  alters scanned             : ${
  [...migrationAltered.values()].reduce((n, m) => n + m.size, 0)
}`);

if (missingTables.length || missingColumns.length || columnDrift.length) {
  console.log('\nDRIFT — a fresh schema.sql build would be missing:');
  for (const t of missingTables) {
    console.log(`  missing table  : public.${t}   (created by ${migrationTables.get(t)})`);
  }
  for (const { table, col, file } of missingColumns) {
    console.log(`  missing column : public.${table}.${col}   (added by ${file})`);
  }
  for (const { table, missing, extra } of columnDrift) {
    if (missing.length) {
      console.log(`  missing column : public.${table}.${missing.join(', ')}   (in the chain, absent from schema.sql)`);
    }
    if (extra.length) {
      console.log(`  extra column   : public.${table}.${extra.join(', ')}   (in schema.sql, absent from the chain)`);
    }
  }
  console.log(
    '\nA fresh build of schema.sql + migrations cannot serve the clients.\n' +
      'Add the missing tables/columns to schema.sql (tables first, then the\n' +
      'columns that reference them) and re-run.',
  );
  process.exit(1);
}

console.log(
  `\ncomplete — ${schemaTables.size} tables and every column the migration chain\n` +
    'defines exist in schema.sql.',
);
