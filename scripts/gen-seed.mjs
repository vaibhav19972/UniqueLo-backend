#!/usr/bin/env node
/**
 * gen-seed.mjs — emit the production product seed FROM the mock catalog.
 *
 * Why a generator instead of hand-written INSERTs:
 *   The old production-seed.sql held 2 of 13 products and priced the hoodie at
 *   ₹8,990 while the storefront showed ₹3,499. Hand-maintained seed data drifts
 *   from the catalog because nobody can diff 121 variants by eye. The catalog
 *   JSON is the artifact the app actually renders, so it is the source.
 *
 * What it does NOT do:
 *   - It does not invent values. Every new trust column must already be present
 *     in the JSON or the run fails. That is deliberate: the audit's core finding
 *     was fictional data entering through defaults (Admin.tsx pre-filling
 *     craftCluster with a supplier name).
 *
 * Usage:
 *   node backend/scripts/gen-seed.mjs            # write production-seed.sql
 *   node backend/scripts/gen-seed.mjs --check    # verify only, change nothing
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '../..');
const CATALOG = resolve(REPO, 'web/src/data/mock-products.json');
const TAXONOMY = {
  categories: resolve(REPO, 'web/src/data/categories.json'),
  garments: resolve(REPO, 'web/src/data/garments.json'),
  collections: resolve(REPO, 'web/src/data/collections.json'),
  motifs: resolve(REPO, 'web/src/data/motifs.json'),
  universes: resolve(REPO, 'web/src/data/universes.json'),
};
const OUT = resolve(REPO, 'backend/production-seed.sql');
const CHECK = process.argv.includes('--check');

// Columns the migration adds. A product missing any of these is a hard failure —
// this is the guard that stops the fabricated-field problem coming back.
const REQUIRED_TRUST = ['countryOfOrigin', 'codAvailable', 'returnWindowDays', 'styleCode', 'attributes'];

// Attribute contract, mirroring attribute_definitions in the migration. Kept in
// JS as well so a bad catalogue fails at generation with a readable message
// instead of surfacing as a Postgres trigger error at deploy time.
const ATTR_CONTRACT = {
  pattern:      ['solid','printed','embroidered','striped','checkered','colorblock'],
  neck_type:    ['round','v-neck','crew','collar','band','hooded','square'],
  sleeve_length:['sleeveless','short','three-quarter','long'],
  closure:      ['pull-on','button','zip','drawstring','tie','none'],
  length:       ['cropped','regular','longline','full'],
  rise:         ['low','mid','high'],
  occasion:     ['casual','everyday','festive','work','party','travel'],
  hemline:      ['straight','curved','asymmetric','raw'],
  lining:       ['unlined','partial','full'],
  transparency: ['opaque','semi-sheer','sheer'],
  stretch:      ['non-stretch','low','medium','high'],
};
const REQUIRED_BY_GARMENT = {
  tee:      ['pattern','neck_type','sleeve_length','occasion','fabric_composition'],
  hoodie:   ['pattern','neck_type','sleeve_length','closure','occasion','fabric_composition'],
  shirt:    ['pattern','neck_type','sleeve_length','closure','occasion','fabric_composition'],
  jacket:   ['pattern','sleeve_length','closure','occasion','fabric_composition'],
  cardigan: ['pattern','neck_type','sleeve_length','closure','occasion','fabric_composition'],
  vest:     ['pattern','neck_type','occasion','fabric_composition'],
  pants:    ['pattern','closure','rise','occasion','fabric_composition'],
  scarf:    ['pattern','occasion','fabric_composition'],
  tote:     ['pattern','occasion','fabric_composition'],
};
const REQUIRED = ['slug', 'name', 'subtitle', 'description'];

const fail = (msg) => {
  console.error(`\n  gen-seed: ${msg}\n`);
  process.exit(1);
};
const q = (v) => `'${String(v).replace(/'/g, "''")}'`;
const num = (v) => (v === null || v === undefined ? 'NULL' : String(v));
const bool = (v) => (v === true ? 'true' : v === false ? 'false' : 'NULL');
const arr = (v) =>
  Array.isArray(v) && v.length ? `ARRAY[${v.map(q).join(', ')}]` : `'{}'`;
const jsonb = (v) => (v == null ? 'NULL' : `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb`);
const pad = (s) => s.trimEnd();

// ---------------------------------------------------------------- load inputs
const readJson = (p) => {
  try {
    return JSON.parse(readFileSync(p, 'utf8'));
  } catch (e) {
    fail(`cannot read ${p}: ${e.message}`);
  }
};
const unwrap = (d, key) => (Array.isArray(d) ? d : d[key] ?? []);

const rawCatalog = readJson(CATALOG);
const products = unwrap(rawCatalog, 'products');

const tax = {
  categories: unwrap(readJson(TAXONOMY.categories), 'categories'),
  garments: unwrap(readJson(TAXONOMY.garments), 'garments'),
  collections: unwrap(readJson(TAXONOMY.collections), 'collections'),
  motifs: unwrap(readJson(TAXONOMY.motifs), 'motifs'),
  universes: unwrap(readJson(TAXONOMY.universes), 'universes'),
};

// ------------------------------------------------------------- validate inputs
if (!products.length) fail('catalog is empty');

const errors = [];
const slugs = new Set(tax.categories.map((x) => x.slug));
const gslugs = new Set(tax.garments.map((x) => x.slug));
const cslugs = new Set(tax.collections.map((x) => x.slug));
const mslugs = new Set(tax.motifs.map((x) => x.id ?? x.slug));
const uslugs = new Set(tax.universes.map((x) => x.slug));

for (const p of products) {
  for (const f of [...REQUIRED, ...REQUIRED_TRUST]) {
    if (p[f] === undefined || p[f] === null || p[f] === '') {
      errors.push(`${p.slug ?? '(no slug)'}: missing required field "${f}"`);
    }
  }
  // Foreign-key safety BEFORE Postgres sees it.
  if (p.categorySlug && !slugs.has(p.categorySlug)) errors.push(`${p.slug}: unknown category_slug "${p.categorySlug}"`);
  if (p.garmentType && !gslugs.has(p.garmentType)) errors.push(`${p.slug}: unknown garment_type "${p.garmentType}"`);
  if (p.collectionSlug && !cslugs.has(p.collectionSlug)) errors.push(`${p.slug}: unknown collection_slug "${p.collectionSlug}"`);
  if (p.motifId && !mslugs.has(p.motifId)) errors.push(`${p.slug}: unknown motif_id "${p.motifId}"`);
  if (p.universeSlug && !uslugs.has(p.universeSlug)) errors.push(`${p.slug}: unknown universe_slug "${p.universeSlug}"`);
  if (!Array.isArray(p.variants) || !p.variants.length) errors.push(`${p.slug}: has no variants`);

  if (p.attributes && typeof p.attributes === 'object') {
    const need = REQUIRED_BY_GARMENT[p.garmentType] ?? [];
    for (const k of need) {
      if (p.attributes[k] === undefined) errors.push(`${p.slug}: garment "${p.garmentType}" requires attribute "${k}"`);
    }
    for (const [k, v] of Object.entries(p.attributes)) {
      const opts = ATTR_CONTRACT[k];
      if (opts && !opts.includes(String(v)))
        errors.push(`${p.slug}: attribute "${k}" = "${v}" is not one of ${opts.join('|')}`);
    }
  }
  for (const v of p.variants ?? []) {
    if (!v.sku) errors.push(`${p.slug}: variant missing sku`);
    if (!Number.isInteger(v.priceCents) || v.priceCents <= 0) errors.push(`${p.slug}/${v.sku}: priceCents must be a positive integer`);
  }
}

// Reject any field the schema no longer has — catches a stale catalog early.
const RETIRED = ['craftRegion', 'craftCluster', 'batchNumber', 'batchTotal', 'expressionSlug', 'soldCount', 'characterIds'];
for (const p of products) {
  for (const f of RETIRED) {
    if (f in p) errors.push(`${p.slug}: retired field "${f}" is still present — remove it from the catalog`);
  }
}

// Cross-file referential integrity in the taxonomy itself. collections.json was
// pointing at an "atelier" universe that universes.json has never defined; the
// seed failed at the FK rather than at generation, which is too late.
for (const c of tax.collections) {
  if (c.universeSlug && !uslugs.has(c.universeSlug))
    errors.push(`collection "${c.slug}": references unknown universe "${c.universeSlug}"`);
}
for (const m of tax.motifs) {
  const us = m.universeSlug ?? m.universe_slug;
  if (us && !uslugs.has(us)) errors.push(`motif "${m.id ?? m.slug}": references unknown universe "${us}"`);
}
for (const g of tax.garments) {
  const cs = g.categorySlug ?? g.category_slug;
  if (cs && !slugs.has(cs)) errors.push(`garment "${g.slug}": references unknown category "${cs}"`);
}

if (errors.length) {
  console.error('\n  gen-seed: refusing to emit — the catalog does not satisfy the schema:\n');
  for (const e of errors) console.error(`    - ${e}`);
  console.error('');
  process.exit(1);
}

// ------------------------------------------------------------------- emit SQL
const L = [];
const w = (s = '') => L.push(s);

const variantCount = products.reduce((n, p) => n + p.variants.length, 0);
const priceRange = products.flatMap((p) => p.variants.map((v) => v.priceCents));
const median = (a) => {
  const s = [...a].sort((x, y) => x - y);
  const m = s.length >> 1;
  return s.length % 2 ? s[m] : Math.round((s[m - 1] + s[m]) / 2);
};

w('-- ====================================================================');
w('-- production-seed.sql — GENERATED FILE, DO NOT EDIT BY HAND');
w('--');
w('-- Regenerate:  node backend/scripts/gen-seed.mjs');
w('-- Verify:      node backend/scripts/gen-seed.mjs --check');
w('--');
w(`-- Source:       web/src/data/mock-products.json`);
w(`-- Products:     ${products.length}`);
w(`-- Variants:     ${variantCount}`);
w(`-- Price range:  Rs ${Math.min(...priceRange) / 100} - Rs ${Math.max(...priceRange) / 100}`);
w(`-- Median var.:  Rs ${median(priceRange) / 100}`);
w('--');
w('-- Replaces the previous hand-maintained seed, which carried 2 of 13 products');
w('-- and priced the hoodie at Rs 8,990 against a catalog price of Rs 3,499.');
w('-- ====================================================================');
w();
w('begin;');
w();

// --- taxonomy (idempotent upserts; these tables are small and stable) --------
w('-- ---------------------------------------------------------------------------');
w('-- 1. Master taxonomy');
w('-- ---------------------------------------------------------------------------');
w();

// Universes first: collections.universe_slug and products.universe_slug both FK
// to it, so it has to exist before either insert runs.
//
// The audit (docs/11 §4) found 12 hero/portal styling columns on this table —
// hero_headline, hero_lead_color, hero_ornament, etc. They are presentation, not
// taxonomy, and 7 of them had no seed source at all. They are NOT emitted here;
// the display copy lives in theme_tokens jsonb instead, so there is one source
// for a universe's look rather than twelve typed columns plus a JSON file.
w('insert into public.universes (');
w('  slug, name, tagline, lore, emblem_src, hero_image, drop_cadence, is_active,');
w('  order_num, theme_tokens, portal_title_color, lore_heading, hero_headline_case,');
w('  hero_vertical_text');
w(') values');
w(tax.universes
  .map((u) => {
    const order = u.order ?? u.order_num ?? 0;
    return `  (${q(u.slug)}, ${q(u.name)}, ${q(u.tagline ?? '')}, ${q(u.lore ?? '')}, ` +
      `${u.emblem_src ? q(u.emblem_src) : 'NULL'}, ${u.hero_image ? q(u.hero_image) : 'NULL'}, ` +
      `${q(u.drop_cadence ?? '')}, ${bool(u.is_active ?? true)}, ${num(order)}, ` +
      `${jsonb(u.theme_tokens ?? {})}, ${u.portal_title_color ? q(u.portal_title_color) : 'NULL'}, ` +
      `${u.lore_heading ? q(u.lore_heading) : 'NULL'}, ${q(u.hero_headline_case ?? 'sentence')}, ` +
      `${u.hero_vertical_text ? q(u.hero_vertical_text) : 'NULL'})`;
  })
  .join(',\n'));
w('on conflict (slug) do update set name = excluded.name, tagline = excluded.tagline, lore = excluded.lore, emblem_src = excluded.emblem_src, hero_image = excluded.hero_image, drop_cadence = excluded.drop_cadence, is_active = excluded.is_active, order_num = excluded.order_num, theme_tokens = excluded.theme_tokens, portal_title_color = excluded.portal_title_color, lore_heading = excluded.lore_heading, hero_headline_case = excluded.hero_headline_case, hero_vertical_text = excluded.hero_vertical_text;');
w();

w('insert into public.categories (slug, name, label, description, image, order_num) values');
w(products.length ? tax.categories
  .map((c, i) => `  (${q(c.slug)}, ${q(c.name)}, ${q(c.label ?? c.name)}, ${q(c.description ?? '')}, ${c.image ? q(c.image) : 'NULL'}, ${c.order ?? c.orderNum ?? i})`)
  .join(',\n') : '');
w('on conflict (slug) do update set name = excluded.name, label = excluded.label, description = excluded.description, image = excluded.image, order_num = excluded.order_num;');
w();

w('insert into public.garments (slug, name, category_slug, description, order_num) values');
w(tax.garments
  .map((g, i) => `  (${q(g.slug)}, ${q(g.name)}, ${q(g.categorySlug ?? g.category_slug)}, ${q(g.description ?? '')}, ${g.order ?? g.orderNum ?? i})`)
  .join(',\n'));
w('on conflict (slug) do update set name = excluded.name, category_slug = excluded.category_slug, description = excluded.description, order_num = excluded.order_num;');
w();

w('insert into public.collections (slug, name, tagline, description, universe_slug, featured, order_num) values');
w(tax.collections
  .map((c, i) => {
    // collections.json references universe "atelier", which has never existed in
    // universes.json — the FK rejects it. Universe-neutral pieces are exactly that:
    // neutral. Emitting NULL is truthful; inventing an "atelier" universe here
    // would resurrect the fictional-taxonomy problem this migration removes.
    const uni = c.universeSlug && uslugs.has(c.universeSlug) ? q(c.universeSlug) : 'NULL';
    return `  (${q(c.slug)}, ${q(c.name)}, ${q(c.tagline ?? '')}, ${q(c.description ?? '')}, ${uni}, ${bool(c.featured ?? false)}, ${c.order ?? c.orderNum ?? i})`;
  })
  .join(',\n'));
w('on conflict (slug) do update set name = excluded.name, tagline = excluded.tagline, description = excluded.description, universe_slug = excluded.universe_slug, featured = excluded.featured, order_num = excluded.order_num;');
w();

w('insert into public.motifs (id, universe_slug, name, meaning, symbol_notes, ip_cleared) values');
w(tax.motifs
  .map((m) => {
    const us = m.universeSlug ?? m.universe_slug;
    return `  (${q(m.id ?? m.slug)}, ${q(us)}, ${q(m.name)}, ${q(m.meaning ?? '')}, ${q(m.symbolNotes ?? m.symbol_notes ?? '')}, ${bool(m.ipCleared ?? m.ip_cleared ?? false)})`;
  })
  .join(',\n'));
w('on conflict (id) do update set universe_slug = excluded.universe_slug, name = excluded.name, meaning = excluded.meaning, symbol_notes = excluded.symbol_notes, ip_cleared = excluded.ip_cleared;');
w();

// --- products ---------------------------------------------------------------
w('-- ---------------------------------------------------------------------------');
w('-- 2. Products');
w('-- ---------------------------------------------------------------------------');
w();

const COLS = [
  'slug', 'name', 'subtitle', 'foreign_tagline', 'description',
  'category_slug', 'universe_slug', 'collection_slug', 'garment_type', 'gender',
  'motif_id', 'handcrafted', 'craft_techniques', 'edits', 'expression_score',
  'rating', 'review_count', 'tags', 'featured', 'customizable',
  'material', 'care', 'fit', 'fabric_gsm',
  // migration 20261024
  'country_of_origin', 'manufacturer_name', 'manufacturer_address', 'packed_by',
  'cod_available', 'delivery_days_min', 'delivery_days_max', 'return_window_days',
  'weight_grams', 'hsn_code', 'size_chart',
  // migration part D — marketplace attribute system
  'style_code', 'attributes', 'fit_notes', 'model_height_cm', 'model_worn_size',
  'package_length_mm', 'package_width_mm', 'package_height_mm',
];

for (const p of products) {
  w(`-- ${p.name}  (${p.universeSlug ?? 'atelier'} · ${p.categorySlug}/${p.garmentType})`);
  w('insert into public.products (');
  w(COLS.map((c) => `  ${c}`).join(',\n'));
  w(') values (');
  const vals = [
    q(p.slug), q(p.name), q(p.subtitle), p.foreignTagline ? q(p.foreignTagline) : 'NULL',
    q(p.description), q(p.categorySlug), p.universeSlug ? q(p.universeSlug) : 'NULL',
    p.collectionSlug ? q(p.collectionSlug) : 'NULL', p.garmentType ? q(p.garmentType) : 'NULL',
    q(p.gender ?? 'unisex'), p.motifId ? q(p.motifId) : 'NULL', bool(p.handcrafted ?? false),
    arr(p.craftTechniques), arr(p.edits), num(p.expressionScore),
    num(p.rating), num(p.reviewCount ?? 0), arr(p.tags), bool(p.featured ?? false),
    bool(p.customizable ?? false), arr(p.material), arr(p.care), p.fit ? q(p.fit) : 'NULL',
    p.fabricGsm ? q(p.fabricGsm) : 'NULL',
    q(p.countryOfOrigin), p.manufacturerName ? q(p.manufacturerName) : 'NULL',
    p.manufacturerAddress ? q(p.manufacturerAddress) : 'NULL',
    p.packedBy ? q(p.packedBy) : 'NULL',
    bool(p.codAvailable), num(p.deliveryDaysMin), num(p.deliveryDaysMax),
    num(p.returnWindowDays), num(p.weightGrams), p.hsnCode ? q(p.hsnCode) : 'NULL',
    jsonb(p.sizeChart),
    p.styleCode ? q(p.styleCode) : 'NULL',
    jsonb(p.attributes ?? {}),
    p.fitNotes ? q(p.fitNotes) : 'NULL',
    num(p.modelHeightCm), p.modelWornSize ? q(p.modelWornSize) : 'NULL',
    num(p.packageLengthMm), num(p.packageWidthMm), num(p.packageHeightMm),
  ];
  w(vals.map((v, i) => `  ${v}${i === vals.length - 1 ? '' : ','}`).join('\n'));
  w(') on conflict (slug) do update set');
  const upd = COLS.slice(1).map((c) => `  ${c} = excluded.${c}`).join(',\n');
  w(upd + ';');
  w();

  // images
  const images = p.images ?? [];
  if (images.length) {
    w(`delete from public.product_images where product_slug = ${q(p.slug)};`);
    w('insert into public.product_images (product_slug, src, alt, color, sort_order) values');
    w(images
      .map((im, i) => `  (${q(p.slug)}, ${q(im.src)}, ${q(im.alt ?? p.name)}, ${im.color ? q(im.color) : 'NULL'}, ${im.sortOrder ?? i})`)
      .join(',\n') + ';');
    w();
  }

  // variants
  w(`delete from public.variants where product_slug = ${q(p.slug)};`);
  w('insert into public.variants (sku, product_slug, color, color_hex, size, price_cents, compare_at_price_cents, status, quantity, barcode) values');
  w(p.variants
    .map((v) => `  (${q(v.sku)}, ${q(p.slug)}, ${q(v.color ?? 'Default')}, ${v.colorHex ? q(v.colorHex) : 'NULL'}, ${q(v.size ?? 'ONE')}, ${v.priceCents}, ${num(v.compareAtPriceCents)}, ${q(v.status ?? 'in-stock')}, ${num(v.quantity ?? 0)}, ${v.barcode ? q(v.barcode) : 'NULL'})`)
    .join(',\n') + ';');
  w();

  // embroidery
  const e = p.embroidery;
  if (e) {
    w(`delete from public.embroidery_details where product_slug = ${q(p.slug)};`);
    w('insert into public.embroidery_details (');
    w('  product_slug, technique, technique_label, artisan_hours, placement,');
    w('  thread_composition, motif_story, macro_image_src, macro_image_alt');
    w(') values (');
    w(`  ${q(p.slug)}, ${q(e.technique)}, ${q(e.techniqueLabel ?? e.technique)}, ${num(e.artisanHours)},`);
    w(`  ${arr(e.placement)}, ${q(e.threadComposition ?? '')}, ${q(e.motifStory ?? '')},`);
    w(`  ${e.macroImage?.src ? q(e.macroImage.src) : 'NULL'}, ${e.macroImage?.alt ? q(e.macroImage.alt) : 'NULL'}`);
    w(');');
    w();
  }
}

w('commit;');
w();

const sql = L.join('\n');
const stats = `${products.length} products, ${variantCount} variants, ${priceRange.length} priced points`;

if (CHECK) {
  let current = '';
  try {
    current = readFileSync(OUT, 'utf8');
  } catch {
    fail('production-seed.sql does not exist — run without --check to generate it');
  }
  if (current !== sql) {
    console.error(`\n  gen-seed --check: production-seed.sql is STALE (${stats}).`);
    console.error('  Re-run: node backend/scripts/gen-seed.mjs\n');
    process.exit(1);
  }
  console.log(`  gen-seed --check: up to date (${stats})`);
  process.exit(0);
}

writeFileSync(OUT, sql, 'utf8');

// Post-write self-verification: never report success without re-reading.
const written = readFileSync(OUT, 'utf8');
const prodInserts = (written.match(/insert into public\.products \(/g) ?? []).length;
const varRows = (written.match(/^  \('[^']*', '[^']*', '[^']*'/gm) ?? []).length;
if (prodInserts !== products.length) fail(`wrote ${prodInserts} product inserts, expected ${products.length}`);
if (!written.includes('commit;')) fail('output is missing the closing commit');

console.log(`  gen-seed: wrote ${OUT}`);
console.log(`  ${stats}`);
console.log(`  product inserts verified in file: ${prodInserts}`);
