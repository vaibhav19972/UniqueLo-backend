# UniqueLo — Backend Contract

**The single source of truth both `web/` and `mobile/` build against.**

If the backend changes shape, it changes here first. Both clients then update to match.
No client may invent a field, and no field may exist in a client without appearing here.

`products` has **44 columns** measured live (`contracts/live-columns.txt`).
There is no 45th: `intensity` was **retired 2026-10-31** with its migration
(`migrations/_archive/01_web_20261013_taxonomy_columns.sql`) because neither
client reads it as a column — both derive it from `expression_score`
(`contracts/parity-gaps.md` #2). Gated by `scripts/check-contract.mjs` (code +
this doc vs schema), `scripts/check-schema-parity.mjs` (schema.sql vs the
measured live shape) and `scripts/check-schema-completeness.mjs` (schema.sql vs
every table and column the migration chain creates).

---

## 1. Storage & access model

Supabase (Postgres + RLS + Storage). Clients never talk to Postgres directly — they read
through PostgREST and write through RPC functions.

| Client | Transport | Auth | Read path | Write path |
|---|---|---|---|---|
| `web/` | `@supabase/supabase-js` (`web/src/lib/data.ts`) | Supabase Auth session for admin; publishable key for reads | `select` with nested embeds | `rpc/place_order`; admin via authenticated session / `publish_product` |
| `mobile/` | Ktor HTTP (`mobile/.../data/SupabaseHttpClient.kt`) | publishable key, read-only | PostgREST `select` with `!inner` embeds | `rpc/quote_order` for every bag price; `rpc/place_order` to commit (legacy two-call REST fallback only if the RPC is absent) |

`web/src/lib/data.ts` is the **adapter**: it maps snake_case PostgREST rows (`RawProduct`)
into camelCase domain objects (`Product`). Mobile does the same in `Mappers.kt`.
Both adapters must produce the same domain shape — that equivalence is what this
document defines.

### Current hosted state (re-measured read-only, 2026-11-01)

Re-measured 2026-11-01. The 2026-10-25 reading recorded throughout this repo
("write path open", "admins absent", "20261031 pending") is **superseded**:
everything it called unapplied has landed, and the catalogue write path is
**closed**. The 2026-10-31 reading was accurate for what it measured; this pass
adds the rows it did not cover (`20261102`, `20261104`, the Edge Functions,
`20261105`) and corrects two claims it could not have known were false.

| Fact | Evidence |
|---|---|
| `20261024` trust/marketplace columns present | 44-column fingerprint |
| `rls` on catalogue; **anon writes refused** | `POST /rest/v1/garments` -> **`401 42501`** "new row violates row-level security policy". `POST /rest/v1/products` -> `400 23514` (the BEFORE trigger speaks first) — **but RLS refuses that INSERT too**: proven offline by dropping the triggers and retrying as `anon`, which yields "new row violates row-level security policy", with a superuser control insert succeeding. The trigger error is simply the first gate to answer, because Postgres runs BEFORE ROW triggers ahead of `WITH CHECK`. **No anon write hole.** |
| `admins` present -> `20261025` applied | `GET /rest/v1/admins` -> `200` (was `404 PGRST205`) |
| `customer_addresses`, `customer_wishlists`, `orders.user_id` -> `20261031` applied | all `200` |
| `coupons`, `shipping_rules`, `coupon_redemptions`, `variants.compare_at_ends_at`, `orders.cod_fee_cents` -> `20261101` applied | all `200`; `quote_order` returns a live quote |
| `orders.tracking_number` / `carrier` -> `20261102` **NOT applied** | both `400 42703 "column does not exist"`. `orders.status` being `200` is not evidence for this file — the migration is atomic and its own two columns are missing |
| `rpc/place_order` (p_order, p_items) | **deployed.** Correct call with a bad SKU -> `500 P0002 "Unknown or uncatalogued variant SKU"`. A **no-argument** probe returns `404 PGRST202`, which is PostgREST's "no function with those parameters", NOT evidence of absence — this false negative is what kept OA-1 open in the mobile audits |
| `rpc/quote_order` | `400 22023 "A bag needs at least one item"`; real call -> 89900 + 9900 = **99800** |
| `rpc/publish_product` installed, not anon-executable | `401 42501` |
| `payment_intents` present -> `20261104` applied | `GET /rest/v1/payment_intents` -> `401 42501 permission denied` (table exists, RLS refuses anon) |
| Razorpay Edge Functions live | `razorpay-create-order` -> `200`, returns a gateway order id; `razorpay-verify` -> `200`. **Hosted is on `rzp_live_` keys.** |
| `orders.payment_method` / `payment_ref` -> `20261105` **APPLIED** | both `200`; `payment_method` `not null`, `orders_payment_method_valid` `convalidated=true`, `idx_orders_payment_ref` present as a UNIQUE partial index, and `place_order`'s stored body writes `payment_method` and does **not** read `payment_ref` from `p_order` |
| `orders` row count | **1**, not 0 — a real COD order `b9b72801` (₹4,696, `confirmed-cod`) from 2026-10-29. Corrected 2026-11-01 from an earlier "0 rows": the anon probe returns `[]` because RLS hides rows from anonymous callers, **not** because the table is empty. An RLS-filtered empty array is not a count |

**The `20261025` → catalogue lockdown and the `20261031` customer-account
migrations are both in force.** `contracts/write-path-policies.md` still carries
an "ACCEPTED RISK — write path open" banner from 2026-10-25; that risk is
**closed** as of 2026-10-31 and the banner is annotated accordingly.

**`orders` holds 1 real row, not 0.** An earlier version of this paragraph said
"Orders are being received on web and mobile" — which was wrong. It was then
corrected to "0 rows" — which was **also wrong**, and wrong the same way my
catalogue probes were: an unauthenticated `GET /rest/v1/orders` returns `[]`
because RLS hides every row from anon, and I read that empty array as an empty
table. The actual figure, read with the service role, is one COD order from
2026-10-29 (`b9b72801`, `confirmed-cod`, ₹4,696).

An RLS-filtered `[]` is indistinguishable from an empty table from outside.
Any future "table is empty" claim in this repo must come from a count taken
with a role that can see rows.


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
| `admins` | `user_id` | admin allowlist | Created by `20261025`. Gate for every catalogue/asset write |
| `customer_addresses` | `uuid` | saved delivery addresses | Created by `20261031`. `pincode` is 6-digit text; max one `is_default` per user |
| `customer_wishlists` | `(user_id, product_slug)` | cloud saved pieces | Created by `20261031`. **No FK to `products`** — a delisted product must not erase a saved piece (D-18) |
| `coupons` | `code` | discount promotion definitions | Created by `20261101`. Percentage, fixed cents, or free shipping |
| `shipping_rules` | `id` | carriage tiers & COD terms | Created by `20261101`. Free delivery threshold, flat rate, COD surcharge |
| `coupon_redemptions` | `id` | redemption audit log | Created by `20261101`. Enforces per-user / per-coupon limits at `place_order` |
| `payment_intents` | `id` | gateway payment attempts | Created by `20261104`. Links provider order/payment to `client_order_id` |

### Authorization model (authoritative)

| Principal | Catalogue read | Catalogue write | Order write | Order read |
|---|---|---|---|---|
| `anon` | yes (RLS `using(true)`) | **no** | `rpc/place_order` only | `rpc/get_order_details(id, email)` only |
| `authenticated` (customer) | yes | **no** — `is_admin()` false | `rpc/place_order` only | own rows (`orders.user_id = auth.uid()`) |
| `authenticated` (admin) | yes | yes (`is_admin()`) | `rpc/place_order` only | own rows |

`orders.user_id` is **derived server-side** by `place_order` from `auth.uid()`.
A `user_id` in the RPC payload is ignored. Guest checkout sends none and lands
`user_id = null`; guests are never visible to any signed-in user.

There is no client INSERT path into `orders`/`order_items` — the legacy anon
INSERT policies were revoked by `20261031`. `place_order` is `SECURITY DEFINER`,
so it writes without them.

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

**Order status vocabulary — ENFORCED since `20261102`.** `orders.status` carries
`orders_status_valid`, so anything outside this set is refused by the database:

| Status | Set by | Meaning |
|---|---|---|
| `pending` | *(reserved — no writer yet)* | reserved, not yet paid. **Nothing writes this today**; it exists so the payment gateway does not need a second migration. Do not build UI that assumes it appears |
| `reserved` | legacy mobile RPC | stock held, unconfirmed |
| `confirmed` | `place_order` (prepaid) | paid or pay-on-ship agreed |
| `confirmed-cod` | `place_order` (`payment_method='cod'`) | cash on delivery agreed |
| `processing` | admin | being packed |
| `shipped` | admin | with courier. **`tracking_number` + `carrier` are required** — `orders_shipped_needs_tracking` refuses `shipped` without both (`20261103`). `delivered` is exempt so a hand-delivered order can complete |
| `delivered` | admin | received |
| `cancelled` | admin | void |

The column is `not null`. `tracking_number` and `carrier` are a pair: setting one
without the other violates `orders_tracking_pairs_with_carrier`.

**Error surface:** a `raise exception` aborts with no partial order. Clients show the
message verbatim and must not retry blindly (stock may have moved). The empty-items / invalid coupon guard
is `22023`, out of stock is `P0001`, unknown SKU is `P0002`.

---

## 7. Migrations

`backend/migrations/` is ordered; both clients share this single chain.

| File | Origin | Purpose | Applied on hosted (2026-10-31) |
|---|---|---|---|
| `01_web_20261013_taxonomy_columns.sql` | web | ~~`intensity`, `craft_techniques`, `edits`~~ | **RETIRED** — moved to `migrations/_archive/`; `intensity` is not in the live 44-column shape and both clients derive it from `expression_score` |
| `20260101000000_place_order_fn.sql` | mobile | order placement RPC | **yes** (`22023` guard) |
| `20260102000000_lock_catalogue_writes.sql` | mobile | full no-auth lockdown draft | replay history |
| `20260103000000_lockdown_interim.sql` | mobile | interim lockdown | replay history |
| `20260104000000_lockdown_auth_admin.sql` | mobile | authenticated-admin lockdown | **superseded by `20261031` §5b**, which drops its permissive `"Authenticated admin write"` policies. Its blanket-write hole is closed; the signed-in-customer probe (OA-6) is still open |
| `20261024_data_model_trust_fields.sql` | web | drops fabricated fields; adds trust + marketplace columns, `attribute_definitions`, triggers | **yes** |
| `20261025_admin_write_policies.sql` | web | `admins` + `is_admin()` + write policies | **yes** — `admins` → `200`; anon `POST /garments` → `401 42501` |
| `20261026_catalogue_garment_types.sql` | web | garment registry rows | **yes** |
| `20261026_publish_product.sql` | web | transactional publish RPC | installed (anon denied) |
| `20261027_product_images_bucket.sql` | web | storage bucket + policies | bucket recreated (`ff1f052`) |
| `20261030_harden_place_order.sql` | backend | server-side prices, coupon validation, atomic stock decrement | **yes** (verified 2026-10-29: bogus SKU → `P0002`) |
| `20261031_customer_accounts.sql` | backend | `orders.user_id`, `customer_addresses`, `customer_wishlists`, storage re-gate, RPC-only order writes | **yes** — `customer_addresses`, `customer_wishlists`, `orders.user_id` all `200`; proven 13/13 on a PG16 replica (`scripts/verify-customer-accounts.sql`) |
| `20261032_order_items_read.sql` | backend | RLS policy for customers to view own `order_items` | **yes** — allows order history line item expansion under `orders.user_id = auth.uid()` |
| `20261101_checkout_pricing.sql` | backend | `coupons`, `shipping_rules`, `coupon_redemptions`, `price_cart`/`quote_order` RPCs, compare_at sale expiry, COD surcharge | **yes** — `quote_order` returns live quotes |
| `20261102_order_lifecycle.sql` | backend | `orders_status_valid` CHECK, `orders.tracking_number`, `orders.carrier` columns, status transitions | **unapplied on hosted** (re-measured 2026-11-01; atomic file pending deploy) |
| `20261103_admin_order_access.sql` | backend | Admin SELECT/UPDATE policies on orders, `orders_shipped_needs_tracking` CHECK constraint | **unapplied on hosted** (depends on 20261102) |
| `20261104_razorpay_payments.sql` | backend | `payment_intents` table, indices, RLS enabled, Deno Edge Functions | **yes** — hosted live with `rzp_live_` keys |
| `20261105_order_payment_identity.sql` | backend | `orders.payment_method`, `orders.payment_ref`, partial unique index, place_order payment stamping | **unapplied on hosted** (proven locally in `verify-order-payment.sh`) |

**Two findings that changed the deploy order** (both resolved by `20261031`; kept as the record of why the order was what it was):

1. `20261025` alone does **not** close the write path. `20260104` created
   `"Authenticated admin write <t>"` (`using (true)`) and `20261025` only drops
   `"Admins write <t>"`. Per policies OR together, so any signed-in user keeps
   full catalogue write. `20261031` §5b drops the legacy policies — **the
   lockdown is only real after `20261031` runs**, not after `20261025`.
2. `20261025` never touches `storage.objects`. The image-upload policies from
   `20260104` are gated on `to authenticated` alone, so customer sign-up would
   hand out delete rights on catalogue photography. `20261031` §5 re-gates them
   on `is_admin()`.

**Ordering (fixed 2026-10-31).** `01_web_*` sorted first lexically but was authored
after the mobile chain; it is retired. `20261026_catalogue_garment_types.sql` inserts
`garments` rows with `category_slug` foreign keys, and `categories` is empty until
`production-seed.sql` runs — while the seed must run **last**, because it writes
`variants.compare_at_ends_at` and `orders.cod_fee_cents`, both created by `20261101`.
That ordering caveat was therefore impossible to satisfy, and the chain aborted with
`garments_category_slug_fkey` when first actually executed. The migration now inserts
the three category rows it depends on (`on conflict do nothing`), so it is
self-sufficient. Load order is simply `local-bootstrap` (plain Postgres only) →
`schema.sql` → `migrations/` sorted → `production-seed.sql`; the whole chain is proven
green on PostgreSQL 16.15.

Verify with `scripts/check-schema-completeness.mjs`, `check-schema-parity.mjs` and
`check-contract.mjs` after any change.

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
