-- ─────────────────────────────────────────────────────────────────────────────
-- place_order v2 + get_order_details: atomic orders for UniqueLo (D-12, OA-1)
--
-- v2 (contributed by the backend agent; reviewed + executed against a local
-- PostgreSQL 16.15 clone on 2026-10-23 — Rule 1). Supersedes the v1 in this
-- file's history (same migration number: v1 was never deployed to the hosted
-- project, so there is no upgrade path to preserve).
--
-- Why v2 replaced v1 (all *verified*, see PROJECT_STATE verification row):
--   * SECURITY DEFINER + `set search_path = public, pg_temp` — the atomic write
--     no longer depends on anon INSERT policies staying permissive, and the
--     pinned search_path protects definer name resolution (supabase hygiene).
--   * `customer_email` is required and normalized (trim + lower).
--   * `id`/item `id` fall back to `gen_random_uuid()` when absent/empty;
--     a client-supplied id still gives PK-level retry dedupe (23505).
--   * Item fields get harmless fallbacks; `quantity` clamps to ≥ 1.
--   * `get_order_details(uuid, text)` — guest order lookup (no-auth backend):
--     the only sanctioned read path into `orders` (which has NO public SELECT
--     policy), gated by matching the stored email. Callable by anon +
--     `authenticated` (future auth-ready web client); the Android app does not
--     call it yet (Phase 4 order-history candidate).
--
-- Verified against the LIVE hosted schema by REST introspection before adoption:
--   orders:    id, customer_name, customer_email, status, subtotal_cents,
--              discount_cents, shipping_cents, total_cents, coupon_code,
--              gift_note, shipping_address, created_at (all exist)
--   order_items: id, order_id, product_slug, variant_sku, product_name, color,
--              size, quantity, price_cents, customization — NO created_at
--              (hence not inserted here)
-- Local-clone battery (uniquelo_clone): app-shaped payload round-trip (status
-- 'reserved' stored, email lowercased, created_at default applied, items
-- attached to the FN-created header id, client order_id ignored, junk keys
-- ignored, absent customization stored NULL), same-id retry → 23505, empty
-- items → 22023, missing email → 22023, generated-id path, quantity clamp,
-- get_order_details (match / wrong email / unknown id → null), and legacy
-- anon-INSERT parity for the app's fallback path.
--
-- Known nuance (documented, not patched — contributors' SQL ships verbatim):
-- only `id` falls back on EMPTY string; other text fields treat '' as a value,
-- so '' bypasses the coalesce fallbacks. The Android app always sends
-- catalogue-backed non-empty strings, so this cannot trigger from our client.
--
-- App contract (composeApp SupabaseRepository): body is
--   { p_order: {id, customer_name, customer_email, status:'reserved',
--     subtotal_cents, discount_cents, shipping_cents, total_cents,
--     shipping_address {line1, city, postal_code, country} },
--     p_items: [{id, order_id(ignored by fn), product_slug, variant_sku,
--     product_name, color, size, quantity, price_cents}] }
-- coupon_code / gift_note / customization are absent from the app payload and
-- must stay optional; the response BODY is unused by the app (status-code +
-- PGRST202 fallback only), so new response fields are safe to add.
--
-- Landmines honored (PROJECT_STATE #1/#2): no `RETURNING` (orders has no
-- public SELECT), `created_at` never column-named (jsonb paths don't apply
-- DEFAULTs — every other masked column is absent from these INSERT lists).
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.place_order(p_order jsonb, p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_order_id uuid;
    v_customer_email text;
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

    -- 1. Insert Order Header
    insert into public.orders (
        id,
        customer_name,
        customer_email,
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
        coalesce(p_order->>'status', 'confirmed'),
        coalesce((p_order->>'subtotal_cents')::integer, 0),
        coalesce((p_order->>'discount_cents')::integer, 0),
        coalesce((p_order->>'shipping_cents')::integer, 0),
        coalesce((p_order->>'total_cents')::integer, 0),
        p_order->>'coupon_code',
        p_order->>'gift_note',
        p_order->'shipping_address'
    );

    -- 2. Insert Order Items (with fallback UUIDs per item)
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
    select
        coalesce(nullif(i.id, '')::uuid, gen_random_uuid()),
        v_order_id,
        coalesce(i.product_slug, 'unknown-product'),
        coalesce(i.variant_sku, 'default-sku'),
        coalesce(i.product_name, 'Embroidered Garment'),
        coalesce(i.color, 'Standard'),
        coalesce(i.size, 'M'),
        greatest(coalesce(i.quantity, 1), 1),
        coalesce(i.price_cents, 0),
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
    );

    return jsonb_build_object(
        'success', true,
        'id', v_order_id,
        'status', coalesce(p_order->>'status', 'confirmed'),
        'total_cents', coalesce((p_order->>'total_cents')::integer, 0)
    );
end;
$$;

-- Grant execute to both web and mobile clients
grant execute on function public.place_order(jsonb, jsonb) to anon, authenticated;

create or replace function public.get_order_details(p_order_id uuid, p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_order record;
    v_items jsonb;
begin
    select * into v_order
    from public.orders
    where id = p_order_id and lower(customer_email) = lower(trim(p_email));

    if not found then
        return null;
    end if;

    select coalesce(jsonb_agg(to_jsonb(i)), '[]'::jsonb)
    into v_items
    from public.order_items i
    where i.order_id = p_order_id;

    return jsonb_build_object(
        'order', to_jsonb(v_order),
        'items', v_items
    );
end;
$$;

grant execute on function public.get_order_details(uuid, text) to anon, authenticated;
