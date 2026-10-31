-- ============================================================================
-- 20261105_order_payment_identity.sql
--
-- WHAT THIS FIXES
-- ---------------
-- `orders` could not answer "how was this paid?".
--
--   * There was no `payment_method` column. `place_order` derived `v_payment`
--     internally (for the COD surcharge and the status default) and then threw
--     it away. An online order and a COD order were byte-identical rows; the
--     only trace of COD was `cod_fee_cents > 0`, which is a CONSEQUENCE of COD,
--     not a record of it. An order below the free-shipping threshold whose COD
--     fee is zero is genuinely ambiguous today.
--
--   * There was nowhere to put the gateway's payment id. `payment_intents` holds
--     it, but an intent is a payment ATTEMPT; the order is the sale. A support
--     conversation starting from an order id could not reach the Razorpay
--     payment without a join the operator had to know to make.
--
-- WHY THE METHOD IS DERIVED, NOT READ FROM THE CLIENT
-- ---------------------------------------------------
-- `p_order->'shipping_address'->>'payment_method'` is client-supplied and is
-- only a hint. It is normalised to exactly 'cod' | 'prepaid' here so a junk
-- value collapses to 'prepaid' instead of violating the new CHECK and aborting
-- a valid sale. The server ALREADY trusts this field to compute the COD
-- surcharge, so the column records the same value the money was computed from:
-- it stops discarding an existing fact rather than adding a new trust edge.
--
-- WHY `payment_ref` IS NOT WRITTEN BY `place_order`
-- -------------------------------------------------
-- `place_order` runs with the caller's JWT (anon or customer), so anything it
-- reads from `p_order` is a client assertion. Accepting `payment_ref` there
-- would let anyone stamp an arbitrary string — or someone else's `pay_...` id —
-- onto their own order, corrupting the very audit trail the column exists to
-- provide. `razorpay-verify` stamps it instead, with the SERVICE ROLE, after the
-- signature and capture are proven. A client cannot reach that path.
--
-- The cost, stated plainly: a verify that places the order but fails to stamp it
-- leaves `payment_ref` NULL. `payment_intents.provider_payment_id` still holds
-- the id and `placed_order_id` identifies the row, so the gap is recoverable
-- rather than silent.
--
-- `place_order` CHANGES HERE. Its signature is unchanged, so neither client
-- needs an edit or a redeploy — but this file MUST be applied before the new
-- `razorpay-verify` starts writing `payment_ref`, or the stamp fails 42703.
--
-- ORDER OF OPERATIONS
-- -------------------
-- 1. Apply this migration.
-- 2. Redeploy `razorpay-verify` (it now stamps the order).
--
-- ROLLBACK
-- --------
--   drop index if exists public.idx_orders_payment_ref;
--   alter table public.orders drop column if exists payment_ref;
--   alter table public.orders drop constraint if exists orders_payment_method_valid;
--   alter table public.orders drop column if exists payment_method;
-- then re-paste `20261101_checkout_pricing.sql` to restore the previous
-- `place_order` body. Nothing else reads these columns, so dropping them is safe
-- even with live rows.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Columns
-- ---------------------------------------------------------------------------

alter table public.orders
  add column if not exists payment_method text,
  add column if not exists payment_ref    text;

comment on column public.orders.payment_method is
  'How the customer paid: prepaid (gateway) or cod. Derived server-side from the '
  'same v_payment that decides the COD surcharge and the status default. '
  'Client-supplied values are normalised, not trusted.';

comment on column public.orders.payment_ref is
  'Gateway payment id (e.g. Razorpay pay_...). Written ONLY by razorpay-verify '
  'under the service role, after signature + capture are proven. NULL means no '
  'gateway reference was stamped (COD, or a verify that failed to stamp it) — '
  'payment_intents.provider_payment_id is then the fallback.';

-- ---------------------------------------------------------------------------
-- 2. Backfill BEFORE the column is constrained
--
--    Two signals, in order of confidence:
--      a. status = 'confirmed-cod' — place_order's own COD default. Decisive.
--      b. cod_fee_cents > 0 — a COD surcharge was actually charged.
--    Anything matching neither defaults to 'prepaid'. That is an INFERENCE for a
--    prepaid-looking row, and it is recorded as such in
--    contracts/DEPLOY-order-payment.md: a COD order below the free-shipping
--    threshold carried no fee, so it cannot be distinguished from prepaid in
--    history. The column is authoritative from this migration forward only.
-- ---------------------------------------------------------------------------

update public.orders
   set payment_method = 'cod'
 where status = 'confirmed-cod'
    or coalesce(cod_fee_cents, 0) > 0;

update public.orders
   set payment_method = 'prepaid'
 where payment_method is null;

-- Now that every row has a value, enforce presence. NOT NULL is safe only
-- because the backfill above ran in this same transaction.
alter table public.orders alter column payment_method set not null;

-- ---------------------------------------------------------------------------
-- 3. Vocabulary: NOT VALID, then validated separately
--    Same two-step as 20261102 — on real data a bad row names itself rather
--    than aborting the migration opaquely.
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (
    select 1 from pg_constraint where conname = 'orders_payment_method_valid'
  ) then
    raise notice 'orders_payment_method_valid already present, skipping';
    return;
  end if;

  alter table public.orders
    add constraint orders_payment_method_valid
    check (payment_method in ('cod', 'prepaid'))
    not valid;
end $$;

do $$
declare
  v_bad text;
begin
  select string_agg(distinct payment_method, ', ' order by payment_method) into v_bad
    from public.orders
   where payment_method is not null
     and payment_method not in ('cod', 'prepaid');

  if v_bad is not null then
    raise exception 'orders.payment_method holds unrecognised value(s): %', v_bad
      using errcode = '23514';
  end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'orders_payment_method_valid' and convalidated
  ) then
    alter table public.orders validate constraint orders_payment_method_valid;
    raise notice 'orders_payment_method_valid validated';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 4. One payment cannot settle two orders
--
--    Partial, because payment_ref is NULL for COD and for any order not yet
--    stamped — NULLs are not compared by a unique index. This is the database's
--    answer to "verify ran twice and placed the order twice": the second stamp
--    collides instead of silently succeeding.
-- ---------------------------------------------------------------------------

create unique index if not exists idx_orders_payment_ref
  on public.orders(payment_ref)
  where payment_ref is not null;

-- ---------------------------------------------------------------------------
-- 5. place_order — record the method it already computed
--
--    VERBATIM from 20261101 §8, with three edits and nothing else:
--      (a) v_payment normalised to exactly cod|prepaid;
--      (b) payment_method added to the orders insert;
--      (c) payment_method echoed in the return payload.
--    Every other line — the lock order, price_cart, the stock gate, the
--    order_items insert, the redemption ledger's free_shipping handling — is
--    untouched. Re-deriving this body from memory is how a rewrite silently
--    drops a guarantee; it was extracted mechanically instead.
-- ---------------------------------------------------------------------------

create or replace function public.place_order(p_order jsonb, p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_order_id      uuid;
    v_customer_email text;
    v_payment       text;
    v_quote         jsonb;
    v_item          record;
    v_variant       public.variants%rowtype;
    v_new_quantity  integer;
    v_new_status    text;
    v_user_id       uuid;
    v_coupon_code   text;
    v_coupon_applied text;
    v_discount      integer;
begin
    if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
        raise exception 'place_order requires at least one order item' using errcode = '22023';
    end if;

    v_order_id := coalesce(nullif(p_order->>'id', '')::uuid, gen_random_uuid());
    v_customer_email := trim(lower(p_order->>'customer_email'));

    if v_customer_email is null or v_customer_email = '' then
        raise exception 'place_order requires customer_email' using errcode = '22023';
    end if;

    -- OWNERSHIP IS DERIVED, NEVER SUPPLIED (unchanged from 20261031).
    v_user_id := auth.uid();

    -- NORMALISED to exactly 'cod' | 'prepaid', never a raw client string.
    --
    -- Before 20261105 this was the raw lowercased value. Nothing ever read it
    -- back, so an unrecognised value was harmless-but-invisible: it behaved as
    -- "not cod" for both the surcharge and the status default. It is now WIRED
    -- TO A CHECK CONSTRAINT and stored on the order, so a junk value must
    -- collapse to 'prepaid' rather than abort a valid sale with 23514. The
    -- client is still only a hint; this is the normalisation of a hint, not
    -- trust in it.
    v_payment := case
        when lower(coalesce(
            nullif(p_order->'shipping_address'->>'payment_method', ''),
            case when p_order->>'status' = 'confirmed-cod' then 'cod' else 'prepaid' end
        )) = 'cod' then 'cod'
        else 'prepaid'
    end;
    v_coupon_code := nullif(upper(trim(coalesce(p_order->>'coupon_code', ''))), '');

    -- An unrecognized coupon must still abort with 22023 (CONTRACT §6). price_cart
    -- reports it as an error object rather than raising, so that the bag can show
    -- an inline message without a transaction; place_order turns it back into a raise.
    if v_coupon_code is not null then
        if not exists (select 1 from public.coupons where code = v_coupon_code and is_active) then
            raise exception 'Invalid or unrecognized coupon code: %', p_order->>'coupon_code'
                using errcode = '22023';
        end if;
    end if;

    -- Lock the coupon row before pricing if one is supplied. This serialises two
    -- concurrent checkouts that would otherwise both read "0 redemptions" and
    -- both redeem a per_user_limit = 1 code. A unique index cannot express this:
    -- it would hard-cap every guest at one use regardless of per_user_limit.
    if v_coupon_code is not null then
        perform 1 from public.coupons where code = v_coupon_code for update;
    end if;

    -- Lock every ordered variant FIRST, then price, then check stock.
    --
    -- The order matters for what the customer is told. If stock were checked
    -- before pricing, an 11-unit COD attempt on a low-stock SKU would report
    -- "insufficient stock" instead of "COD is limited to 10 units" — the second
    -- is the actual reason the order cannot proceed, and the first invites the
    -- customer to retry with a quantity that will fail again.
    --
    -- The lock is taken here (not inside price_cart) so price_cart stays
    -- callable read-only from quote_order without ever blocking a bag.
    for v_item in
        select coalesce(nullif(trim(i.variant_sku), ''), 'default-sku') as variant_sku,
               sum(greatest(coalesce(i.quantity, 1), 1))::integer as total_qty
          from jsonb_to_recordset(p_items) as i(variant_sku text, quantity integer)
         group by coalesce(nullif(trim(i.variant_sku), ''), 'default-sku')
         order by 1
    loop
        select * into v_variant from public.variants where sku = v_item.variant_sku for update;
        if not found then
            raise exception 'Unknown or uncatalogued variant SKU: %', v_item.variant_sku
                using errcode = 'P0002';
        end if;
    end loop;

    -- Pricing, coupon, COD-cap and shipping validation all happen here. Any of
    -- them raising aborts before a single row is written.
    v_quote := public.price_cart(p_items, v_coupon_code, v_customer_email, v_payment);

    if (v_quote->'coupon'->>'error') is not null then
        raise exception '%', (v_quote->'coupon'->>'error') using errcode = '22023';
    end if;

    -- Stock is verified against the locked rows, after the pricing rules have
    -- had their say.
    for v_item in
        select coalesce(nullif(trim(i.variant_sku), ''), 'default-sku') as variant_sku,
               sum(greatest(coalesce(i.quantity, 1), 1))::integer as total_qty
          from jsonb_to_recordset(p_items) as i(variant_sku text, quantity integer)
         group by coalesce(nullif(trim(i.variant_sku), ''), 'default-sku')
    loop
        select * into v_variant from public.variants where sku = v_item.variant_sku;
        if v_variant.quantity < v_item.total_qty then
            raise exception 'Insufficient stock for SKU %: requested %, available %',
                v_item.variant_sku, v_item.total_qty, v_variant.quantity
                using errcode = 'P0001';
        end if;
    end loop;

    v_coupon_applied := case
        when v_quote->'coupon'->>'code' is not null then v_quote->'coupon'->>'code'
        else null
    end;
    v_discount := coalesce((v_quote->>'discount_cents')::integer, 0);

    -- payment_method is recorded here. payment_ref is NOT: it is written by
    -- razorpay-verify under the service role, after the gateway has proven the
    -- payment. Accepting it from p_order would let any caller stamp a forged
    -- gateway reference onto their own order.
    insert into public.orders (
        id, customer_name, customer_email, user_id, status,
        subtotal_cents, discount_cents, shipping_cents, cod_fee_cents, total_cents,
        coupon_code, gift_note, shipping_address, payment_method
    ) values (
        v_order_id,
        coalesce(nullif(p_order->>'customer_name', ''), 'Valued Collector'),
        v_customer_email,
        v_user_id,
        coalesce(nullif(p_order->>'status', ''),
                 case when v_payment = 'cod' then 'confirmed-cod' else 'confirmed' end),
        (v_quote->>'subtotal_cents')::integer,
        v_discount,
        (v_quote->>'shipping_cents')::integer,
        (v_quote->>'cod_fee_cents')::integer,
        (v_quote->>'total_cents')::integer,
        v_coupon_applied,
        p_order->>'gift_note',
        p_order->'shipping_address',
        v_payment
    );

    for v_item in
        select coalesce(nullif(i.id, '')::uuid, gen_random_uuid()) as id,
               coalesce(nullif(trim(i.variant_sku), ''), 'default-sku') as variant_sku,
               coalesce(nullif(i.product_name, ''), 'Embroidered Garment') as product_name,
               coalesce(nullif(i.color, ''), 'Standard') as color,
               coalesce(nullif(i.size, ''), 'M') as size,
               greatest(coalesce(i.quantity, 1), 1) as quantity,
               i.customization
          from jsonb_to_recordset(p_items) as i(
               id text, product_slug text, variant_sku text, product_name text,
               color text, size text, quantity integer, price_cents integer,
               customization jsonb)
    loop
        select * into v_variant from public.variants where sku = v_item.variant_sku;

        v_new_quantity := v_variant.quantity - v_item.quantity;
        v_new_status := case
            when v_new_quantity <= 0 then 'out-of-stock'
            when v_new_quantity <= 3 then 'low-stock'
            else 'in-stock'
        end;

        update public.variants
           set quantity = v_new_quantity, status = v_new_status
         where sku = v_item.variant_sku;

        insert into public.order_items (
            id, order_id, product_slug, variant_sku, product_name,
            color, size, quantity, price_cents, customization
        ) values (
            v_item.id, v_order_id, v_variant.product_slug, v_item.variant_sku,
            v_item.product_name, v_item.color, v_item.size, v_item.quantity,
            -- Authoritative price from the DB, never the client's.
            v_variant.price_cents, v_item.customization
        );
    end loop;

    -- Ledger row last: it references the order, and a failed insert must roll
    -- the whole order back rather than leave a phantom redemption.
    --
    -- A free-shipping coupon legitimately has discount_cents = 0, so gating this
    -- on `v_discount > 0` records NOTHING for FREESHIP and its usage limits can
    -- never fire — the same code redeems forever. Gate on "a coupon was
    -- actually applied", and store whichever value was genuinely given.
    if v_coupon_applied is not null then
        insert into public.coupon_redemptions (
            coupon_code, order_id, user_id, customer_email, discount_applied_cents
        ) values (
            v_coupon_applied,
            v_order_id,
            v_user_id,
            v_customer_email,
            -- free_shipping coupons delivered value as waived carriage
            v_discount + case
                when (v_quote->'coupon'->>'free_shipping')::boolean
                    then (v_quote->>'flat_rate_cents')::integer
                else 0
            end
        );
    end if;

    return v_quote || jsonb_build_object(
        'id', v_order_id,
        'user_id', v_user_id,
        'payment_method', v_payment,
        'status', coalesce(nullif(p_order->>'status', ''),
                           case when v_payment = 'cod' then 'confirmed-cod' else 'confirmed' end),
        'success', true
    );
end;
$$;
comment on function public.place_order(jsonb, jsonb) is
  'CONTRACT §6. Server-authoritative pricing via price_cart; ownership from '
  'auth.uid(); payment_method recorded as derived (cod|prepaid). As of 20261105 '
  'it does NOT accept payment_ref — razorpay-verify stamps that under the '
  'service role, so a client can never forge a gateway reference.';

commit;
