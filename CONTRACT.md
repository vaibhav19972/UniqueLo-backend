# UniqueLo — Backend Contract

**The single source of truth both `web/` and `mobile/` build against.**

If the backend changes shape, it changes here first. Both clients then update to match.
No client may invent a field, and no field may exist in a client without appearing here.

---

## 1. Storage & access model

Supabase (Postgres + RLS + Storage). Clients never talk to Postgres directly — they read
through PostgREST and write through RPC functions.

| Client | Transport | Auth | Read path | Write path |
|---|---|---|---|---|
| `web/` | `@supabase/supabase-js` (`web/src/lib/data.ts`) | Supabase Auth session | `select` with nested embeds | `rpc/place_order` + authenticated admin |
| `mobile/` | Ktor HTTP (`mobile/.../data/SupabaseHttpClient.kt`) | Anon key, read-only | PostgREST `select` with `!inner` embeds | `rpc/place_order` only |

`web/src/lib/data.ts` is the **adapter**: it maps snake_case PostgREST rows (`RawProduct`)
into camelCase domain objects (`Product`). Mobile does the same in `Mappers.kt`.
Both adapters must produce the same domain shape — that equivalence is what this
document defines.

---

## 2. Table ownership

| Table | Primary key | Owns | Notes |
|---|---|---|---|
| `universes` | `slug` | theme tokens, hero copy | Cosmetic + IA only |
| `motifs` | `id` | character lore, `ip_cleared` | `ip_cleared=false` must never render |
| `categories` | `slug` | nav doors, description | |
| `garments` | `slug` | garment registry facet | Maps to `catalog/*/SKU.md` "garment" |
| `collections` | `slug` | drop membership | |
| `products` | `slug` | identity, taxonomy facets, copy | Read model root |
| `variants` | `sku` | price, stock, colour, size | **`sku` is the inventory key** |
| `product_images` | `uuid` | `src`, `alt`, `sort_order` 0–5 | Slot contract, §4 |
| `embroidery_details` | `uuid` | technique provenance | 1:1 with product (`unique`) |
| `reviews` | `uuid` | social proof | |
| `newsletter_subscribers` | `uuid` | email capture | |
| `orders` / `order_items` | `uuid` | order ledger | Written only via `place_order` |

**Naming rule:** database is `snake_case`; clients are `camelCase`; the adapter translates.
A field is named exactly once in the DB and exactly once per client — never renamed in transit
without a mapping entry.

---

## 3. Canonical Product read model

The nested shape both clients consume. This is the **parity contract** — web builds
`Product` from it, mobile builds `Product` from it, and they must be indistinguishable.

```
Product
├─ slug                 text   PK
├─ name                 text   NOT NULL
├─ subtitle             text   NOT NULL
├─ foreign_tagline      text   NULL      → foreignTagline
├─ description          text   NOT NULL
├─ category_slug        text   FK → categories.slug  (SET NULL)
├─ universe_slug        text   FK → universes.slug   (SET NULL)  NULL = Atelier base line
├─ collection_slug      text   FK → collections.slug (SET NULL)
├─ garment_type         text   FK → garments.slug    (SET NULL)
├─ gender               text   NOT NULL  CHECK men|women|unisex   (default unisex)
├─ motif_id             text   FK → motifs.id        (SET NULL)
├─ handcrafted          bool   NOT NULL  default false
├─ craft_techniques     text[] NOT NULL  default {}
├─ edits                text[] NOT NULL  default {}
├─ expression_score     smallint NOT NULL CHECK 1..5  default 3
├─ expression_slug      text   NOT NULL  default 'cult'
├─ intensity            text   NOT NULL  default 'balanced'   (added 2026-10-13)
├─ rating               numeric(3,1) NOT NULL default 5.0
├─ review_count         int    NOT NULL  default 0
├─ sold_count           text   NULL
├─ tags                 text[] NOT NULL  default {}
├─ featured             bool   NOT NULL  default false
├─ customizable         bool   NOT NULL  default false
├─ material             text[] NOT NULL  default {}
├─ care                 text[] NOT NULL  default {}
├─ fit                  text   NULL
├─ batch_number         int    default 1
├─ batch_total          int    default 50
├─ craft_region         text   NULL
├─ craft_cluster        text   NULL
├─ fabric_gsm           text   NULL
├─ created_at           timestamptz NOT NULL
│
│  ⚠ NOT IN schema.sql TODAY — seed.sql inserts these and a fresh build fails:
│    is_mock   boolean  ← §5 depends on it
│    vibes     text[]   ← legacy taxonomy, superseded by craft_techniques/edits
│    moods     text[]   ← legacy taxonomy, superseded by edits
│  See contracts/parity-gaps.md #0 and contracts/schema-drift.md
│
├─ variants[]           → variants     (embedded, ordered by size then colour)
│   ├─ sku                   text PK
│   ├─ product_slug          text FK
│   ├─ color, color_hex      text NOT NULL
│   ├─ size                  text NOT NULL
│   ├─ price_cents           int  NOT NULL
│   ├─ compare_at_price_cents int NULL
│   ├─ status                text CHECK in-stock|low-stock|out-of-stock
│   └─ quantity              int  default 10
│
├─ product_images[]     → product_images (embedded, ORDER BY sort_order ASC)
│   ├─ id uuid, product_slug, src NOT NULL, alt NOT NULL, color NULL, sort_order 0..5
│
└─ embroidery_details   → embroidery_details (embedded, 1:1, nullable)
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

- `intensity` — derived when absent: `score <= 2 → quiet`, `3 → balanced`, `>= 4 → loud`
- `characterIds` — forward-compat; single-motif rows read as `[motifId]`
- `isMock` — denormalised convenience flag (see §5)

Mobile does **not** derive `intensity` today. That is a known parity gap, tracked in
`contracts/parity-gaps.md`.

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

## 5. The mock / real catalogue boundary

`products.is_mock` separates seed-derived display rows from real sellable SKUs.

- `is_mock = true` → mock catalogue. Web storefront renders these pre-launch.
- `is_mock = false` → real SKU. Must carry a full universe/motif/variant set.

**Blocker first:** the column does not exist in `schema.sql`, but `seed.sql` inserts
it into all 13 product rows. A fresh database built from `schema.sql` + `seed.sql`
fails at the first insert. `vibes` and `moods` are in the same position. See
`contracts/schema-drift.md`. Nothing below is enforceable until that lands.

**Open defect:** `web/src/lib/data.ts` `getProducts()` does not filter
`.eq('is_mock', true)` — it selects every row and hardcodes `isMock: false` on the
mapped result. Migrated legacy seed rows with full universe columns pass
feature-detection and leak into the storefront. Fix is a red test first
(T1.4 in `web/docs/10-testing`).

Both clients must apply the same predicate. Mobile's read path must not silently
disagree with web's.

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

**Guarantees the function provides** (clients rely on these, do not re-implement):

1. Prices are re-read server-side from `variants` — client-sent `price_cents` is advisory.
2. Stock is decremented atomically; insufficient stock aborts the whole transaction.
3. Returns the created `orders.id` plus the item ledger.
4. `SECURITY DEFINER` — anon may call it, but only it may write these tables.

**Error surface:** a `raise exception` aborts with no partial order. Clients show the
message verbatim; they must not retry a failed `place_order` blindly (stock may have moved).

---

## 7. Migrations

`backend/migrations/` is ordered. Both clients share this single chain — mobile
contributed `20260101000000`–`20260104000000`, web contributed `01_web_20261013`.

| File | Origin | Purpose |
|---|---|---|
| `01_web_20261013_taxonomy_columns.sql` | web | `intensity`, `craft_techniques`, `edits` |
| `20260101000000_place_order_fn.sql` | mobile | order placement RPC |
| `20260102000000_lock_catalogue_writes.sql` | mobile | RLS lock on catalogue writes |
| `20260103000000_lockdown_interim.sql` | mobile | interim lockdown |
| `20260104000000_lockdown_auth_admin.sql` | mobile | auth-gated admin |

**Ordering caveat:** `01_web_*` runs first lexically but was authored after the mobile
chain in real time. `schema.sql` already contains `expression_score`/`expression_slug`,
so a fresh build is consistent; a database built by replaying migrations alone must
apply `01_web_*` before the lockdown chain. Verify with `schema.sql` diff after any
migration change — schema drift between `schema.sql` and the migration chain is the
most likely source of "works on web, breaks on mobile".

---

## 8. Ground truth files

| Concern | File |
|---|---|
| Full DDL | `backend/schema.sql` |
| Dev seed | `backend/seed.sql` |
| Production baseline | `backend/production-seed.sql` |
| Migration chain | `backend/migrations/` |
| Client types | `web/src/lib/data.ts`, `mobile/.../data/SupabaseDtos.kt` |
| Known divergences | `backend/contracts/parity-gaps.md` |
