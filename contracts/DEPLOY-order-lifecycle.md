# DEPLOY — order lifecycle (`20261102_order_lifecycle.sql`)

**Status: NOT DEPLOYED.** Written and PROVEN LOCALLY only. The hosted project
(`heimnfjuwmmmejqcjbbd`) still has free-text `orders.status` and **no**
`tracking_number` / `carrier` columns.

Read this before writing any admin order-management code: `GET
/rest/v1/orders?select=tracking_number` returns **`400`** against hosted today.
An admin UI built against the local schema will fail in production until this is
applied.

> This note exists *before* deploy on purpose. `DEPLOY-checkout-pricing.md` was
> written after the fact and said "NOT DEPLOYED" for a whole day after the thing
> had gone live — that is the exact failure this file is shaped to avoid. Update
> the status line the moment it changes, in the same commit as the evidence.

---

## What it does

| Change | Detail |
|---|---|
| `orders_status_valid` | CHECK limiting `status` to the CONTRACT §6 vocabulary (8 values, incl. `pending`) |
| `orders.status NOT NULL` | backfilled first, then constrained |
| `orders.tracking_number`, `orders.carrier` | new columns; NULL until shipped |
| `orders_tracking_pairs_with_carrier` | CHECK: the two are set together or not at all |
| `idx_orders_open_queue` | partial index on open orders, newest first |
| `idx_orders_tracking` | partial index for support lookups by AWB |

Atomic: one `begin; … commit;`. A failure rolls back **everything**, so a bad row
looks like "nothing happened" and the error message is the only signal.

---

## BEFORE you apply it — the probe that must run first

The migration normalises existing statuses and then validates a CHECK against
them. **Local proof does not cover this**, because a fresh build has an empty
`orders` table and the validation passes trivially.

**Anon RLS cannot see orders.** Verified this session: an anon
`GET /rest/v1/orders?select=status` returns `[]` with `content-range: */0`. A
probe using the publishable key will look clean no matter what is in the table.
**Use the SQL editor or a service-role key.**

```sql
-- run in the Supabase SQL editor
select status, count(*)
  from public.orders
 group by status
 order by 2 desc;

select distinct status
  from public.orders
 where status is null
    or status not in ('pending','reserved','confirmed','confirmed-cod',
                      'processing','shipped','delivered','cancelled');
```

```sql
-- Rows the migration will SILENTLY REWRITE. Not just a typo check: the backfill
-- turns NULL/empty into 'confirmed' and lowercases+trims everything else.
select
  count(*) filter (where status is null or trim(status) = '')          as will_become_confirmed,
  count(*) filter (where status is not null and status <> lower(trim(status))) as will_be_lowercased,
  count(*)                                                             as total_orders
  from public.orders;
```

- Third query is the one that matters numerically. **`will_become_confirmed`
  above zero means the migration is asserting that unpaid orders are confirmed.**
  `place_order` always sets a status so it should be 0 — but "should be" is what
  the seven missing tables were built on. If it is not 0, decide per row before
  applying; do not let a schema migration make a commercial claim on your behalf.
- First query: eyeball it for typos (`Confirmed`, `CONF-COD`, `shiped`).
- Second query: **any row returned means the migration will abort** with
  `23514` naming those values. Map them first with a targeted `update`; do not
  widen the vocabulary to accommodate a typo.

The migration already lowercases and trims, so `CONFIRMED` and ` confirmed ` are
handled. Only genuine non-vocabulary words will fail.

**Client status supply — checked 2026-10-31, all three paths are inside the
vocabulary:**

| Caller | Sends | Resolves to |
|---|---|---|
| web | **no `status` field at all** (`grep` for status in `Checkout.tsx` / `pricing.ts` → none) | `place_order` derives `confirmed` / `confirmed-cod` from payment method |
| mobile (`place_order`) | `confirmed-cod` when `cod`, else `confirmed` | verbatim, both legal |
| mobile (legacy two-call fallback) | same pair | verbatim, both legal |

`place_order` reads `p_order->>'status'` with a `coalesce` fallback, so an
absent field is safe. **A future client that starts sending an arbitrary status
string would now abort checkout with `23514` instead of silently writing a bad
row.** That is the intended trade, but it is a sharp edge: status is
server-owned state and no client should be supplying it at all. Removing that
input from `place_order` is the correct long-term fix and is tracked as KD-6.

---

## Apply

Paste the whole file into the SQL editor. It is idempotent: the constraint block
checks `pg_constraint` by name, and the column adds use `if not exists`.

**Verify after:**

```sql
select conname, convalidated from pg_constraint
 where conname in ('orders_status_valid','orders_tracking_pairs_with_carrier');
-- both rows must show convalidated = true

select column_name, is_nullable from information_schema.columns
 where table_name='orders' and column_name in ('tracking_number','carrier','status');
-- tracking_number/carrier: is_nullable = YES ; status: NO
```

Then from a client, `GET /rest/v1/orders?select=tracking_number` must return
`200` (with `[]` under anon RLS) instead of `400`.

---

## Local proof (what is and is not established)

`bash scripts/verify-chain.sh` applies `local-bootstrap → schema.sql → migrations
sorted → production-seed` to a throwaway PostgreSQL 16.15 cluster.

- **Established:** the DDL parses and applies in chain order; the partial-index
  predicates are accepted; `schema.sql` and the migration agree on columns.
- **NOT established:** that the `not valid` → `validate` path survives real
  hosted data. The local `orders` table is empty, so validation is a no-op.
  This is the whole reason for the probe above.
