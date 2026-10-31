# DEPLOY — order payment identity (`20261105_order_payment_identity.sql`)

**Status: WRITTEN and PROVEN LOCALLY. NOT APPLIED to hosted.** The chain builds
and the behaviour is proven on a throwaway cluster (`scripts/verify-order-payment.sh`,
all proofs passing). Hosted (`heimnfjuwmmmejqcjbbd`) does **not** yet have
`orders.payment_method` or `orders.payment_ref`.

Apply this **before** redeploying `razorpay-verify`. The new function stamps
`orders.payment_ref`; against a database without that column the stamp fails
`42703` and every verified payment leaves a NULL reference. The order is still
placed, so the failure is quiet rather than a lost sale — which is exactly why
the ordering is written down here.

---

## What it does

| Change | Detail |
|---|---|
| `orders.payment_method` | `text not null`, `CHECK (payment_method in ('cod','prepaid'))` |
| `orders.payment_ref` | `text`, nullable; gateway payment id |
| `idx_orders_payment_ref` | UNIQUE partial index, `where payment_ref is not null` |
| `place_order` | rewritten **from `20261101`'s body verbatim**, three edits only |

The three `place_order` edits, and nothing else:

1. `v_payment` normalised to exactly `cod` \| `prepaid` (was the raw lowercased
   client string, stored nowhere and therefore never validated).
2. `payment_method` added to the `orders` insert.
3. `payment_method` echoed in the return payload.

Signature unchanged — **neither web nor mobile needs an edit or a redeploy.**

---

## Why `payment_ref` is not written by `place_order`

`place_order` runs with the caller's JWT, so its payload is a client assertion.
Accepting `payment_ref` there would let any caller stamp an arbitrary string, or
someone else's `pay_...` id, onto their own order — corrupting the audit trail
the column exists to provide. `razorpay-verify` stamps it under the service role,
after the HMAC signature and the captured status are proven.

The cost, stated rather than hidden: a verify that places the order but fails to
stamp leaves `payment_ref` NULL. `payment_intents.provider_payment_id` still
holds the id, `placed_order_id` finds the row, and `failure_reason` is set to
`order <id> placed but payment_ref not stamped: <error>`. Recoverable, not silent.

---

## Backfill is an INFERENCE for historical rows

Two signals, in order of confidence:

| Signal | Meaning |
|---|---|
| `status = 'confirmed-cod'` | `place_order`'s own COD default — decisive |
| `cod_fee_cents > 0` | a COD surcharge was actually charged — decisive |

Anything matching neither becomes `'prepaid'`. **For a COD order placed below the
free-shipping threshold that is a guess:** no fee was charged, so nothing in the
row distinguishes it from a prepaid order.

As of this writing `orders` on hosted is **empty**, so the backfill has nothing to
mislabel. The column is authoritative from this migration forward only; treat any
pre-`20261105` row as inferred. If the table is ever populated before this is
applied, re-check that assumption first — it will not hold.

---

## Order of operations

```bash
# 1. Apply (paste the file in the SQL Editor, or:)
psql "$DATABASE_URL" -f migrations/20261105_order_payment_identity.sql
#    EXPECT: success, plus NOTICE orders_payment_method_valid validated

# 2. Redeploy only verify — create-order is unchanged.
cd backend
supabase functions deploy razorpay-verify
```

Then confirm:

```sql
-- EXPECT: 2 rows, payment_method text / payment_ref text
select column_name, data_type, is_nullable
  from information_schema.columns
 where table_name = 'orders'
   and column_name in ('payment_method','payment_ref');

-- EXPECT: one row, 'orders_payment_method_valid', convalidated = true
select conname, convalidated from pg_constraint
 where conname = 'orders_payment_method_valid';

-- EXPECT: one row, the partial unique index
select indexname from pg_indexes where indexname = 'idx_orders_payment_ref';
```

---

## Rollback

```sql
drop index if exists public.idx_orders_payment_ref;
alter table public.orders drop constraint if exists orders_payment_method_valid;
alter table public.orders drop column if exists payment_ref;
alter table public.orders drop column if exists payment_method;
```

Then re-paste `20261101_checkout_pricing.sql` to restore the previous
`place_order` body, and redeploy the previous `razorpay-verify` — otherwise it
keeps trying to stamp a column that no longer exists (harmless: the stamp is
logged, not fatal, precisely so a redeploy ordering mistake cannot strand a
paid customer).

---

## What was proven locally

`scripts/verify-order-payment.sh` (throwaway cluster, real `place_order` calls):

```
PASS  prepaid order stores payment_method      prepaid
PASS  prepaid order has NULL payment_ref       NULL
PASS  COD order stores payment_method          cod
PASS  COD order status                         confirmed-cod
PASS  distinct payment_method values           2
PASS  junk method normalised to prepaid        prepaid   (does NOT abort the sale)
PASS  constraint rejected 'bitcoin'            (positive control)
PASS  duplicate payment_ref rejected           (idx_orders_payment_ref)
PASS  multiple NULL payment_ref rows coexist   2
```

The junk-method case is the one worth knowing: because `payment_method` is now
`CHECK`-constrained, a client sending `payment_method: "UPI"` would abort a valid
sale with `23514` if the value were stored raw. It is normalised instead.
