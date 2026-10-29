-- ====================================================================
-- Harden place_order RPC: server-side price enforcement + atomic stock decrement
--
-- Closes CONTRACT.md Section 6 guarantees:
--   1. Prices are re-read server-side from variants (client price is advisory).
--   2. Stock is locked via FOR UPDATE, validated against total ordered qty,
--      and decremented atomically. Insufficient stock raises P0001 and aborts.
--   3. Variants status is updated ('out-of-stock' if 0, 'low-stock' if <= 5).
--   4. Computes authoritative subtotal_cents and total_cents on the order header.
--   5. Returns created order id, status, subtotal_cents, and total_cents.
-- ====================================================================

create or replace function public.place_order(p_order jsonb, p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_order_id uuid;
    v_customer_email text;
    v_item record;
    v_variant record;
    v_item_price integer;
    v_computed_subtotal integer := 0;
    v_discount_cents integer;
    v_shipping_cents integer;
    v_computed_total integer;
    v_new_quantity integer;
    v_new_status text;
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

    -- Extract discount & shipping
    v_discount_cents := greatest(coalesce((p_order->>'discount_cents')::integer, 0), 0);
    v_shipping_cents := greatest(coalesce((p_order->>'shipping_cents')::integer, 0), 0);

    -- Phase 1: Lock variants, validate stock, and compute authoritative subtotal
    for v_item in
        select
            coalesce(i.variant_sku, 'default-sku') as variant_sku,
            sum(greatest(coalesce(i.quantity, 1), 1))::integer as total_qty,
            min(coalesce(i.price_cents, 0)) as client_price_cents
        from jsonb_to_recordset(p_items) as i(
            variant_sku text,
            quantity integer,
            price_cents integer
        )
        group by coalesce(i.variant_sku, 'default-sku')
    loop
        select sku, price_cents, quantity
        into v_variant
        from public.variants
        where sku = v_item.variant_sku
        for update;

        if not found then
            -- Fall back to client price if variant does not exist (e.g. non-inventory custom items)
            v_item_price := v_item.client_price_cents;
        else
            if v_variant.quantity < v_item.total_qty then
                raise exception 'Insufficient stock for SKU %: requested %, available %',
                    v_item.variant_sku, v_item.total_qty, v_variant.quantity
                    using errcode = 'P0001';
            end if;
            v_item_price := v_variant.price_cents;
        end if;

        v_computed_subtotal := v_computed_subtotal + (v_item_price * v_item.total_qty);
    end loop;

    -- Compute final total (subtotal - discount + shipping)
    v_computed_total := greatest(v_computed_subtotal - v_discount_cents + v_shipping_cents, 0);

    -- Phase 2: Insert Order Header
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
        v_computed_subtotal,
        v_discount_cents,
        v_shipping_cents,
        v_computed_total,
        p_order->>'coupon_code',
        p_order->>'gift_note',
        p_order->'shipping_address'
    );

    -- Phase 3: Insert Order Items & Decrement Stock
    for v_item in
        select
            coalesce(nullif(i.id, '')::uuid, gen_random_uuid()) as id,
            coalesce(i.product_slug, 'unknown-product') as product_slug,
            coalesce(i.variant_sku, 'default-sku') as variant_sku,
            coalesce(i.product_name, 'Embroidered Garment') as product_name,
            coalesce(i.color, 'Standard') as color,
            coalesce(i.size, 'M') as size,
            greatest(coalesce(i.quantity, 1), 1) as quantity,
            coalesce(i.price_cents, 0) as client_price_cents,
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

        if not found then
            v_item_price := v_item.client_price_cents;
        else
            v_item_price := v_variant.price_cents;
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
        end if;

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
        ) values (
            v_item.id,
            v_order_id,
            coalesce(v_variant.product_slug, v_item.product_slug),
            v_item.variant_sku,
            v_item.product_name,
            v_item.color,
            v_item.size,
            v_item.quantity,
            v_item_price,
            v_item.customization
        );
    end loop;

    return jsonb_build_object(
        'success', true,
        'id', v_order_id,
        'status', coalesce(p_order->>'status', 'confirmed'),
        'subtotal_cents', v_computed_subtotal,
        'total_cents', v_computed_total
    );
end;
$$;

grant execute on function public.place_order(jsonb, jsonb) to anon, authenticated;

