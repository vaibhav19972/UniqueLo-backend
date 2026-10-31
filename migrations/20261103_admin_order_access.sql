-- ============================================================================
-- 20261103_admin_order_access.sql
--
-- Phase B, slice 2. Slice 1 (20261102) added indexes FOR an admin queue and
-- columns FOR fulfilment — but no policy lets an admin reach either.
--
-- Measured across migrations/*.sql before writing this:
--   20261031  "Users view own orders"      for select to authenticated
--             using (user_id = auth.uid())
--   20261032  "Users view own order items" the same, via an orders subquery
--   20261031 §5c  deliberately leaves order writes RPC-only (no INSERT/UPDATE)
--
-- Those are the ONLY policies on either table. So today a signed-in admin sees
-- their own orders and nothing else, cannot read any customer's line items, and
-- cannot UPDATE status or tracking at all. The admin order-management UI cannot
-- be built against this — every list returns one row, every save is refused.
--
-- `public.is_admin()` already exists (20261025): true for a row in
-- public.admins, or a server-set app_metadata.role of admin/service_role.
-- It gates catalogue and storage writes. It gates nothing transactional. This
-- file closes that.
--
-- SCOPE: admin READ and UPDATE only.
--   * No INSERT — orders are created by place_order, never by an admin.
--   * No DELETE — financial records are not deletable by a UI.
--   * Customer policies are untouched; this only ADDS.
--
-- The customer's own path is unchanged: place_order (SECURITY DEFINER) still
-- writes both tables, and "users view own" still reads them.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 0. Precondition: is_admin() must exist, or every policy below is invalid
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regprocedure('public.is_admin()') is null then
    raise exception
      'public.is_admin() is missing. Apply 20261025_admin_write_policies.sql first.'
      using errcode = '42883';
  end if;

  if to_regclass('public.orders') is null
     or to_regclass('public.order_items') is null then
    raise exception 'orders/order_items missing; nothing to gate.'
      using errcode = '42P01';
  end if;

  -- 20261103 adds a constraint referencing tracking_number/carrier, which
  -- 20261102 creates. Applied on its own it would fail with a bare
  -- "column does not exist" instead of naming the ordering problem — the same
  -- class of defect as the 20261026 FK abort caught by execution on 2026-10-31.
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'orders'
       and column_name = 'tracking_number'
  ) then
    raise exception
      'orders.tracking_number is missing. Apply 20261102_order_lifecycle.sql first.'
      using errcode = '42703';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1. Admin can read every order
-- ---------------------------------------------------------------------------
-- Policies are permissive and OR together, so this ADDS to "Users view own
-- orders" rather than replacing it. A customer still sees only their own; an
-- admin sees all. `for select to authenticated` — anonymous callers get nothing,
-- which is correct: order data is never public.
drop policy if exists "Admins view all orders" on public.orders;
-- `(select public.is_admin())` forces an InitPlan evaluated ONCE per statement
-- rather than a subquery per row. Without the wrapper an admin list of N orders
-- runs N lookups against public.admins. Cheap to write now, painful to retrofit.
create policy "Admins view all orders" on public.orders
  for select to authenticated
  using ((select public.is_admin()));

-- ---------------------------------------------------------------------------
-- 2. Admin can read every line item
-- ---------------------------------------------------------------------------
-- Same predicate, no denormalised user_id on order_items — ownership lives in
-- exactly one place, matching the reasoning in 20261032.
drop policy if exists "Admins view all order items" on public.order_items;
create policy "Admins view all order items" on public.order_items
  for select to authenticated
  using ((select public.is_admin()));

-- ---------------------------------------------------------------------------
-- 3. Admin can update fulfilment state
-- ---------------------------------------------------------------------------
-- UPDATE only. Fulfilment is exactly: set status, set tracking_number+carrier.
-- USING gates which rows may be targeted; WITH CHECK gates the result, so an
-- admin cannot UPDATE a row into a state that would be invisible to them, and
-- cannot rewrite the money columns into an inconsistent order.
--
-- Money and identity are frozen. A status change must not be a quiet way to
-- edit what the customer was charged.
drop policy if exists "Admins update order fulfilment" on public.orders;
create policy "Admins update order fulfilment" on public.orders
  for update to authenticated
  using ((select public.is_admin()))
  with check (
    (select public.is_admin())
    -- An order cannot lose its identity. Deliberately NOT an arithmetic
    -- invariant: `total_cents = subtotal - discount + shipping + cod` holds for
    -- everything 20261101's place_order writes, but NOT provably for orders from
    -- the older legacy two-call path — and WITH CHECK on UPDATE is evaluated on
    -- the new row, so one unreconciled legacy row makes that order permanently
    -- unfulfillable. The failure surfaces as a generic RLS denial with no hint
    -- which row is wrong, and the admin cannot repair it either (the corrected
    -- row is rejected by the same check).
    --
    -- Money is frozen by the COLUMN GRANT below, which is the real mechanism.
    -- This policy proves intent; it must not encode a data-validity assertion
    -- that pre-dates the constraint.
    and customer_email is not null
    and subtotal_cents >= 0
  );

-- Column-level guard: even with an UPDATE policy, RLS does not stop an admin
-- from changing `total_cents`. Restrict the grant to the columns fulfilment
-- actually needs. This is the mechanism, not the policy above — the policy
-- proves intent, the grant enforces it.
-- Named for BOTH roles: verify-customer-accounts.sql grants update on every
-- table to `anon, authenticated`, so a revoke naming only `authenticated` leaves
-- anon holding table-wide UPDATE. RLS blocks it today (no anon policy on
-- orders), but defence in depth is cheap and the grant is the mechanism.
revoke update, insert, delete on public.orders from anon;
revoke update on public.orders from authenticated;
grant update (status, tracking_number, carrier) on public.orders to authenticated;

-- order_items: read-only for admins. Nothing about a line item is editable
-- after the fact — price and quantity are the audit trail.
revoke update, insert, delete on public.order_items from authenticated;
grant select on public.order_items to authenticated;

-- ---------------------------------------------------------------------------
-- 4. 'shipped' now REQUIRES a tracking number (closes a doc-vs-enforcement gap)
-- ---------------------------------------------------------------------------
-- CONTRACT §6 states shipped means "with courier; tracking_number + carrier
-- required". Until now the constraint only enforced PAIRING, so an order could
-- sit in `shipped` with both NULL — the documentation claimed an invariant the
-- database did not hold. That is the same defect class this whole phase exists
-- to remove, and it was introduced by 20261102 hours ago.
--
-- Scoped to `shipped` only, not `delivered`: a hand-delivered or locally
-- collected order can legitimately reach `delivered` without a courier. `shipped`
-- specifically means "with courier", so it is the one that must carry an AWB.
do $$
begin
  if exists (
    select 1 from pg_constraint where conname = 'orders_shipped_needs_tracking'
  ) then
    raise notice 'orders_shipped_needs_tracking already present, skipping';
    return;
  end if;

  alter table public.orders
    add constraint orders_shipped_needs_tracking
    check (status <> 'shipped' or (tracking_number is not null and carrier is not null))
    not valid;
end $$;

do $$
declare
  v_bad integer;
begin
  select count(*) into v_bad
    from public.orders
   where status = 'shipped'
     and (tracking_number is null or carrier is null);

  if v_bad > 0 then
    raise exception
      '% order(s) are already status=shipped with no tracking_number/carrier. '
      'Set them before validating this constraint.', v_bad
      using errcode = '23514';
  end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'orders_shipped_needs_tracking' and convalidated
  ) then
    alter table public.orders validate constraint orders_shipped_needs_tracking;
    raise notice 'orders_shipped_needs_tracking validated';
  end if;
end $$;

commit;

-- ============================================================================
-- NOT INCLUDED, on purpose
-- ----------------------------------------------------------------------------
-- A status-TRANSITION guard (rejecting delivered -> pending) is not here.
--
-- It is a real hole: the CHECK constrains the vocabulary, not the order of
-- states, so nothing stops a backwards jump. But enforcing it needs a trigger on
-- the path that fulfilment uses, and a trigger with a wrong transition map is
-- worse than no guard — it blocks legitimate corrections during a live launch,
-- which is the least convenient possible failure.
--
-- It belongs with the admin UI that will drive it, where the transitions the
-- screen actually offers can be the source of truth. Recorded as KD-7.
--
-- Also still open: coupon_redemptions has zero policies (KD-3), so the
-- redemption ledger is unreadable even by an admin. It should get the same
-- is_admin() treatment, but it is not on the fulfilment path.
-- ============================================================================
