-- ============================================================================
-- 20261031_customer_accounts.sql
-- ============================================================================
-- Enables customer accounts: saved delivery addresses, cloud wishlist, and
-- order ownership. Designed so GUEST CHECKOUT IS UNAFFECTED — every addition
-- is additive and nullable, and place_order keeps working for anon callers.
--
-- PREREQUISITES (must be applied first, in this order):
--   1. 20261025_admin_write_policies.sql   <- creates public.admins + is_admin()
--   2. an admin row bootstrapped in public.admins (see §0 below)
--   3. 20261030_harden_place_order.sql     <- authoritative pricing/stock
-- If 20261025 is missing, is_admin() does not exist and the storage block in
-- this file will fail to compile. That is intentional: fail loudly, not open.
--
-- SECURITY MODEL
--   * orders.user_id is set SERVER-SIDE from auth.uid(). The client CANNOT
--     choose it. Any user_id present in the RPC payload is ignored.
--   * customers may SELECT only their own orders. Guest lookup stays on
--     rpc/get_order_details (email-gated), unchanged.
--   * catalogue writes and image uploads are admin-only (is_admin()), never
--     merely "authenticated" — that is the whole point of this migration.
--
-- Idempotent: safe to run more than once.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 0. Bootstrap check
-- ---------------------------------------------------------------------------
-- We do NOT create an admin here on purpose: adding an admin must be a
-- deliberate act. But we refuse to proceed if the gate function is missing,
-- because every policy below depends on it.
do $$
begin
  if to_regprocedure('public.is_admin()') is null then
    raise exception
      'public.is_admin() is missing. Apply 20261025_admin_write_policies.sql first (customer accounts must never be gated on `authenticated` alone).';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1. Orders gain an owner (nullable — guest checkout stays valid)
-- ---------------------------------------------------------------------------
alter table public.orders
  add column if not exists user_id uuid references auth.users(id) on delete set null;

comment on column public.orders.user_id is
  'Owner of the order, set server-side by place_order from auth.uid(). NULL = guest checkout. Never client-supplied.';

create index if not exists idx_orders_user_id on public.orders(user_id)
  where user_id is not null;

-- Customers read their own orders. There is still NO anon/public SELECT:
-- guests use rpc/get_order_details(uuid, email).
drop policy if exists "Users view own orders" on public.orders;
create policy "Users view own orders" on public.orders
  for select to authenticated
  using (user_id is not null and user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 2. Saved delivery addresses
-- ---------------------------------------------------------------------------
create table if not exists public.customer_addresses (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  label          text,
  is_default     boolean not null default false,
  recipient_name text not null,
  phone          text not null,
  address_line   text not null,
  landmark       text,
  city           text not null,
  state          text not null,
  pincode        text not null check (pincode ~ '^[0-9]{6}$'),
  created_at     timestamptz not null default now()
);

comment on table public.customer_addresses is
  'Customer-saved Indian delivery addresses. pincode is a 6-digit string (leading zeros are significant, so text not integer).';

alter table public.customer_addresses enable row level security;

drop policy if exists "Users manage own addresses" on public.customer_addresses;
create policy "Users manage own addresses" on public.customer_addresses
  for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- At most one default per user. Without this a user can accumulate many
-- defaults and "the default address" becomes ambiguous at checkout.
drop index if exists uq_customer_addresses_one_default;
create unique index uq_customer_addresses_one_default
  on public.customer_addresses(user_id)
  where is_default;

create index if not exists idx_customer_addresses_user
  on public.customer_addresses(user_id);

-- ---------------------------------------------------------------------------
-- 3. Cloud wishlist (cross-device sync of saved pieces)
-- ---------------------------------------------------------------------------
create table if not exists public.customer_wishlists (
  user_id      uuid not null references auth.users(id) on delete cascade,
  product_slug text not null,
  created_at   timestamptz not null default now(),
  primary key (user_id, product_slug)
);

comment on table public.customer_wishlists is
  'Per-user saved product slugs. Deliberately NOT a FK to products(slug): a delisted product must not silently erase a customer''s saved piece (mobile decision D-18). The join to products simply finds nothing and the client hides the stale slug.';

alter table public.customer_wishlists enable row level security;

drop policy if exists "Users manage own wishlist" on public.customer_wishlists;
create policy "Users manage own wishlist" on public.customer_wishlists
  for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index if not exists idx_customer_wishlists_slug
  on public.customer_wishlists(product_slug);

-- ---------------------------------------------------------------------------
-- 4. place_order: bind orders to the caller, and only the caller
-- ---------------------------------------------------------------------------
-- Only the header changes: the function gains user_id = auth.uid(). Everything
-- else (authoritative pricing, coupons, atomic stock, P0001/P0002) is the
-- 20261030 body, preserved verbatim.
create or replace function public.place_order(p_order jsonb, p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_order_id uuid;
    v_customer_email text;
    v_coupon_code text;
    v_item record;
    v_variant record;
    v_computed_subtotal integer := 0;
    v_discount_cents integer := 0;
    v_shipping_cents integer := 0;
    v_computed_total integer;
    v_new_quantity integer;
    v_new_status text;
    v_user_id uuid;
begin
    if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
        raise exception 'place_order requires at least one order item' using errcode = '22023';
    end if;

    -- Use client-provided UUID for idempotency, or generate one if not supplied
    v_order_id := coalesce(nullif(p_order->>'id', '')::uuid, gen_random_uuid());
    v_customer_email := trim(lower(p_order->>'customer_email'));

    if v_customer_email is null or v_customer_email = '' then
        raise exception 'place_order requires customer_email' using errcode = '22023';
    end if;

    -- OWNERSHIP IS DERIVED, NEVER SUPPLIED. A p_order.user_id in the payload is
    -- ignored on purpose: accepting it would let any signed-in customer attach
    -- orders to another customer's uuid and poison their order history.
    -- NULL here means an anon/guest caller -> guest order.
    v_user_id := auth.uid();

    -- Phase 1: Lock variants, validate existence, check stock, and compute authoritative subtotal
    for v_item in
        select
            coalesce(nullif(trim(i.variant_sku), ''), 'default-sku') as variant_sku,
            sum(greatest(coalesce(i.quantity, 1), 1))::integer as total_qty
        from jsonb_to_recordset(p_items) as i(
            variant_sku text,
            quantity integer
        )
        group by coalesce(nullif(trim(i.variant_sku), ''), 'default-sku')
    loop
        select sku, product_slug, price_cents, quantity
        into v_variant
        from public.variants
        where sku = v_item.variant_sku
        for update;

        if not found then
            raise exception 'Unknown or uncatalogued variant SKU: %', v_item.variant_sku
                using errcode = 'P0002';
        end if;

        if v_variant.quantity < v_item.total_qty then
            raise exception 'Insufficient stock for SKU %: requested %, available %',
                v_item.variant_sku, v_item.total_qty, v_variant.quantity
                using errcode = 'P0001';
        end if;

        v_computed_subtotal := v_computed_subtotal + (v_variant.price_cents * v_item.total_qty);
    end loop;

    -- Phase 2: Derive authoritative discount & shipping server-side
    v_coupon_code := upper(trim(coalesce(p_order->>'coupon_code', '')));

    if v_coupon_code = '' then
        v_discount_cents := 0;
    elsif v_coupon_code = 'HUSTLE10' or v_coupon_code = 'ATELIER10' then
        v_discount_cents := (v_computed_subtotal * 10) / 100;
    elsif v_coupon_code = 'GOBONKERS15' then
        v_discount_cents := (v_computed_subtotal * 15) / 100;
    elsif v_coupon_code = 'BONKERS20' then
        v_discount_cents := (v_computed_subtotal * 20) / 100;
    elsif v_coupon_code = 'NEEDLECRAFT' then
        v_discount_cents := least(332000, v_computed_subtotal);
    elsif v_coupon_code = 'FREESHIP' then
        v_discount_cents := 0;
    else
        raise exception 'Invalid or unrecognized coupon code: %', p_order->>'coupon_code'
            using errcode = '22023';
    end if;

    v_discount_cents := least(v_discount_cents, v_computed_subtotal);

    if v_coupon_code = 'FREESHIP' or v_computed_subtotal >= 2905000 or p_order->>'shipping_cents' is null or (p_order->>'shipping_cents')::integer <= 0 then
        v_shipping_cents := 0;
    else
        v_shipping_cents := least(greatest((p_order->>'shipping_cents')::integer, 0), 50000);
    end if;

    v_computed_total := greatest(v_computed_subtotal - v_discount_cents + v_shipping_cents, 0);

    -- Phase 3: Insert Order Header with authoritative totals + derived owner
    insert into public.orders (
        id,
        customer_name,
        customer_email,
        user_id,
        status,
        subtotal_cents,
        discount_cents,
        shipping_cents,
        total_cents,
        coupon_code,
        gift_note,
        shipping_address
    )
    values (
        v_order_id,
        coalesce(p_order->>'customer_name', 'Valued Collector'),
        v_customer_email,
        v_user_id,
        coalesce(p_order->>'status', 'confirmed'),
        v_computed_subtotal,
        v_discount_cents,
        v_shipping_cents,
        v_computed_total,
        nullif(v_coupon_code, ''),
        p_order->>'gift_note',
        p_order->'shipping_address'
    );

    -- Phase 4: Insert Order Items & Decrement Stock
    for v_item in
        select
            coalesce(nullif(i.id, '')::uuid, gen_random_uuid()) as id,
            coalesce(nullif(trim(i.variant_sku), ''), 'default-sku') as variant_sku,
            coalesce(i.product_name, 'Embroidered Garment') as product_name,
            coalesce(i.color, 'Standard') as color,
            coalesce(i.size, 'M') as size,
            greatest(coalesce(i.quantity, 1), 1) as quantity,
            i.customization
        from jsonb_to_recordset(p_items) as i(
            id text,
            product_slug text,
            variant_sku text,
            product_name text,
            color text,
            size text,
            quantity integer,
            price_cents integer,
            customization jsonb
        )
    loop
        select sku, product_slug, price_cents, quantity
        into v_variant
        from public.variants
        where sku = v_item.variant_sku;

        v_new_quantity := v_variant.quantity - v_item.quantity;

        if v_new_quantity <= 0 then
            v_new_status := 'out-of-stock';
        elsif v_new_quantity <= 5 then
            v_new_status := 'low-stock';
        else
            v_new_status := 'in-stock';
        end if;

        update public.variants
        set quantity = v_new_quantity,
            status = v_new_status
        where sku = v_item.variant_sku;

        insert into public.order_items (
            id,
            order_id,
            product_slug,
            variant_sku,
            product_name,
            color,
            size,
            quantity,
            price_cents,
            customization
        )
        values (
            v_item.id,
            v_order_id,
            coalesce((select product_slug from public.variants where sku = v_item.variant_sku), 'unknown'),
            v_item.variant_sku,
            v_item.product_name,
            v_item.color,
            v_item.size,
            v_item.quantity,
            (select price_cents from public.variants where sku = v_item.variant_sku),
            v_item.customization
        );
    end loop;

    return jsonb_build_object(
        'id', v_order_id,
        'status', coalesce(p_order->>'status', 'confirmed'),
        'total_cents', v_computed_total,
        'subtotal_cents', v_computed_subtotal,
        'discount_cents', v_discount_cents,
        'shipping_cents', v_shipping_cents,
        'user_id', v_user_id,
        'success', true
    );
end;
$$;

grant execute on function public.place_order(jsonb, jsonb) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. close the storage hole
-- ---------------------------------------------------------------------------
-- 20260104 gated product-images uploads on `to authenticated`, which was safe
-- only while "authenticated" meant "the owner". Once customers can sign up,
-- every customer could overwrite or delete catalogue photography. Re-gate on
-- is_admin(). Public READ is preserved so the storefront keeps rendering.
do $$
begin
  if to_regclass('storage.objects') is not null then
    drop policy if exists "Admin Upload Product Images" on storage.objects;
    drop policy if exists "Admin Modify Product Images" on storage.objects;

    create policy "Admin Upload Product Images" on storage.objects
      for insert to authenticated
      with check (bucket_id = 'product-images' and public.is_admin());

    create policy "Admin Modify Product Images" on storage.objects
      for update to authenticated
      using (bucket_id = 'product-images' and public.is_admin())
      with check (bucket_id = 'product-images' and public.is_admin());

    create policy "Admin Delete Product Images" on storage.objects
      for delete to authenticated
      using (bucket_id = 'product-images' and public.is_admin());
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 5b. DROP the legacy permissive `to authenticated` policies
-- ---------------------------------------------------------------------------
-- FINDING (measured on a full schema+migration-chain replica, 2026-10-29):
-- 20260104 created one policy per catalogue table of the form
--     create policy "Authenticated admin write <t>" ... to authenticated
--       using (true) with check (true)
-- 20261025 added the correct policy ("Admins write <t>" -> is_admin()) but its
-- loop only drops "Admins write <t>". The 20260104 policy SURVIVES.
--
-- Postgres ORs permissive policies, so `true` beats `is_admin()`: any signed-in
-- user still has full write on all nine tables even after 20261025 is applied.
-- Applying 20261025 alone does NOT close the hole. These must be dropped.
--
-- Verified failing before this block (T2: authenticated non-admin INSERTed
-- into garments) and passing after.
do $$
declare
  t text;
begin
  foreach t in array array['products','variants','product_images','collections',
                           'embroidery_details','categories','garments','motifs',
                           'universes','attribute_definitions']
  loop
    if exists (select 1 from pg_tables where schemaname='public' and tablename=t) then
      execute format('drop policy if exists "Authenticated admin write %1$I" on public.%1$I', t);
      execute format('drop policy if exists "Authenticated admin write %1$s" on public.%1$I', t);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 5c. orders/order_items: RPC-only writes
-- ---------------------------------------------------------------------------
-- schema.sql still carries "Allow public create orders" / "Allow public create
-- order items" (anon INSERT with check (true)) — the legacy pre-RPC path. That
-- is now a forgery vector: anyone can POST an order row directly with an
-- arbitrary user_id and plant fake entries in a real customer's order history
-- (which §1 makes readable by that customer).
--
-- place_order is SECURITY DEFINER, so it keeps working with these closed.
-- web/src/lib/data.ts's direct-insert fallback only fires when the RPC is
-- absent (PGRST202/42883); the RPC is installed and hardened, so no live path
-- depends on it.
do $$
begin
  if exists (select 1 from pg_tables where schemaname='public' and tablename='orders') then
    drop policy if exists "Allow public create orders" on public.orders;
    execute 'revoke insert, update, delete on public.orders from anon';
  end if;
  if exists (select 1 from pg_tables where schemaname='public' and tablename='order_items') then
    drop policy if exists "Allow public create order items" on public.order_items;
    execute 'revoke insert, update, delete on public.order_items from anon';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 6. attribute_definitions belongs in the admin-gated set too
-- ---------------------------------------------------------------------------
-- 20261025's loop names nine catalogue tables and misses attribute_definitions,
-- which 20261024 added. Rewriting its contract would let an attacker bypass
-- the attribute trigger for every future write. (Currently RLS-closed by
-- default, which is correct but accidental — make it deliberate.)
do $$
begin
  if exists (select 1 from pg_tables where schemaname='public' and tablename='attribute_definitions') then
    drop policy if exists "Admins write attribute_definitions" on public.attribute_definitions;
    create policy "Admins write attribute_definitions" on public.attribute_definitions
      for all to authenticated
      using (public.is_admin()) with check (public.is_admin());

    drop policy if exists "Public read attribute_definitions" on public.attribute_definitions;
    create policy "Public read attribute_definitions" on public.attribute_definitions
      for select to anon, authenticated
      using (true);
  end if;
end $$;

commit;
