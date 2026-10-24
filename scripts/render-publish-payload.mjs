#!/usr/bin/env node
/**
 * Extract the panel's REAL publish payload and execute it against Postgres.
 *
 * The payload is built inside a React component, so nothing typechecks it against
 * the SQL function and no build step exercises it. This extracts the object
 * literal from buildPublishPayload(), substitutes the component's state with
 * representative values, and prints JSON the shell can hand to psql.
 *
 * A drift here is invisible: the panel renders, the button clicks, and the RPC
 * rejects at runtime with a column mismatch the user sees as "Publish Failed".
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const REPO = process.env.UL_REPO || resolve(process.cwd(), '..');
const ADMIN = resolve(REPO, 'web/src/pages/Admin.tsx');
const src = readFileSync(ADMIN, 'utf8');

// --- locate buildPublishPayload() ---
const start = src.indexOf('const buildPublishPayload = () => {');
if (start === -1) {
  console.error('could not find buildPublishPayload in Admin.tsx');
  process.exit(1);
}
// The function ends at the first "\n  };" after the balanced brace of its body.
let depth = 0, i = src.indexOf('{', start), end = -1;
for (let j = i; j < src.length; j++) {
  if (src[j] === '{') depth++;
  else if (src[j] === '}') { depth--; if (depth === 0) { end = j; break; } }
}
const body = src.slice(i, end + 1);

// --- the component state the payload reads ---
const state = {
  slug: 'panel-test-tee',
  name: 'Panel Test Tee',
  subtitle: 'Published from the panel',
  foreignTagline: '',
  description: 'Verifying the panel payload against publish_product.',
  categorySlug: '',
  universeSlug: 'itihaas',
  collectionSlug: '',
  garmentType: 'tee',
  gender: 'unisex',
  motifId: '',
  handcrafted: true,
  selectedExpressionScore: 4,
  selectedMoods: [],
  tagsInput: 'test, panel',
  featured: false,
  customizable: false,
  materialsInput: 'cotton',
  careInput: 'cold wash',
  fit: 'relaxed',
  styleCode: 'UL-PANEL-001',
  countryOfOrigin: 'IN',
  manufacturerName: '',
  manufacturerAddress: '',
  packedBy: '',
  codAvailable: true,
  deliveryDaysMin: 3,
  deliveryDaysMax: 7,
  returnWindowDays: 7,
  weightGrams: 450,
  hsnCode: '6205',
  attributes: {
    pattern: 'solid', neck_type: 'round', sleeve_length: 'short',
    occasion: 'casual', fabric_composition: '100% cotton',
  },
  fitNotes: '',
  modelHeightCm: null,
  modelWornSize: '',
  packageLengthMm: null,
  packageWidthMm: null,
  packageHeightMm: null,
  slotImages: [
    { src: '/images/panel-1.jpg', alt: 'Panel 1' },
    { src: '/images/panel-2.jpg', alt: 'Panel 2' },
  ],
  variants: [
    { sku: 'PANEL-S', color: 'Red', colorHex: '#C00', size: 'S', price: 1299, status: 'in-stock', quantity: 5, barcode: '8901234567001' },
    { sku: 'PANEL-M', color: 'Red', colorHex: '#C00', size: 'M', price: 1299, status: 'in-stock', quantity: 8, barcode: '8901234567002' },
  ],
  technique: 'aari',
  techniqueLabel: 'Aari',
  artisanHours: 12,
  placementInput: 'chest',
  threadComposition: 'silk',
  motifStory: 'A test motif.',
};

// Rewrite the body so it is evaluable: forward-declare every identifier the
// component would have provided, then return the object literal.
const names = Object.keys(state);
const decls = names
  .map((k) => `const ${k} = ${JSON.stringify(state[k])};`)
  .join('\n');

// The body is `{ return { ... }; }` — strip the braces so we can wrap it.
const inner = body.slice(1, -1);

const evalSrc = `
${decls}
${inner}
`;

const payload = new Function(evalSrc)();

// --- sanity: the RPC reads these keys; flag any it will not find ---
const required = [
  'slug', 'name', 'subtitle', 'description', 'gender', 'handcrafted',
  'expression_score', 'attributes', 'cod_available', 'return_window_days',
  'country_of_origin', 'images', 'embroidery',
];
const missing = required.filter((k) => !(k in payload.product));
if (missing.length) {
  console.error(`payload.product is missing keys the RPC reads: ${missing.join(', ')}`);
  process.exit(1);
}
if (!Array.isArray(payload.variants) || payload.variants.length === 0) {
  console.error('payload.variants is empty');
  process.exit(1);
}
const vMissing = ['sku', 'color', 'size', 'price_cents'].filter((k) => !(k in payload.variants[0]));
if (vMissing.length) {
  console.error(`payload.variants[0] is missing: ${vMissing.join(', ')}`);
  process.exit(1);
}

console.log(JSON.stringify(payload));
