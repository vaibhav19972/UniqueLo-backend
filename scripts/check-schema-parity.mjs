#!/usr/bin/env node
/**
 * Schema parity gate: the products block in schema.sql must equal the measured
 * live catalogue shape (contracts/live-columns.txt).
 *
 * This is the guard contracts/schema-drift.md asked for. It caught the six
 * columns 20261024 dropped but schema.sql still declared, and the trust columns
 * the migration added that schema.sql lacked.
 *
 * Usage: node backend/scripts/check-schema-parity.mjs
 * Exit 0 = parity, exit 1 = drift (prints both directions).
 */

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '../..');

const schema = readFileSync(resolve(REPO, 'backend/schema.sql'), 'utf8');
const start = schema.indexOf('create table if not exists public.products');
if (start < 0) {
  console.error('could not find public.products in schema.sql');
  process.exit(1);
}
const block = schema.slice(start, schema.indexOf(');', start));

const inSchema = new Set();
for (const line of block.split('\n').slice(1)) {
  if (/^\s{2}constraint\b/.test(line)) continue;
  const m = line.match(/^\s{2}([a-z_]+)\s+[a-z(\[]/);
  if (m) inSchema.add(m[1]);
}

const live = new Set(
  readFileSync(resolve(REPO, 'backend/contracts/live-columns.txt'), 'utf8')
    .split('\n')
    .map((s) => s.trim())
    .filter(Boolean),
);

const missing = [...live].filter((c) => !inSchema.has(c)).sort();
const extra = [...inSchema].filter((c) => !live.has(c)).sort();

console.log(`schema parity  (schema.sql products vs contracts/live-columns.txt)`);
console.log(`  schema.sql columns : ${inSchema.size}`);
console.log(`  live columns       : ${live.size}`);

if (missing.length || extra.length) {
  console.log('\nDRIFT');
  if (missing.length) console.log(`  missing from schema.sql: ${missing.join(', ')}`);
  if (extra.length) console.log(`  not in live shape      : ${extra.join(', ')}`);
  process.exit(1);
}
console.log('\nparity — schema.sql matches the measured live catalogue shape.');
