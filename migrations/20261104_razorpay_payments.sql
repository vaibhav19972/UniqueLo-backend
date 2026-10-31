-- ============================================================================
-- 20261104_razorpay_payments.sql
--
-- The payment gateway lands. 20261102 deferred `payment_status` and any invoice
-- table "until the gateway lands" — this is that file, and it is deliberately
-- NARROWER than that deferral implied: no invoice table, and `orders` is not
-- touched at all.
--
-- WHY PAYMENT STATE IS NOT ON `orders`
-- ------------------------------------
-- `20261103` revoked INSERT/UPDATE/DELETE on `orders` from anon/authenticated and
-- granted back only a three-column admin UPDATE. Putting `payment_status` on
-- `orders` would therefore create a column that NOTHING can legitimately write
-- except a SECURITY DEFINER function — and it would mean a payment outlives or
-- dies with the order row, which is the wrong lifetime. A captured payment whose
-- order failed to place (stock moved between charge and write) MUST remain
-- visible; on `orders` it would have nowhere to live.
--
-- So money lives in its own ledger, keyed by the client's own order id:
--
--     payment_intents.client_order_id  ==  orders.id
--
-- The client already generates that UUID (`data.ts` `createOrder`) for
-- place_order idempotency. This migration reuses it as the join key rather than
-- inventing a second one, so reconciliation is a plain equality, not a lookup
-- table.
--
-- PROVIDER-NEUTRAL BY CONSTRUCTION
-- --------------------------------
-- `provider` carries no restrictive CHECK and the provider-specific ids are
-- nullable. Razorpay fills them today; the next gateway adds a row with a
-- different `provider` value and needs no migration. That is the seam the brief
-- asked for when it said "then we will be integrating more payment methods."
--
-- ACCESS: RLS on, ZERO policies — service role only. Same posture as
-- `coupon_redemptions` (20261101), for the same reason: writes go through a
-- SECURITY DEFINER path, and no browser may ever read or mark a payment.
-- ============================================================================

begin;

create table if not exists public.payment_intents (
  id uuid primary key default gen_random_uuid(),
  -- 'razorpay' today; free text so the next gateway is a row, not a migration.
  provider text not null default 'razorpay',
  -- The client-generated order id. NOT a FK: the intent is created (and can be
  -- charged) BEFORE the order row exists, and a captured payment with no order
  -- is a real state this ledger must be able to represent — see KD-8.
  client_order_id uuid not null,
  -- The id place_order actually returned, once it succeeded. NULL = money taken
  -- with no order: the refund queue.
  placed_order_id uuid,
  provider_order_id text unique,
  provider_payment_id text unique,
  -- Paise. Razorpay's own unit, and identical to the repo's `*_cents`
  -- convention (formatPrice divides by 100), so there is NO conversion anywhere.
  amount_cents integer not null check (amount_cents >= 100),
  currency text not null default 'INR',
  status text not null default 'created',
  customer_email text not null,
  customer_name text,
  customer_phone text,
  shipping_address jsonb,
  coupon_code text,
  -- The priced cart as it stood when the charge was created. place_order is
  -- called with THIS, never with a cart the browser re-submits.
  items jsonb not null,
  failure_reason text,
  created_at timestamptz not null default now(),
  captured_at timestamptz,
  -- Named, mirroring orders_status_valid (20261102). Keeping it off the status
  -- column line matters: check-schema-completeness.mjs parses columns with
  -- /^\s{2}([a-z_]+)\s+[a-z(\[]/ and only skips lines starting with `constraint`.
  constraint payment_intents_status_valid
    check (status in ('created', 'authorized', 'captured', 'failed', 'expired'))
);

comment on table public.payment_intents is
  'Provider-neutral payment ledger. RLS on, no policies: service role only. '
  'Joins to public.orders on client_order_id = orders.id.';

comment on column public.payment_intents.client_order_id is
  'Client-generated order UUID, written to orders.id by place_order.';

comment on column public.payment_intents.placed_order_id is
  'Set only after place_order succeeds AND its total matches the amount paid. '
  'NULL on a captured row means money was taken with no order (KD-8) — an ops '
  'row to refund, not a row to hide.';

comment on column public.payment_intents.amount_cents is
  'Paise. Equal to quote_order().total_cents with no scaling.';

-- Retries reuse the row rather than minting a second Razorpay order for the
-- same basket; this is the lookup that makes that possible.
create index if not exists idx_payment_intents_client_order
  on public.payment_intents (client_order_id);

-- The refund/ops queue.
--
-- NOT predicated on status = 'captured'. The realistic orphan is a customer who
-- pays and then closes the tab, or whose browser dies, BEFORE `verify` runs: the
-- intent is still `status = 'created'` while Razorpay holds a captured payment.
-- A `status = 'captured'` predicate would make exactly that row invisible — the
-- one case where money exists and nothing in this database knows it. So the
-- predicate is "no order", which covers created-and-paid, captured-and-unplaced,
-- and amount-mismatch rows alike.
create index if not exists idx_payment_intents_orphans
  on public.payment_intents (created_at desc)
  where placed_order_id is null;

alter table public.payment_intents enable row level security;

-- No policies on purpose (see header). Stated explicitly so a future reader does
-- not "fix" the absence by adding an anon SELECT.

-- ---------------------------------------------------------------------------
-- Privileges: REVOKE FIRST, then assert.
--
-- Supabase ships `alter default privileges in schema public grant all on tables
-- to anon, authenticated, service_role`. So on the hosted project this table is
-- born readable by a publishable key, and an assertion alone would raise and roll
-- the whole migration back — while passing locally if the throwaway cluster has
-- no such default. Revoking first makes the posture true on both, and the guard
-- below then proves it rather than assuming it.
--
-- Role existence is checked because the local test cluster may not define
-- `anon`/`authenticated` at all; a bare REVOKE would error there.
-- ---------------------------------------------------------------------------
do $$
declare
  r text;
begin
  foreach r in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('revoke all on public.payment_intents from %I', r);
    end if;
  end loop;

  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant all on public.payment_intents to service_role';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Guard: prove the table is unreachable from a publishable key.
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from information_schema.table_privileges
     where table_schema = 'public'
       and table_name = 'payment_intents'
       and grantee in ('anon', 'authenticated')
  ) then
    raise exception 'payment_intents must not be granted to anon/authenticated';
  end if;
end $$;

commit;
