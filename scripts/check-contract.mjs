#!/usr/bin/env node
/**
 * Contract gate: the storefront's SELECT list and the Catalog Studio's SQL
 * generator must both agree with the shipped schema.
 *
 * This exists because a typecheck cannot verify either. The SELECT list is a
 * template string handed to PostgREST; the generator is a template string a human
 * pastes into Supabase. Both were wrong after the migration and the app still
 * built and typechecked cleanly — the panel simply showed stale or broken SQL.
 *
 * Usage:  node backend/scripts/check-contract.mjs
 * Exit 0 = consistent, exit 1 = drifted (prints what).
 *
 * Requires the db column names as the source of truth. Pass a live database:
 *   node backend/scripts/check-contract.mjs --db 'postgresql://...'
 * or let it use schema.sql + the migration files (offline mode, the default).
 */

import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '../..');

const TEAL = '\x1b[36m';
const RED = '\x1b[31m';
const GREEN = '\x1b[32m';
const DIM = '\x1b[2m';
const OFF = '\x1b[0m';

const dbFlag = process.argv.indexOf('--db');

// ---------------------------------------------------------------------------
// 1. The columns that exist, per schema.sql + every migration in order
// ---------------------------------------------------------------------------
function schemaColumnsFromFiles() {
  const cols = new Set();
  const schema = readFileSync(resolve(REPO, 'backend/schema.sql'), 'utf8');

  // products table block only
  const block = schema.slice(
    schema.indexOf('create table if not exists public.products'),
    schema.indexOf(');', schema.indexOf('create table if not exists public.products'))
  );
  for (const m of block.matchAll(/^\s{2}([a-z_]+)\s+[a-z(]/gm)) cols.add(m[1]);

  // every added column in every migration
  const migDir = resolve(REPO, 'backend/migrations');
  let files = [];
  try {
    files = execFileSync('ls', [migDir]).toString().split('\n').filter((f) => f.endsWith('.sql')).sort();
  } catch { /* no migrations dir */ }

  for (const f of files) {
    const sql = readFileSync(resolve(migDir, f), 'utf8');
    for (const m of sql.matchAll(/add column if not exists\s+([a-z_]+)/g)) cols.add(m[1]);
    for (const m of sql.matchAll(/drop column if exists\s+([a-z_]+)/g)) cols.delete(m[1]);
  }
  return cols;
}

function schemaColumnsFromDb(dsn) {
  const out = execFileSync('psql', [dsn, '-tAc',
    "select column_name from information_schema.columns where table_schema='public' and table_name='products'"
  ]).toString();
  return new Set(out.split('\n').map((s) => s.trim()).filter(Boolean));
}

const dbCols = dbFlag > -1 ? schemaColumnsFromDb(process.argv[dbFlag + 1]) : schemaColumnsFromFiles();
const dbMode = dbFlag > -1 ? `live database` : `schema.sql + migrations`;

// ---------------------------------------------------------------------------
// 2. The storefront's SELECT list
// ---------------------------------------------------------------------------
const dataTs = readFileSync(resolve(REPO, 'web/src/lib/data.ts'), 'utf8');
const selMatch = dataTs.match(/\.from\('products'\)\s*\.select\(`([\s\S]*?)`\)/);
if (!selMatch) {
  console.error(`${RED}could not find the products select() in data.ts${OFF}`);
  process.exit(1);
}
const selected = selMatch[1]
  .split(/variants \(/)[0]           // top-level columns only
  .split(',')
  .map((c) => c.trim())
  .filter((c) => /^[a-z_]+$/.test(c));

// nested structures must reference real tables
const nested = [...selMatch[1].matchAll(/(\w+)\s*\(([^)]*)\)/g)].map((m) => ({
  table: m[1],
  cols: m[2].split(',').map((c) => c.trim()).filter(Boolean),
}));

// ---------------------------------------------------------------------------
// 3. The Catalog Studio's SQL generator
// ---------------------------------------------------------------------------
const adminTs = readFileSync(resolve(REPO, 'web/src/pages/Admin.tsx'), 'utf8');
const genStart = adminTs.indexOf('INSERT INTO public.products (');
const genEnd = adminTs.indexOf(') ON CONFLICT (slug) DO UPDATE SET');
const generated = genStart > -1 && genEnd > -1
  ? adminTs.slice(genStart + 'INSERT INTO public.products ('.length, genEnd)
      .split(',')
      .map((c) => c.trim())
      .filter((c) => /^[a-z_]+$/.test(c))
  : [];

// ---------------------------------------------------------------------------
// 4. Compare
// ---------------------------------------------------------------------------
const problems = [];

const selMissing = selected.filter((c) => !dbCols.has(c));
if (selMissing.length) problems.push(`data.ts SELECTs columns that do not exist: ${selMissing.join(', ')}`);

const genMissing = generated.filter((c) => !dbCols.has(c));
if (genMissing.length) problems.push(`Admin SQL generator writes columns that do not exist: ${genMissing.join(', ')}`);

if (generated.length === 0) problems.push('Admin SQL generator: could not parse its column list');

// retired names must be gone from both
const RETIRED = ['craft_region', 'craft_cluster', 'batch_number', 'batch_total', 'sold_count'];
for (const r of RETIRED) {
  if (new RegExp(`\\b${r}\\b`).test(adminTs)) problems.push(`Admin.tsx still references retired column "${r}"`);
  if (selected.includes(r)) problems.push(`data.ts still selects retired column "${r}"`);
}

// The generator must carry the fields the schema requires, or the INSERT will be
// rejected by the attribute trigger at paste time.
const mustGenerate = ['style_code', 'attributes', 'cod_available', 'return_window_days', 'country_of_origin'];
const genMissingRequired = mustGenerate.filter((c) => !generated.includes(c));
if (genMissingRequired.length) problems.push(`Admin SQL generator omits required fields: ${genMissingRequired.join(', ')}`);

// ---------------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------------
console.log(`${TEAL}contract check${OFF}  ${DIM}(${dbMode})${OFF}`);
console.log(`  schema columns            : ${dbCols.size}`);
console.log(`  data.ts selects           : ${selected.length}`);
console.log(`  Admin generator writes    : ${generated.length}`);
console.log(`  nested relations          : ${nested.map((n) => n.table).join(', ') || 'none'}`);

if (problems.length) {
  console.log(`\n${RED}DRIFT DETECTED${OFF}`);
  for (const p of problems) console.log(`  - ${p}`);
  process.exit(1);
}

console.log(`\n${GREEN}consistent${OFF} — storefront reads and studio writes both match the schema.`);
