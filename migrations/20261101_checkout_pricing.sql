-- ====================================================================
-- 20261101_checkout_pricing.sql
--
-- Checkout pricing becomes data-driven, and MRPs become real.
--
-- This migration does four things, in dependency order:
--
--   1. variants gain compare_at_ends_at — a dated markdown expires itself,
--      so a strike-through can never outlive the sale it describes.
--   2. public.coupons + public.coupon_redemptions + public.shipping_rules —
--      the promotion engine. Replaces the if/else ladder that exists today in
--      BOTH CartDrawer.tsx and place_order.
--   3. public.price_cart() — ONE pricing routine. quote_order and place_order
--      both call it, so the bag and the order can never disagree.
--   4. public.quote_order() — read-only quote for the bag and /checkout.
--      place_order is rewritten to call price_cart() too, and keeps every
--      existing error code (22023 / P0001 / P0002) it already promises.
--
-- Shaped by owner decisions (2026-10-30):
--   shipping  flat Rs 99, free above Rs 1,499
--   COD       Rs 59 fee, max 10 units per order
--   coupons   surfaced as a prompt, never auto-applied
--   MRP       real MRPs exist; strike-through only where declared
--
-- FREE-SHIPPING RULE: eligibility is evaluated on the PRE-DISCOUNT subtotal.
-- A customer who applies a coupon must never lose free delivery — that turns
-- a reward into a punishment and is a leading cause of checkout abandonment.
--
-- Idempotent: safe to run more than once.
-- ====================================================================

begin;

-- ---------------------------------------------------------------------------
-- 0. MRP gets an expiry
-- ---------------------------------------------------------------------------
-- variants.compare_at_price_cents already exists (schema.sql:169) and is NULL
-- on all 197 hosted rows. Without an end date, a markdown badge is permanent —
-- which is exactly how "sale" pricing becomes a false claim. Null = open-ended.
alter table public.variants
  add column if not exists compare_at_ends_at timestamptz;

comment on column public.variants.compare_at_ends_at is
  'When the compare_at_price_cents markdown stops being claimable. NULL = no expiry. '
  'The client must not render a strike-through once now() > this.';

-- A markdown with no reference price is meaningless; a reference price at or
-- below the selling price is not a discount. Enforce both at the storage layer
-- so no client, script, or admin paste can create a fabricated discount.
--
-- Order matters: EXISTING rows are quarantined BEFORE the constraint is added.
-- A plain ADD CONSTRAINT aborts on real data (hosted carried four
-- UL-S68C-CREAM variants whose compare_at sat below their price), which would
-- leave the whole migration unapplied. An MRP at or below the selling price has
-- no honest reading — it is either a bad MRP or a bad price — so the only safe
-- action is to delete the unverifiable claim, not to invent a replacement.
-- Every quarantined row is reported so it can be re-entered correctly.
do $$
declare
  v_bad int;
begin
  select count(*) into v_bad
  from public.variants
  where compare_at_price_cents is not null
    and compare_at_price_cents <= price_cents;

  if v_bad > 0 then
    raise warning 'Quarantining % variant(s) whose compare_at_price_cents <= price_cents. '
                  'Setting compare_at_price_cents = NULL (the claim is unverifiable, not corrected). '
                  'Rows: %', v_bad,
      (select string_agg(sku || ' (price ' || price_cents || ', mrp ' || compare_at_price_cents || ')', '; ')
       from public.variants
       where compare_at_price_cents is not null
         and compare_at_price_cents <= price_cents);

    update public.variants
       set compare_at_price_cents = null,
           compare_at_ends_at = null
     where compare_at_price_cents is not null
       and compare_at_price_cents <= price_cents;
  end if;

  -- An expiry with no markdown to expire is also a lie.
  update public.variants
     set compare_at_ends_at = null
   where compare_at_ends_at is not null
     and compare_at_price_cents is null;

  if not exists (
    select 1 from pg_constraint where conname = 'variants_mrp_exceeds_price'
  ) then
    alter table public.variants
      add constraint variants_mrp_exceeds_price
      check (compare_at_price_cents is null or compare_at_price_cents > price_cents);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'variants_mrp_ends_needs_mrp'
  ) then
    alter table public.variants
      add constraint variants_mrp_ends_needs_mrp
      check (compare_at_ends_at is null or compare_at_price_cents is not null);
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1. Promotion engine: coupons
-- ---------------------------------------------------------------------------
create table if not exists public.coupons (
  code               text primary key,
  description        text,
  -- 'percent'       discount_value is percentage points (10 = 10%)
  -- 'fixed'         discount_value is paise
  -- 'free_shipping' discount_value is ignored; waives the shipping line
  discount_type      text not null check (discount_type in ('percent', 'fixed', 'free_shipping')),
  discount_value     integer not null default 0 check (discount_value >= 0),
  -- Ceiling for percentage coupons. NULL = uncapped (dangerous; prefer a cap).
  max_discount_cents integer check (max_discount_cents is null or max_discount_cents > 0),
  min_subtotal_cents integer not null default 0 check (min_subtotal_cents >= 0),
  starts_at          timestamptz not null default now(),
  expires_at         timestamptz,
  total_usage_limit  integer check (total_usage_limit is null or total_usage_limit > 0),
  per_user_limit     integer not null default 1 check (per_user_limit > 0),
  first_order_only   boolean not null default false,
  -- Only one coupon applies per order today. The column exists so stacking can
  -- be switched on later without a schema change; false means "cannot combine".
  stackable          boolean not null default false,
  -- Whether this code may be ADVERTISED to a customer who has not typed it.
  -- Staff/VIP/compensation codes set this false: they stay redeemable if you
  -- know the code, but the best_coupon prompt will never reveal them.
  is_public          boolean not null default true,
  is_active          boolean not null default true,
  created_at         timestamptz not null default now(),
  constraint coupons_window_valid check (expires_at is null or expires_at > starts_at),
  constraint coupons_percent_sane check (discount_type <> 'percent' or discount_value between 1 and 100)
);

comment on table public.coupons is
  'Promotion codes. Codes are stored uppercase; clients may submit any case. '
  'Replaces the hardcoded if/else ladder that previously existed in both the '
  'web client and place_order — marketing adds a code with an INSERT, not a deploy.';

alter table public.coupons enable row level security;

-- Public read: the bag must be able to list live offers without a service key.
drop policy if exists "Public read active coupons" on public.coupons;
create policy "Public read active coupons" on public.coupons
  for select to anon, authenticated
  using (is_active);

-- No client INSERT/UPDATE/DELETE policy at all. Only service_role (which
-- bypasses RLS) or a SQL editor can create promotions. This mirrors the
-- `admins` posture: absence of a policy is the lock.

create index if not exists idx_coupons_active_window
  on public.coupons(is_active, starts_at, expires_at);

-- ---------------------------------------------------------------------------
-- 2. Redemption ledger — the only thing that can enforce per-user limits
-- ---------------------------------------------------------------------------
create table if not exists public.coupon_redemptions (
  id                     uuid primary key default gen_random_uuid(),
  coupon_code            text not null references public.coupons(code) on delete restrict,
  order_id               uuid not null references public.orders(id) on delete cascade,
  -- Set when a signed-in customer placed the order. NULL for guest orders,
  -- which is why email is the fallback identity below.
  user_id                uuid references auth.users(id) on delete set null,
  customer_email         text not null,
  discount_applied_cents integer not null check (discount_applied_cents >= 0),
  created_at             timestamptz not null default now()
);

comment on table public.coupon_redemptions is
  'One row per coupon use. Written only inside place_order. Without this table a '
  'per-user limit is unenforceable — there is nowhere to count from.';

alter table public.coupon_redemptions enable row level security;
-- Deliberately NO client policies: this is an internal ledger. A customer who
-- could read it would learn every code that exists and who used it.

create index if not exists idx_coupon_redemptions_code
  on public.coupon_redemptions(coupon_code);
create index if not exists idx_coupon_redemptions_email
  on public.coupon_redemptions(lower(customer_email), coupon_code);
create index if not exists idx_coupon_redemptions_user
  on public.coupon_redemptions(user_id, coupon_code) where user_id is not null;

-- Concurrency guard for single-use coupons.
--
-- place_order locks variant rows, but two orders for DIFFERENT SKUs take disjoint
-- locks and run in parallel. Both would read "0 prior redemptions" and both apply
-- a per_user_limit = 1 code. A count-based check cannot close that race.
--
-- Solved with a FOR UPDATE row lock on the coupon itself (see place_order), NOT a
-- unique index: an index on (coupon_code, email) would hard-cap every guest at
-- ONE redemption no matter what per_user_limit says, silently overriding
-- FREESHIP's limit of 3. Serialising on the coupon row lets the count do its job
-- while still making concurrent redemption impossible.

-- ---------------------------------------------------------------------------
-- 3. Shipping rules — one row, no client write
-- ---------------------------------------------------------------------------
create table if not exists public.shipping_rules (
  id               uuid primary key default gen_random_uuid(),
  name             text not null,
  flat_rate_cents  integer not null default 0 check (flat_rate_cents >= 0),
  -- NULL = always free. Otherwise: free when PRE-DISCOUNT subtotal reaches this.
  free_above_cents integer check (free_above_cents is null or free_above_cents >= 0),
  cod_fee_cents    integer not null default 0 check (cod_fee_cents >= 0),
  -- Unit count, not rupees. NULL = no cap.
  cod_max_units    integer check (cod_max_units is null or cod_max_units > 0),
  cod_enabled      boolean not null default true,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now()
);

comment on table public.shipping_rules is
  'Delivery economics. cod_max_units is a UNIT COUNT cap, not a rupee cap. '
  'free_above_cents is compared against the pre-discount subtotal on purpose: '
  'using a coupon must never cost the customer free delivery.';

alter table public.shipping_rules enable row level security;

drop policy if exists "Public read shipping rules" on public.shipping_rules;
create policy "Public read shipping rules" on public.shipping_rules
  for select to anon, authenticated
  using (is_active);

-- Seed the single active rule. Owner decisions 2026-10-30.
insert into public.shipping_rules (name, flat_rate_cents, free_above_cents, cod_fee_cents, cod_max_units)
select 'India standard', 9900, 149900, 5900, 10
where not exists (select 1 from public.shipping_rules where is_active);

-- ---------------------------------------------------------------------------
-- 4. orders gains cod_fee_cents
-- ---------------------------------------------------------------------------
-- Kept separate from shipping_cents: folding a COD surcharge into courier cost
-- destroys any later COD-vs-prepaid margin analysis, and misstates what was
-- actually spent on carriage.
alter table public.orders
  add column if not exists cod_fee_cents integer not null default 0;

comment on column public.orders.cod_fee_cents is
  'Cash-on-delivery surcharge, reported separately from shipping_cents.';

-- ---------------------------------------------------------------------------
-- 5. Seed the coupons the UI already advertises
-- ---------------------------------------------------------------------------
-- The old client claimed minimums it never enforced (BONKERS20 demanded
-- Rs 9,999 in the UI and nothing in SQL). These rows make the claim true.
insert into public.coupons
  (code, description, discount_type, discount_value, max_discount_cents,
   min_subtotal_cents, per_user_limit, first_order_only)
values
  ('HUSTLE10',    '10% off your order',         'percent', 10, 30000,  99900, 1, false),
  ('ATELIER10',   '10% welcome to the atelier', 'percent', 10, 30000,  99900, 1, true),
  ('GOBONKERS15', '15% off orders above Rs 2,499', 'percent', 15, 50000, 249900, 1, false),
  ('BONKERS20',   '20% off orders above Rs 3,999', 'percent', 20, 80000, 399900, 1, false),
  ('NEEDLECRAFT', 'Rs 3,320 off bespoke needlecraft', 'fixed', 332000, null, 999900, 1, false),
  ('FREESHIP',    'Complimentary delivery',      'free_shipping', 0, null, 0, 3, false)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- 6. THE pricing routine — one implementation, two callers
-- ---------------------------------------------------------------------------
-- Everything that decides money lives here. quote_order renders it; place_order
-- enforces it. If these ever diverge, the customer is quoted one number and
-- charged another — which is precisely the bug this migration exists to kill
-- (client said Rs 1,999 shipping, server clamped to Rs 500).
--
-- Price is ALWAYS read from public.variants. A client-supplied price is never
-- consulted, so a tampered payload cannot change what is charged.

-- Adding p_check_identity would otherwise CREATE a 5-arg overload and leave the
-- 4-arg function callable and ambiguous. Drop it explicitly.
drop function if exists public.price_cart(jsonb, text, text, text);

create or replace function public.price_cart(
    p_items          jsonb,
    p_coupon_code    text default null,
    p_customer_email text default null,
    p_payment_method text default 'prepaid',
    -- When false, per-user and first-order gates are NOT evaluated against
    -- p_customer_email. quote_order passes false for anonymous callers: an
    -- unauthenticated caller can type any email, so honouring it would let
    -- anyone probe "does this person have an order?" through the error message.
    p_check_identity boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_rules          public.shipping_rules%rowtype;
    v_coupon         public.coupons%rowtype;
    v_code           text;
    v_item           record;
    v_variant        public.variants%rowtype;
    v_line           jsonb := '[]'::jsonb;
    v_subtotal       integer := 0;
    v_units          integer := 0;
    v_discount       integer := 0;
    v_shipping       integer := 0;
    v_cod_fee        integer := 0;
    v_total          integer := 0;
    v_free_ship      boolean := false;
    v_coupon_error   text := null;
    v_coupon_ok      boolean := false;
    v_best           jsonb := null;
    v_now            timestamptz := now();
    v_redemptions    integer := 0;
    v_is_cod         boolean;
begin
    if jsonb_typeof(p_items) is distinct from 'array'
       or jsonb_array_length(p_items) = 0 then
        raise exception 'A bag needs at least one item' using errcode = '22023';
    end if;

    v_is_cod := lower(coalesce(p_payment_method, 'prepaid')) = 'cod';

    select * into v_rules
      from public.shipping_rules
     where is_active
     order by created_at
     limit 1;

    if not found then
        raise exception 'No active shipping rule is configured' using errcode = 'P0003';
    end if;

    -- ------------------------------------------------------------------
    -- 6a. Per-line pricing, authoritative from variants
    -- ------------------------------------------------------------------
    for v_item in
        select coalesce(nullif(trim(i.variant_sku), ''), '') as variant_sku,
               sum(greatest(coalesce(i.quantity, 1), 1))::integer as qty
          from jsonb_to_recordset(p_items) as i(variant_sku text, quantity integer)
         group by coalesce(nullif(trim(i.variant_sku), ''), '')
    loop
        select * into v_variant from public.variants where sku = v_item.variant_sku;

        if not found then
            raise exception 'Unknown or uncatalogued variant SKU: %', v_item.variant_sku
                using errcode = 'P0002';
        end if;

        -- A markdown is claimable only while it is unexpired. Past the end date
        -- the strike-through is a false statement, so the reference price is
        -- dropped here rather than trusted to the client.
        v_line := v_line || jsonb_build_object(
            'sku',                v_variant.sku,
            'product_slug',       v_variant.product_slug,
            'size',               v_variant.size,
            'color',              v_variant.color,
            'quantity',           v_item.qty,
            'unit_price_cents',   v_variant.price_cents,
            'line_total_cents',   v_variant.price_cents * v_item.qty,
            'compare_at_cents',
                case
                    when v_variant.compare_at_price_cents is not null
                     and v_variant.compare_at_price_cents > v_variant.price_cents
                     and (v_variant.compare_at_ends_at is null
                          or v_variant.compare_at_ends_at > v_now)
                    then v_variant.compare_at_price_cents
                    else null
                end,
            'stock_available',    v_variant.quantity
        );

        v_subtotal := v_subtotal + (v_variant.price_cents * v_item.qty);
        v_units    := v_units + v_item.qty;
    end loop;

    -- ------------------------------------------------------------------
    -- 6b. Coupon evaluation
    -- ------------------------------------------------------------------
    v_code := upper(trim(coalesce(p_coupon_code, '')));

    if v_code <> '' then
        select * into v_coupon from public.coupons where code = v_code;

        if not found or not v_coupon.is_active then
            v_coupon_error := 'This code is not valid.';
        elsif v_now < v_coupon.starts_at then
            v_coupon_error := 'This offer has not started yet.';
        elsif v_coupon.expires_at is not null and v_now >= v_coupon.expires_at then
            v_coupon_error := 'This offer has expired.';
        elsif v_subtotal < v_coupon.min_subtotal_cents then
            v_coupon_error := format(
                'Add items worth Rs %s more to use this code.',
                ((v_coupon.min_subtotal_cents - v_subtotal) / 100)
            );
        else
            -- Global usage limit
            if v_coupon.total_usage_limit is not null then
                select count(*) into v_redemptions
                  from public.coupon_redemptions where coupon_code = v_code;
                if v_redemptions >= v_coupon.total_usage_limit then
                    v_coupon_error := 'This offer is no longer available.';
                end if;
            end if;

            -- Per-user limit.
            --
            -- COUNT BOTH IDENTITIES, always. Counting only auth.uid() when
            -- signed in lets a customer redeem as a guest (user_id NULL), then
            -- sign in with the same email and redeem again — the limit silently
            -- doubles. Counting only email lets one household share a code.
            -- The union of both is the honest answer: a redemption is "yours" if
            -- it came from your session OR your email.
            --
            -- p_check_identity = false disables the EMAIL half only. A validated
            -- session is a real identity; a typed-in email is a claim.
            if v_coupon_error is null and v_coupon.per_user_limit is not null then
                select count(*) into v_redemptions
                  from public.coupon_redemptions r
                 where r.coupon_code = v_code
                   and (
                        (auth.uid() is not null and r.user_id = auth.uid())
                     or (p_check_identity
                         and nullif(trim(coalesce(p_customer_email, '')), '') is not null
                         and lower(r.customer_email) = lower(trim(p_customer_email)))
                   );
                if v_redemptions >= v_coupon.per_user_limit then
                    v_coupon_error := 'You have already used this code.';
                end if;
            end if;

            -- First-order gate. Same union logic: a prior GUEST order under this
            -- email must count, or a returning customer signs in and claims a
            -- first-order-only code they are not entitled to.
            if v_coupon_error is null and v_coupon.first_order_only then
                select count(*) into v_redemptions
                  from public.orders o
                 where (
                        (auth.uid() is not null and o.user_id = auth.uid())
                     or (p_check_identity
                         and nullif(trim(coalesce(p_customer_email, '')), '') is not null
                         and lower(o.customer_email) = lower(trim(p_customer_email)))
                   );
                if v_redemptions > 0 then
                    v_coupon_error := 'This code is for first orders only.';
                end if;
            end if;
        end if;

        if v_coupon_error is null then
            v_coupon_ok := true;
            if v_coupon.discount_type = 'percent' then
                v_discount := (v_subtotal * v_coupon.discount_value) / 100;
                if v_coupon.max_discount_cents is not null then
                    v_discount := least(v_discount, v_coupon.max_discount_cents);
                end if;
            elsif v_coupon.discount_type = 'fixed' then
                v_discount := v_coupon.discount_value;
            else
                v_free_ship := true;
            end if;
            v_discount := least(v_discount, v_subtotal);
        end if;
    end if;

    -- ------------------------------------------------------------------
    -- 6c. Shipping: evaluated on the PRE-DISCOUNT subtotal
    -- ------------------------------------------------------------------
    if v_free_ship then
        v_shipping := 0;
    elsif v_rules.free_above_cents is not null and v_subtotal >= v_rules.free_above_cents then
        v_shipping := 0;
    else
        v_shipping := v_rules.flat_rate_cents;
    end if;

    -- ------------------------------------------------------------------
    -- 6d. COD fee and unit cap
    -- ------------------------------------------------------------------
    if v_is_cod then
        if not v_rules.cod_enabled then
            raise exception 'Cash on delivery is not available' using errcode = '22023';
        end if;
        if v_rules.cod_max_units is not null and v_units > v_rules.cod_max_units then
            -- Enforcement lives here, not in the UI: a client-side cap is a
            -- suggestion, and the RTO risk of a 40-piece COD order is real.
            raise exception
                'Cash on delivery is limited to % units per order (yours has %). Please pay online.',
                v_rules.cod_max_units, v_units
                using errcode = '22023';
        end if;
        v_cod_fee := v_rules.cod_fee_cents;
    end if;

    v_total := greatest(v_subtotal - v_discount + v_shipping + v_cod_fee, 0);

    -- ------------------------------------------------------------------
    -- 6e. Best eligible coupon — for the PROMPT, never auto-applied
    -- ------------------------------------------------------------------
    -- Owner decision: surface the best offer, let the customer click Apply.
    --
    -- "Eligible" must mean exactly what redemption means, or the prompt offers
    -- a code that then fails on click — the worst possible time to disappoint.
    -- So this applies the SAME gates as 6b: public only (never leak a staff or
    -- VIP code nobody typed), window, minimum, global cap, per-user limit and
    -- first-order-only. Anything that would be rejected on apply is not offered.
    select to_jsonb(c)
      into v_best
      from (
        select c.code, c.description, c.discount_type, c.discount_value,
               case
                   when c.discount_type = 'percent' then
                       least((v_subtotal * c.discount_value) / 100,
                             coalesce(c.max_discount_cents, 2147483647))
                   when c.discount_type = 'fixed' then least(c.discount_value, v_subtotal)
                   else 0
               end as value_cents,
               c.min_subtotal_cents
          from public.coupons c
         where c.is_active
           and c.is_public
           and c.code <> v_code
           and v_now >= c.starts_at
           and (c.expires_at is null or v_now < c.expires_at)
           and v_subtotal >= c.min_subtotal_cents
           and (c.total_usage_limit is null
                or (select count(*) from public.coupon_redemptions r
                     where r.coupon_code = c.code) < c.total_usage_limit)
           -- per-user limit, same union identity rule as 6b
           and (c.per_user_limit is null
                or (select count(*) from public.coupon_redemptions r
                     where r.coupon_code = c.code
                       and (
                            (auth.uid() is not null and r.user_id = auth.uid())
                         or (p_check_identity
                             and nullif(trim(coalesce(p_customer_email, '')), '') is not null
                             and lower(r.customer_email) = lower(trim(p_customer_email)))
                       )) < c.per_user_limit)
           -- first-order-only coupons are not offered to a returning buyer
           and (not c.first_order_only
                or not exists (
                     select 1 from public.orders o
                      where (
                             (auth.uid() is not null and o.user_id = auth.uid())
                          or (p_check_identity
                              and nullif(trim(coalesce(p_customer_email, '')), '') is not null
                              and lower(o.customer_email) = lower(trim(p_customer_email)))
                      )))
      ) c
     order by c.value_cents desc, c.code
     limit 1;

    return jsonb_build_object(
        'lines',            v_line,
        'units',            v_units,
        'subtotal_cents',   v_subtotal,
        'discount_cents',   v_discount,
        'shipping_cents',   v_shipping,
        'cod_fee_cents',    v_cod_fee,
        'total_cents',      v_total,
        'free_shipping_threshold_cents', v_rules.free_above_cents,
        'flat_rate_cents',  v_rules.flat_rate_cents,
        'cod_max_units',    v_rules.cod_max_units,
        'payment_method',   case when v_is_cod then 'cod' else 'prepaid' end,
        'coupon', case
            when v_coupon_ok then jsonb_build_object(
                'code', v_code,
                'discount_type', v_coupon.discount_type,
                'discount_cents', v_discount,
                'free_shipping', v_free_ship
            )
            when v_code <> '' then jsonb_build_object('code', v_code, 'error', v_coupon_error)
            else null
        end,
        'best_coupon',      v_best,
        -- Every coupon the customer could actually use right now, for the
        -- "View all offers" sheet. Same gates as best_coupon, so nothing is
        -- advertised that would be refused on click.
        'available_offers',
            coalesce((
                -- value_cents is sorted NUMERICALLY. Ordering by the jsonb text
                -- value sorts lexicographically, which puts '9900' above '14990'.
                select jsonb_agg(o order by (o->>'value_cents')::integer desc, o->>'code')
                  from (
                    select jsonb_build_object(
                               'code', c.code,
                               'description', c.description,
                               'discount_type', c.discount_type,
                               'discount_value', c.discount_value,
                               'min_subtotal_cents', c.min_subtotal_cents,
                               'value_cents',
                                   case
                                       when c.discount_type = 'percent' then
                                           least((v_subtotal * c.discount_value) / 100,
                                                 coalesce(c.max_discount_cents, 2147483647))
                                       when c.discount_type = 'fixed' then
                                           least(c.discount_value, v_subtotal)
                                       else v_rules.flat_rate_cents
                                   end
                           ) as o, c.code as ord
                      from public.coupons c
                     where c.is_active
                       and c.is_public
                       and c.code <> v_code
                       and v_now >= c.starts_at
                       and (c.expires_at is null or v_now < c.expires_at)
                       and v_subtotal >= c.min_subtotal_cents
                       and (c.total_usage_limit is null
                            or (select count(*) from public.coupon_redemptions r
                                 where r.coupon_code = c.code) < c.total_usage_limit)
                       and (c.per_user_limit is null
                            or (select count(*) from public.coupon_redemptions r
                                 where r.coupon_code = c.code
                                   and (
                                        (auth.uid() is not null and r.user_id = auth.uid())
                                     or (p_check_identity
                                         and nullif(trim(coalesce(p_customer_email, '')), '') is not null
                                         and lower(r.customer_email) = lower(trim(p_customer_email)))
                                   )) < c.per_user_limit)
                       and (not c.first_order_only
                            or not exists (
                                 select 1 from public.orders o2
                                  where (
                                         (auth.uid() is not null and o2.user_id = auth.uid())
                                      or (p_check_identity
                                          and nullif(trim(coalesce(p_customer_email, '')), '') is not null
                                          and lower(o2.customer_email) = lower(trim(p_customer_email)))
                                  )))
                  ) t
            ), '[]'::jsonb),
        -- Real, verifiable saving. Never a floor, never a multiplier.
        'savings_cents',
            coalesce((select sum((l->>'compare_at_cents')::integer * (l->>'quantity')::integer
                                 - (l->>'line_total_cents')::integer)
                        from jsonb_array_elements(v_line) l
                       where l->>'compare_at_cents' is not null), 0)
            + v_discount
            + case when v_shipping = 0 then v_rules.flat_rate_cents else 0 end
    );
end;
$$;

-- The 5-arg signature: adding a defaulted parameter creates a NEW function, so
-- grants must target the new signature or they fail outright.
grant execute on function public.price_cart(jsonb, text, text, text, boolean) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7. quote_order — read-only, for the bag AND /checkout
-- ---------------------------------------------------------------------------
-- The client renders exactly what this returns. No arithmetic in components:
-- that is how the bag ended up inventing a 21% discount and a Rs 74.95 saving.
-- The 5-arg form replaces the 4-arg one (same reason as price_cart above: a
-- default parameter creates an overload, not a replacement).
drop function if exists public.quote_order(jsonb, text, text, text);

create or replace function public.quote_order(
    p_items          jsonb,
    p_coupon_code    text default null,
    p_customer_email text default null,
    p_payment_method text default 'prepaid'
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_trust_email boolean;
begin
    -- Trust p_customer_email only when the caller is signed in AND the email is
    -- their own. Otherwise it is a typed-in claim: an anonymous caller could
    -- otherwise resolve "does victim@example.com have an order?" purely by
    -- reading the first-order-only error message. Unauthenticated callers can
    -- still apply coupons; they just cannot probe someone else's history, and
    -- the address book in their own session still counts.
    v_trust_email := auth.uid() is not null
                     and lower(coalesce(auth.jwt()->>'email', '')) =
                         lower(trim(coalesce(p_customer_email, '')));

    return public.price_cart(
               p_items, p_coupon_code, p_customer_email, p_payment_method, v_trust_email
           ) || jsonb_build_object('quoted_at', now(), 'identity_checked', v_trust_email);
end;
$$;

grant execute on function public.quote_order(jsonb, text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 8. place_order — same pricing routine, plus the write
-- ---------------------------------------------------------------------------
-- Preserved verbatim from 20261031 EXCEPT:
--   * money comes from price_cart() instead of an if/else ladder
--   * client-supplied subtotal/discount/shipping/total are IGNORED entirely
--   * cod_fee_cents is stored
--   * a redemption row is written when a coupon is actually applied
--   * COD unit cap enforced
-- Error codes are unchanged: 22023 (bad input/coupon/COD cap), P0001 (stock),
-- P0002 (unknown SKU). Clients depend on these; do not renumber.
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

    v_payment := lower(coalesce(
        nullif(p_order->'shipping_address'->>'payment_method', ''),
        case when p_order->>'status' = 'confirmed-cod' then 'cod' else 'prepaid' end
    ));
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

    insert into public.orders (
        id, customer_name, customer_email, user_id, status,
        subtotal_cents, discount_cents, shipping_cents, cod_fee_cents, total_cents,
        coupon_code, gift_note, shipping_address
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
        p_order->'shipping_address'
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
        'status', coalesce(nullif(p_order->>'status', ''),
                           case when v_payment = 'cod' then 'confirmed-cod' else 'confirmed' end),
        'success', true
    );
end;
$$;

grant execute on function public.place_order(jsonb, jsonb) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 9. publish_product learns about MRP
-- ---------------------------------------------------------------------------
-- The RPC previously inserted variants WITHOUT compare_at_price_cents, so an
-- admin-published markdown was silently dropped — the column existed and was
-- never written. Adding it here is what makes the admin path able to set an MRP
-- at all.
create or replace function public.set_variant_mrp(
    p_sku               text,
    p_compare_at_cents  integer,
    p_ends_at           timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_variant public.variants%rowtype;
begin
    if not public.is_admin() then
        raise exception 'set_variant_mrp requires admin' using errcode = '42501';
    end if;

    select * into v_variant from public.variants where sku = p_sku for update;
    if not found then
        raise exception 'Unknown variant SKU: %', p_sku using errcode = 'P0002';
    end if;

    if p_compare_at_cents is not null and p_compare_at_cents <= v_variant.price_cents then
        raise exception 'compare_at_price_cents (%) must exceed price_cents (%) for %',
            p_compare_at_cents, v_variant.price_cents, p_sku
            using errcode = '22023';
    end if;

    update public.variants
       set compare_at_price_cents = p_compare_at_cents,
           compare_at_ends_at     = case when p_compare_at_cents is null then null else p_ends_at end
     where sku = p_sku;

    return jsonb_build_object(
        'sku', p_sku,
        'compare_at_price_cents', p_compare_at_cents,
        'compare_at_ends_at', p_ends_at
    );
end;
$$;

revoke all on function public.set_variant_mrp(text, integer, timestamptz) from anon;
grant execute on function public.set_variant_mrp(text, integer, timestamptz) to authenticated;

commit;
