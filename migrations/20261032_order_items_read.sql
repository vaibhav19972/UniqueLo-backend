-- ============================================================================
-- 20261032_order_items_read.sql
-- ============================================================================
-- Completes 20261031 §1. That migration let a customer SELECT their own
-- `orders` rows but added no matching policy on `order_items`, so an order
-- history screen could list orders and then fail to show a single line item.
--
-- The predicate is deliberately expressed against `orders` (a subquery) rather
-- than a denormalised user_id on order_items: ownership lives in exactly one
-- place, so it cannot drift.
--
-- Depends on: 20261031 (orders.user_id + "Users view own orders").
-- Idempotent.
-- ============================================================================

begin;

do $$
begin
  if to_regclass('public.order_items') is null then
    raise notice 'order_items missing; nothing to do';
    return;
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='orders' and column_name='user_id'
  ) then
    raise exception
      'orders.user_id is missing. Apply 20261031_customer_accounts.sql first.';
  end if;
end $$;

alter table public.order_items enable row level security;

drop policy if exists "Users view own order items" on public.order_items;
create policy "Users view own order items" on public.order_items
  for select to authenticated
  using (
    exists (
      select 1
      from public.orders o
      where o.id = order_items.order_id
        and o.user_id is not null
        and o.user_id = auth.uid()
    )
  );

-- No INSERT/UPDATE/DELETE policy: order_items stays RPC-only (20261031 §5c).

commit;
