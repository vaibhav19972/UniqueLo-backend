-- ============================================================================
-- 20261102_order_lifecycle.sql
--
-- Phase B, first slice: give an order a lifecycle it can be trusted on.
--
--   1. orders.status gains the CHECK constraint CONTRACT.md §6 has always
--      documented but never enforced. It was free `text`.
--   2. orders.tracking_number + orders.carrier, so fulfilment has somewhere to
--      record what shipped. `GET /orders?select=tracking_number` returned 400
--      before this.
--   3. A partial index for the admin queue (open orders, newest first).
--
-- Deliberately NOT here: payment_status. That depends on which gateway lands
-- (Razorpay vs other) and inventing the column now would fix a shape before the
-- decision. Same reason there is no invoice table yet.
--
-- SAFETY: existing rows are not assumed clean. The constraint is added NOT VALID
-- (no table scan, no long lock), then validated in a second statement so a bad
-- row names itself instead of aborting the whole migration opaquely.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. orders.status — the vocabulary CONTRACT.md §6 documents
-- ---------------------------------------------------------------------------
-- Written today by:
--   place_order       -> 'confirmed' | 'confirmed-cod'   (20261101 lines 819/895)
--   legacy mobile RPC -> 'reserved'
-- Set later by admin fulfilment:
--   'processing' | 'shipped' | 'delivered' | 'cancelled'
--
-- 'pending' is included because a reservation that has not been paid yet is a
-- real state for prepaid, and refusing it later would mean a second migration.

update public.orders
   set status = 'confirmed'
 where status is null or trim(status) = '';

update public.orders
   set status = lower(trim(status))
 where status <> lower(trim(status));

do $$
begin
  if exists (
    select 1 from pg_constraint where conname = 'orders_status_valid'
  ) then
    raise notice 'orders_status_valid already present, skipping';
    return;
  end if;

  alter table public.orders
    add constraint orders_status_valid
    check (status in ('pending', 'reserved', 'confirmed', 'confirmed-cod',
                      'processing', 'shipped', 'delivered', 'cancelled'))
    not valid;
end $$;

-- Nullable status would let the CHECK pass on NULL even though the vocabulary
-- is now enforced for real values. The backfill above ran in this same
-- transaction, so this is safe. Recorded here rather than left implicit —
-- leaving it unstated is how the seven missing tables happened.
alter table public.orders alter column status set not null;

comment on constraint orders_status_valid on public.orders is
  'CONTRACT.md §6 order vocabulary. Added NOT VALID then validated separately so '
  'a pre-existing row names itself rather than aborting the migration opaquely.';

-- Separate statement: on real data this is where a bad row surfaces, by name.
do $$
declare
  v_bad text;
begin
  select string_agg(distinct status, ', ' order by status) into v_bad
    from public.orders
   where status not in ('pending', 'reserved', 'confirmed', 'confirmed-cod',
                        'processing', 'shipped', 'delivered', 'cancelled');

  if v_bad is not null then
    raise exception
      'orders.status holds values outside the CONTRACT §6 vocabulary: %. '
      'Map them before validating the constraint.', v_bad
      using errcode = '23514';
  end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'orders_status_valid' and convalidated
  ) then
    alter table public.orders validate constraint orders_status_valid;
    raise notice 'orders_status_valid validated';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2. Fulfilment: tracking number + carrier
-- ---------------------------------------------------------------------------
alter table public.orders
  add column if not exists tracking_number text,
  add column if not exists carrier         text;

comment on column public.orders.tracking_number is
  'Courier AWB / tracking id. NULL until the order ships. Set by admin fulfilment, never by a client.';
comment on column public.orders.carrier is
  'Courier name (Delhivery, Blue Dart, India Post, ...). Free text deliberately — the set changes.';

-- A tracking number with no carrier is unusable to a customer, and vice versa.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'orders_tracking_pairs_with_carrier'
  ) then
    alter table public.orders
      add constraint orders_tracking_pairs_with_carrier
      check (
        (tracking_number is null and carrier is null)
        or (tracking_number is not null and carrier is not null)
      );
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Admin queue index
-- ---------------------------------------------------------------------------
-- Open orders, newest first. Partial so it stays small once history grows:
-- terminal states are never in the working set.
create index if not exists idx_orders_open_queue
  on public.orders (created_at desc)
  where status in ('pending', 'reserved', 'confirmed', 'confirmed-cod', 'processing');

-- Lookup by tracking number (customer support answers "where is AWB x").
create index if not exists idx_orders_tracking
  on public.orders (tracking_number)
  where tracking_number is not null;

commit;
