# Deploy checklist — checkout pricing (`20261101`)

**Status: DEPLOYED — verified live 2026-10-31.** This document is now a
**verification** record, not an apply runbook. Do not paste the migration again on
the hosted project; it is already applied.

Live evidence (read-only probes against `heimnfjuwmmmejqcjbbd`):

| Probe | Result |
|---|---|
| `rpc/quote_order` with a real SKU | **`99800`** for an `89900` tee + `9900` shipping; `best_coupon` + `available_offers` returned |
| `coupons` | `200`, 6 rows (`ATELIER10`, `BONKERS20`, `FREESHIP`, `GOBONKERS15`, `HUSTLE10`, `NEEDLECRAFT`) |
| `shipping_rules` | `200` — India standard, `9900` / free above `149900` / COD fee `5900` / cap `10` |
| `coupon_redemptions`, `variants.compare_at_ends_at`, `orders.cod_fee_cents` | all `200` |

It was also executed end-to-end on PostgreSQL 16.15 as part of the full chain on
2026-10-31 (see `CONTRACT.md` §7 "Ordering").

> **Original text, for the record:** "the migration is written and proven against a
> local PostgreSQL 16 replica (132 assertions passing), but it has never been
> applied to the hosted project." That was true when written on 2026-10-30.

Project: `heimnfjuwmmmejqcjbbd`
Follows the same manual pattern as `contracts/AUTH-DEPLOY-RUNBOOK.md`.

---

## Why you have to run this, not me

Deploying needs a credential this machine does not have. `web/.env` holds only
`VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` — the anon key is deliberately
*write-less* once the lockdown migrations are applied. There is no service-role
key, no direct database URL, and no `supabase` CLI installed. Every path that
works requires a secret that is yours to hand over or use.

Two ways to do it:

| | Who runs it | What you need |
|---|---|---|
| **A. SQL Editor** (recommended) | you | nothing but dashboard access |
| **B. Give me a credential** | me | DB URI *or* a Supabase access token |

---

## Option A — you paste it (5 minutes)

1. Dashboard → project `heimnfjuwmmmejqcjbbd` → **SQL Editor**.
2. Open `backend/migrations/20261101_checkout_pricing.sql` and pasted the whole
   file. Run it once.
3. **Expect:** `Success. No rows returned`.
   These NOTICEs are normal and not errors:
   - `column "compare_at_ends_at" of relation "variants" already exists, skipping`
   - `policy "..." does not exist, skipping`
   - `function public.price_cart(jsonb,text,text,text) does not exist, skipping`
4. If you see **any** `ERROR:`, stop and send me the first one. Do not re-run.

Every statement is idempotent (`if not exists`, `on conflict do nothing`,
`create or replace`), so a second run is safe.

---

## Then run these four checks

Paste into the SQL Editor. Each one should return what the comment says.

```sql
-- 1. The tables and column exist.
--    EXPECT: 4 rows (coupons, coupon_redemptions, shipping_rules, variants col)
select 'coupons' as obj, count(*) from public.coupons
union all select 'redemptions', count(*) from public.coupon_redemptions
union all select 'shipping_rules', count(*) from public.shipping_rules
union all select 'variants.compare_at_ends_at', count(*)
  from information_schema.columns
  where table_name='variants' and column_name='compare_at_ends_at';

-- 2. Your shipping numbers are live.
--    EXPECT exactly: India standard | 9900 | 149900 | 5900 | 10
select name, flat_rate_cents, free_above_cents, cod_fee_cents, cod_max_units
from public.shipping_rules where is_active;

-- 3. The six coupons exist.
--    EXPECT 6 rows: HUSTLE10, ATELIER10, GOBONKERS15, BONKERS20, NEEDLECRAFT, FREESHIP
select code, discount_type, discount_value, min_subtotal_cents, per_user_limit
from public.coupons order by code;

-- 4. The pricing engine is installed and callable.
--    EXPECT: one row, a jsonb object with subtotal_cents / total_cents.
--    EXPECT identity_checked = false (anon caller).
select public.quote_order(
  '[{"variant_sku":"REPLACE_WITH_A_REAL_SKU","quantity":1}]'::jsonb
) as quote;
```

For check 4, get a real SKU first:

```sql
select sku, price_cents from public.variants where quantity > 0 limit 3;
```

---

## Option B — give me the credential instead

If you would rather I run it and verify it myself, pick one:

- **Database URI** — Dashboard → Settings → Database → Connection string → **URI**.
  Send it and I'll run `psql "$URI" -f backend/migrations/20261101_checkout_pricing.sql`
  then the four checks above.
- **Access token** — Dashboard → Account → Access Tokens. New token, send it, and
  I'll apply the migration through the Management API.

Either way: **the anon key is not enough**, and I will not ask you to paste a
secret into chat that I could otherwise avoid needing. Option A needs no secret
shared at all.

---

## What is *not* in this migration

It does not touch `orders`/`order_items` RLS, the admin gate, or auth — those are
`20261025`/`20261031` and already deployed. It does not *author* MRPs: the
pipeline emits `compare_at_price_cents` only when a `product.yaml` declares one,
and no product currently does, so the bag shows no strike-through until there is
a genuine markdown to show.

### Pre-flight: four hosted rows will be quarantined

`compare_at_price_cents` is **not** null everywhere on hosted. Four variants of
`anime-eye-sweatshirt` carry a reference price *below* their selling price:

| sku | price | compare_at |
|---|---|---|
| `UL-S68C-CREAM-S` | ₹1,499 | ₹1,399 |
| `UL-S68C-CREAM-M` | ₹1,499 | ₹1,299 |
| `UL-S68C-CREAM-L` | ₹1,499 | ₹1,399 |
| `UL-S68C-CREAM-XL` | ₹1,499 | ₹1,459 |

A reference price under the selling price is not a discount, and the
`variants_mrp_exceeds_price` CHECK constraint correctly refuses it. A plain
`ADD CONSTRAINT` therefore aborts the whole migration on real data (this is the
`23514` you will see). The migration instead **nulls those four values before
adding the constraint** and raises a `WARNING` naming every affected SKU. The
sourcing `product.yaml` declares no MRP for this product, so NULL restores
agreement with the pipeline — nothing real is being discarded.

Nothing is invented in its place. If a genuine markdown is wanted for that
sweatshirt, author it in `product.yaml` and re-publish.

## Rollback

Additive and idempotent. To undo:

```sql
drop function if exists public.set_variant_mrp(text, integer, timestamptz);
drop function if exists public.quote_order(jsonb, text, text, text);
drop function if exists public.price_cart(jsonb, text, text, text, boolean);
drop table if exists public.coupon_redemptions;
drop table if exists public.coupons;
drop table if exists public.shipping_rules;
alter table public.orders drop column if exists cod_fee_cents;
alter table public.variants drop column if exists compare_at_ends_at;
-- then restore place_order from 20261030_harden_place_order.sql
```

`place_order` is overwritten by this migration. Rolling back requires
re-pasting `20261030_harden_place_order.sql`, exactly as the auth runbook says
for its own `place_order` rewrite.

---

## Order of operations for launch

1. **You:** apply the migration (above).
2. **Me:** `/checkout` is already built and committed (Phase 3). It reads
   `quote_order`; until the migration lands it shows "Server pricing is not
   deployed yet" instead of a made-up number.
3. **Together:** place one real ₹899 test order, verify the confirmation page
   shows ₹99 shipping (not ₹1,999), then refund it.

---

## What was proven locally (PG16 replica, not hosted)

These were run against the real functions, not mocks:

```
1x hoodie, prepaid   subtotal 149900  shipping 0  total 149900
1x hoodie, COD       subtotal 149900  cod_fee 5900  total 155800
2x hoodie            subtotal 299800  shipping 0  total 299800   (free)
11 units + COD       RAISES: "COD is limited to 10 units per order"
place_order w/ ATELIER10  recorded 149900 / 14990 / 0 / 0 / 134910
                          redemption ledgered 14990, stock 10 -> 9
```

The COD-cap raise is worth knowing before you test on hosted: the client now
falls back to prepaid rather than showing an error, but the RPC refusing a quote
outright is the server's actual behaviour.

Free delivery triggered at ₹1,499 on a single ₹1,499 hoodie — inclusive, which
is what "free above ₹1,499" reads as. Say now if you meant strictly above.
