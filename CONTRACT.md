# UniqueLo — Backend Contract

**The single source of truth both `web/` and `mobile/` build against.**

If the backend changes shape, it changes here first. Both clients then update to match.
No client may invent a field, and no field may exist in a client without appearing here.

`products` has **44 columns** measured live (`contracts/live-columns.txt`);
`migrations/01_web_20261013` adds `intensity` for a 45th once applied. Gated by
`scripts/check-contract.mjs` (code + this doc vs schema) and
`scripts/check-schema-parity.mjs` (schema.sql vs the measured live shape).

---

## 1. Storage & access model

Supabase (Postgres + RLS + Storage). Clients never talk to Postgres directly — they read
through PostgREST and write through RPC functions.

| Client | Transport | Auth | Read path | Write path |
|---|---|---|---|---|
| `web/` | `@supabase/supabase-js` (`web/src/lib/data.ts`) | Supabase Auth session for admin; publishable key for reads | `select` with nested embeds | `rpc/place_order`; admin via authenticated session / `publish_product` |
| `mobile/` | Ktor HTTP (`mobile/.../data/SupabaseHttpClient.kt`) | publishable key, read-only | PostgREST `select` with `!inner` embeds | `rpc/place_order` (legacy two-call REST fallback only if the RPC is absent) |

`web/src/lib/data.ts` is the **adapter**: it maps snake_case PostgREST rows (`RawProduct`)
into camelCase domain objects (`Product`). Mobile does the same in `Mappers.kt`.
Both adapters must produce the same domain shape — that equivalence is what this
document defines.

### Current hosted state (measured read-only, 2026-10-25)

| Fact | Evidence |
|---|---|
| 20261024 trust/marketplace columns present | 44-column fingerprint; `style_code`, `attributes`, `cod_available` all `200` |
| `is_mock`, `intensity`, `sold_count`, `batch_*`, `craft_*` absent | `42703` on `is_mock` and `intensity` |
| `rpc/place_order` **installed** | empty-items probe → `400 22023 "place_order requires at least one order item"`; **must post `{"p_order":{…},"p_items":[]}`** — a bare `{"items":[]}` returns `404 PGRST202`, which does not mean the function is missing |
| `rpc/publish_product` installed, **not anon-executable** | `401 42501 permission denied for function`, posting `{"p_product":{},"p_variants":[]}` |
| `rpc/get_order_details` installed | `200 null` for an unknown uuid/email |
| `admins` table **absent** → `20261025` unapplied | `404 PGRST205` |
| `01_web_20261013` (taxonomy) unapplied | `products.intensity` → `42703` |

Orders are being received on web and mobile (owner-confirmed 2026-10-25) through the
installed RPC. The catalogue write path is still permissive because `20261025` is not
applied — the accepted risk in `contracts/write-path-policies.md` stands.

---

## 2. Table ownership

| Table | Primary key | Owns | Notes |
|---|---|---|---|
| `universes` | `slug` | theme tokens, hero copy | Cosmetic + IA only |
| `motifs` | `id` | character lore, `ip_cleared` | `ip_cleared=false` must never render |
| `categories` | `slug` | nav doors, description | |
| `garments` | `slug` | garment registry facet | Maps to `products/` `garment_type` |
| `collections` | `slug` | drop membership | |
| `products` | `slug` | identity, taxonomy facets, trust/logistics, copy | Read model root |
| `variants` | `sku` | price, stock, colour, size, `barcode` | **`sku` is the inventory key** |
| `product_images` | `uuid` | `src`, `alt`, `sort_order` 0–5 | Slot contract, §4 |
| `embroidery_details` | `uuid` | technique provenance | 1:1 with product (`unique`) |
| `reviews` | `uuid` | social proof | `rating`/`review_count` are caches |
| `newsletter_subscribers` | `uuid` | email capture | |
| `orders` / `order_items` | `uuid` | order ledger | Written only via `place_order` |
| `attribute_definitions` | `key` | per-garment attribute contract | Created by `20261024`; values in `products.attributes` |
| `admins` | `user_id` | admin allowlist | Created by `20261025` — **not applied on hosted** |

**Naming rule:** database is `snake_case`; clients are `camelCase`; the adapter translates.
A field is named exactly once in the DB and exactly once per client — never renamed in transit
without a mapping entry.

---

## 3. Canonical Product read model

The nested shape both clients consume. This is the **parity contract** — web builds
`Product` from it, mobile builds `Product` from it, and they must be indistinguishable.

```
Product
├─ slug                    text   PK
├─ name                    text   NOT NULL
├─ subtitle                text   NOT NULL
├─ foreign_tagline         text   NULL      → foreignTagline
├─ description             text   NOT NULL
├─ category_slug           text   FK → categories.slug  (SET NULL)
├─ universe_slug           text   FK → universes.slug   (SET NULL)  NULL = Atelier base line
├─ collection_slug         text   FK → collections.slug (SET NULL)
├─ garment_type            text   FK → garments.slug    (SET NULL)
├─ gender                  text   NOT NULL  CHECK men|women|unisex  (default unisex)
├─ motif_id                text   FK → motifs.id        (SET NULL)
├─ handcrafted             bool   NOT NULL  default false
├─ craft_techniques        text[] NOT NULL  default {}
├─ edits                   text[] NOT NULL  default {}
├─ expression_score        smallint NOT NULL CHECK 1..5  default 3
├─ rating                  numeric(3,1) NOT NULL default 5.0     cache, never hand-authored
├─ review_count            int    NOT NULL  default 0           cache, never hand-authored
├─ tags                    text[] NOT NULL  default {}
├─ featured                bool   NOT NULL  default false
├─ customizable            bool   NOT NULL  default false
├─ material                text[] NOT NULL  default {}
├─ care                    text[] NOT NULL  default {}
├─ fit                     text   NULL
├─ fabric_gsm              text   NULL
├─ country_of_origin       char(2) NOT NULL default 'IN'  CHECK ISO-3166
├─ manufacturer_name       text   NULL
├─ manufacturer_address    text   NULL
├─ packed_by               text   NULL
├─ cod_available           bool   NOT NULL  default true
├─ delivery_days_min       smallint NULL
├─ delivery_days_max       smallint NULL
├─ return_window_days      smallint NOT NULL default 7   (0 = non-returnable)
├─ weight_grams            integer NULL
├─ hsn_code                text   NULL  CHECK [0-9]{4,8}
├─ size_chart              jsonb  NULL
├─ attributes              jsonb  NOT NULL default {}   keyed by attribute_definitions.key
├─ style_code              text   NULL  UNIQUE           design-family identity
├─ fit_notes               text   NULL
├─ model_height_cm         smallint NULL
├─ model_worn_size         text   NULL
├─ package_length_mm       smallint NULL
├─ package_width_mm        smallint NULL
├─ package_height_mm       smallint NULL
├─ created_at              timestamptz NOT NULL
│
├─ variants[]              → variants  (embedded, ordered by size then colour)
│   ├─ sku                      text PK
│   ├─ product_slug             text FK
│   ├─ color, color_hex         text NOT NULL
│   ├─ size                     text NOT NULL
│   ├─ price_cents              int  NOT NULL
│   ├─ compare_at_price_cents   int NULL
│   ├─ status                   text CHECK in-stock|low-stock|out-of-stock
│   ├─ quantity                 int  default 10
│   └─ barcode                  text NULL UNIQUE   (added 20261024)
│
├─ product_images[]        → product_images (embedded, ORDER BY sort_order ASC)
│   ├─ id uuid, product_slug, src NOT NULL, alt NOT NULL, color NULL, sort_order 0..5
│
└─ embroidery_details      → embroidery_details (embedded, 1:1, nullable)
    ├─ technique, technique_label, thread_composition, motif_story  NOT NULL
    ├─ artisan_hours int, placement text[]
    └─ macro_image_src, macro_image_alt  NULL
```

### Client-side naming deltas (the only permitted ones)

| DB column | Web (`Product`) | Mobile (`ProductDto`) |
|---|---|---|
| `product_images` | `images` | `productImages` |
| `embroidery_details` | `embroidery` | `embroideryDetails` |
| `craft_techniques` | `craftTechniques` | `craftTechniques` |

Web additionally derives fields that are **not** columns:

- `intensity` — uses the column when present; `score <= 2 → quiet`, `3 → balanced`, `>= 4 → loud`
- `characterIds` — forward-compat; single-motif rows read as `[motifId]`

Mobile does **not** derive `intensity` today. That is a known parity gap
(`contracts/parity-gaps.md`).

---

## 4. Image slot contract (frozen)

`product_images.sort_order` is a **semantic slot index**, not a display order.

| `sort_order` | Slot | Source | Gate |
|---|---|---|---|
| 0 | `hero-front` | generate | — |
| 1 | `on-model-full` | generate | — |
| 2 | `flat-lay` | generate | — |
| 3 | `embroidery-macro` | generate | **human review required** |
| 4 | `placement-detail` | generate | — |
| 5 | `lifestyle-atelier` | generate | — |

Every row requires non-empty `alt`. Six images per SKU, in order, no gaps. Clients may
render fewer than six only if fewer exist — never reorder to fill a gap.

---

## 5. Catalogue provenance — there is no mock flag

There is **no `is_mock` column and no mock flag in this contract**. It was retired on
2026-10-25: nothing consumed it, the column never existed in the schema, and catalogue
size is a property of the data, not of a boolean.

- The database holds whatever the pipeline published (`products/` → `publish.py` /
  `upload.py`) plus `production-seed.sql`.
- `web/src/data/mock-products.json` is a **client-side fallback** used only when Supabase
  is unconfigured or a read fails. It is not a second catalogue, and nothing marks it at
  runtime.
- Either side may hold any number of products; the contract does not distinguish them.

Old parity rows 0/1/6 are closed in `contracts/parity-gaps.md`.

---

## 6. Write contract — orders

Single entry point: `rpc/place_order`. No client inserts into `orders`/`order_items`.

**Request**

```json
{
  "p_customer_name":    "string, required",
  "p_customer_email":   "string, required, valid email",
  "p_subtotal_cents":   "int, required >= 0",
  "p_discount_cents":   "int, default 0",
  "p_shipping_cents":   "int, default 0",
  "p_total_cents":      "int, required >= 0",
  "p_coupon_code":      "string, nullable",
  "p_gift_note":        "string, nullable",
  "p_shipping_address": "jsonb, nullable",
  "p_items": [
    { "product_slug": "", "variant_sku": "", "product_name": "",
      "color": "", "size": "", "quantity": 1, "price_cents": 0,
      "customization": {} }
  ]
}
```

**Guarantees** (clients rely on these, do not re-implement):

1. **Authoritative Pricing & Catalog SKUs:** Prices are re-read server-side from `variants`. Client `price_cents` is ignored. Every line item must reference a registered SKU in `public.variants` — uncatalogued SKUs abort with `P0002`.
2. **Atomic Stock Decrement:** Stock is locked via `FOR UPDATE` and decremented atomically across all variants in the order; insufficient stock aborts the whole transaction with `P0001`.
3. **Server-Side Discount & Shipping Derivation:** Disallows arbitrary client discounts. Unrecognized coupon codes abort with `22023`. Supported atelier coupons (`ATELIER10`, `GOBONKERS15`, `BONKERS20`, `NEEDLECRAFT`, `FREESHIP`) are calculated server-side. Shipping is calculated or clamped server-side.
4. **Authoritative Totals:** `orders` header stores server-calculated `subtotal_cents`, `discount_cents`, `shipping_cents`, and `total_cents`.
5. **SECURITY DEFINER:** anon may call it, but only it may write these tables.

**Order Status Vocabulary:**
- `confirmed-cod` — Placed with Cash on Delivery payment
- `confirmed` — Placed with prepaid electronic payment (UPI, card, etc.)
- `reserved` — Hold session / pre-payment reservation
- `processing` / `shipped` / `delivered` / `cancelled` — Post-order fulfillment lifecycle

**Error surface:** a `raise exception` aborts with no partial order. Clients show the
message verbatim and must not retry blindly (stock may have moved). The empty-items / invalid coupon guard
is `22023`, out of stock is `P0001`, unknown SKU is `P0002`.

---

## 7. Migrations

`backend/migrations/` is ordered; both clients share this single chain.

| File | Origin | Purpose | Applied on hosted (2026-10-25) |
|---|---|---|---|
| `01_web_20261013_taxonomy_columns.sql` | web | `intensity`, `craft_techniques`, `edits` | **no** (`intensity` → 42703) |
| `20260101000000_place_order_fn.sql` | mobile | order placement RPC | **yes** (`22023` guard) |
| `20260102000000_lock_catalogue_writes.sql` | mobile | full no-auth lockdown draft | replay history |
| `20260103000000_lockdown_interim.sql` | mobile | interim lockdown | replay history |
| `20260104000000_lockdown_auth_admin.sql` | mobile | authenticated-admin lockdown | not in force (write path open) |
| `20261024_data_model_trust_fields.sql` | web | drops fabricated fields; adds trust + marketplace columns, `attribute_definitions`, triggers | **yes** |
| `20261025_admin_write_policies.sql` | web | `admins` + `is_admin()` + write policies | **no** (`admins` → 404) |
| `20261026_catalogue_garment_types.sql` | web | garment registry rows | **yes** |
| `20261026_publish_product.sql` | web | transactional publish RPC | installed (anon denied) |
| `20261027_product_images_bucket.sql` | web | storage bucket + policies | bucket recreated (`ff1f052`) |
| `20261030_harden_place_order.sql` | backend | server-side prices, coupon validation, atomic stock decrement | pending deploy |

**Ordering caveat:** `01_web_*` sorts first lexically but was authored after the mobile
chain. `schema.sql` carries the baseline shape. Note that `20261026_catalogue_garment_types.sql`
has foreign keys referencing `categories(slug)`, so on a fresh database, categories must
be seeded before running `20261026` or apply `production-seed.sql` after initial schema setup.
Verify with `scripts/check-schema-parity.mjs` and `scripts/check-contract.mjs` after any
change.

---

## 8. Ground truth files

| Concern | File |
|---|---|
| Full DDL (bootstrap) | `backend/schema.sql` |
| Measured live products shape | `backend/contracts/live-columns.txt` |
| Dev seed (legacy, local-only) | `backend/seed.sql` |
| Production baseline (generated) | `backend/production-seed.sql` |
| Migration chain | `backend/migrations/` |
| Client types | `web/src/lib/data.ts`, `mobile/.../data/SupabaseDtos.kt` |
| Known divergences | `backend/contracts/parity-gaps.md` |
| Write-path state + policy order | `backend/contracts/write-path-policies.md` |
| Gates | `scripts/check-contract.mjs`, `scripts/check-schema-parity.mjs`, `scripts/gen-seed.mjs --check` |
