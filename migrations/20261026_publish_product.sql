-- ============================================================================
-- 20261026_publish_product.sql
--
-- Publish a product from the Catalog Studio in one transaction.
--
-- WHY A FUNCTION AND NOT FIVE supabase.from() CALLS
--
-- A product is four tables: products, product_images, variants and
-- embroidery_details. Doing that from the browser means four round-trips with no
-- transaction, so a failure halfway leaves a product with no variants (invisible
-- on the storefront, since every card reads variants for price) or variants
-- pointing at a product that was never created. PostgREST cannot open a
-- transaction across requests. A plpgsql function runs inside one, and it already
-- has a precedent in this codebase: place_order() is exactly this shape.
--
-- It also closes the air gap properly rather than by trusting the client. The
-- panel previously emitted SQL for a human to paste; that step existed because
-- there was no trusted path, not because it was good. Now the panel sends JSON and
-- the database validates it — the same contract the seed and a manual paste go
-- through, so all three cannot disagree.
--
-- SECURITY
--   security definer with a pinned search_path, like place_order. But definer
--   functions bypass RLS, so the is_admin() gate below is the ONLY thing standing
--   between the anon key (public in the frontend bundle by construction) and the
--   catalog. It raises rather than returning a soft error, so a caller without
--   rights cannot mistake a no-op for success.
--
-- IDEMPOTENT
--   Upserts on slug / sku / product_slug, so re-publishing an edited product is
--   safe and matches the ON CONFLICT behaviour of the SQL the panel used to emit.
--
-- ORDER MATTERS
--   Run after 20261024 (attributes + trigger) and 20261025 (is_admin + policies).
-- ============================================================================

begin;

create or replace function public.publish_product(p_product jsonb, p_variants jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_slug        text;
  v_variant     jsonb;
  v_img         jsonb;
  v_sku         text;
  v_count       integer := 0;
  v_img_count   integer := 0;
  v_barcode     text;
begin
  -- ---------------------------------------------------------------------
  -- 0. Authorisation. First statement, before any parsing, so an
  --    unauthorised caller learns nothing about the payload's validity.
  -- ---------------------------------------------------------------------
  if not public.is_admin() then
    raise exception 'Not authorised to publish products'
      using errcode = '42501';  -- insufficient_privilege
  end if;

  if p_product is null or jsonb_typeof(p_product) is distinct from 'object' then
    raise exception 'publish_product requires a product object' using errcode = '22023';
  end if;

  v_slug := nullif(trim(p_product->>'slug'), '');
  if v_slug is null then
    raise exception 'publish_product requires a slug' using errcode = '22023';
  end if;

  -- Kebab-case. The slug becomes a URL and a foreign key target, so a bad one
  -- propagates to every child row rather than failing once.
  if v_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    raise exception 'slug "%" must be lowercase kebab-case', v_slug using errcode = '22023';
  end if;

  if nullif(trim(p_product->>'name'), '') is null then
    raise exception 'publish_product requires a name' using errcode = '22023';
  end if;

  -- country_of_origin is character(2) with a CHECK for ISO-3166 alpha-2. Both
  -- failures produce a raw type/constraint error naming a column the operator
  -- never typed into, so validate here and say which field is wrong.
  if nullif(trim(p_product->>'country_of_origin'), '') is not null
     and p_product->>'country_of_origin' !~ '^[A-Z]{2}$' then
    raise exception 'country_of_origin "%" must be a two-letter ISO code such as IN',
      p_product->>'country_of_origin' using errcode = '22023';
  end if;

  -- A product with no variants renders as a card with no price and cannot be
  -- bought. Refuse here rather than publishing something the storefront shows
  -- and every visitor bounces off.
  if p_variants is null
     or jsonb_typeof(p_variants) is distinct from 'array'
     or jsonb_array_length(p_variants) = 0 then
    raise exception 'publish_product requires at least one variant' using errcode = '22023';
  end if;

  -- ---------------------------------------------------------------------
  -- 1. Product row. The attribute trigger (20261024) validates
  --    p_product->attributes on the way in, so a missing required attribute
  --    for the chosen garment type aborts the whole transaction here.
  -- ---------------------------------------------------------------------
  insert into public.products (
    slug, name, subtitle, foreign_tagline, description,
    category_slug, universe_slug, collection_slug, garment_type, gender,
    motif_id, handcrafted, expression_score, edits, tags, featured,
    customizable, material, care, fit, style_code,
    country_of_origin, manufacturer_name, manufacturer_address, packed_by,
    cod_available, delivery_days_min, delivery_days_max, return_window_days,
    weight_grams, hsn_code, size_chart, attributes,
    fit_notes, model_height_cm, model_worn_size,
    package_length_mm, package_width_mm, package_height_mm
  ) values (
    v_slug,
    p_product->>'name',
    coalesce(p_product->>'subtitle', ''),
    nullif(p_product->>'foreign_tagline', ''),
    coalesce(p_product->>'description', ''),
    nullif(p_product->>'category_slug', ''),
    nullif(p_product->>'universe_slug', ''),
    nullif(p_product->>'collection_slug', ''),
    nullif(p_product->>'garment_type', ''),
    coalesce(p_product->>'gender', 'unisex'),
    nullif(p_product->>'motif_id', ''),
    coalesce((p_product->>'handcrafted')::boolean, false),
    coalesce((p_product->>'expression_score')::integer, 5),
    coalesce(
      (select array_agg(value::text) from jsonb_array_elements_text(p_product->'edits')),
      '{}'::text[]
    ),
    coalesce(
      (select array_agg(value::text) from jsonb_array_elements_text(p_product->'tags')),
      '{}'::text[]
    ),
    coalesce((p_product->>'featured')::boolean, false),
    coalesce((p_product->>'customizable')::boolean, false),
    coalesce(
      (select array_agg(value::text) from jsonb_array_elements_text(p_product->'material')),
      '{}'::text[]
    ),
    coalesce(
      (select array_agg(value::text) from jsonb_array_elements_text(p_product->'care')),
      '{}'::text[]
    ),
    coalesce(p_product->>'fit', ''),
    nullif(p_product->>'style_code', ''),
    coalesce(p_product->>'country_of_origin', 'IN'),
    nullif(p_product->>'manufacturer_name', ''),
    nullif(p_product->>'manufacturer_address', ''),
    nullif(p_product->>'packed_by', ''),
    coalesce((p_product->>'cod_available')::boolean, true),
    coalesce((p_product->>'delivery_days_min')::integer, 3),
    coalesce((p_product->>'delivery_days_max')::integer, 7),
    coalesce((p_product->>'return_window_days')::integer, 7),
    nullif(p_product->>'weight_grams', '')::integer,
    nullif(p_product->>'hsn_code', ''),
    coalesce(p_product->'size_chart', '{}'::jsonb),
    coalesce(p_product->'attributes', '{}'::jsonb),
    nullif(p_product->>'fit_notes', ''),
    nullif(p_product->>'model_height_cm', '')::integer,
    nullif(p_product->>'model_worn_size', ''),
    nullif(p_product->>'package_length_mm', '')::integer,
    nullif(p_product->>'package_width_mm', '')::integer,
    nullif(p_product->>'package_height_mm', '')::integer
  )
  on conflict (slug) do update set
    name                  = excluded.name,
    subtitle              = excluded.subtitle,
    foreign_tagline       = excluded.foreign_tagline,
    description           = excluded.description,
    category_slug         = excluded.category_slug,
    universe_slug         = excluded.universe_slug,
    collection_slug       = excluded.collection_slug,
    garment_type          = excluded.garment_type,
    gender                = excluded.gender,
    motif_id              = excluded.motif_id,
    handcrafted           = excluded.handcrafted,
    expression_score      = excluded.expression_score,
    edits                 = excluded.edits,
    tags                  = excluded.tags,
    featured              = excluded.featured,
    customizable          = excluded.customizable,
    material              = excluded.material,
    care                  = excluded.care,
    fit                   = excluded.fit,
    style_code            = excluded.style_code,
    country_of_origin     = excluded.country_of_origin,
    manufacturer_name     = excluded.manufacturer_name,
    manufacturer_address  = excluded.manufacturer_address,
    packed_by             = excluded.packed_by,
    cod_available         = excluded.cod_available,
    delivery_days_min     = excluded.delivery_days_min,
    delivery_days_max     = excluded.delivery_days_max,
    return_window_days    = excluded.return_window_days,
    weight_grams          = excluded.weight_grams,
    hsn_code              = excluded.hsn_code,
    size_chart            = excluded.size_chart,
    attributes            = excluded.attributes,
    fit_notes             = excluded.fit_notes,
    model_height_cm       = excluded.model_height_cm,
    model_worn_size       = excluded.model_worn_size,
    package_length_mm     = excluded.package_length_mm,
    package_width_mm      = excluded.package_width_mm,
    package_height_mm     = excluded.package_height_mm;

  -- ---------------------------------------------------------------------
  -- 2. Images. Delete-then-insert: slot order is a semantic index, so a
  --    product edited from 5 images to 3 must not leave stale slots 4 and 5
  --    behind. This mirrors the DELETE the generated SQL did.
  -- ---------------------------------------------------------------------
  delete from public.product_images where product_slug = v_slug;

  for v_img in select * from jsonb_array_elements(coalesce(p_product->'images', '[]'::jsonb))
  loop
    if nullif(v_img->>'src', '') is null then
      raise exception 'image at slot % has no src', v_img_count using errcode = '22023';
    end if;

    insert into public.product_images (product_slug, src, alt, color, sort_order)
    values (
      v_slug,
      v_img->>'src',
      coalesce(nullif(v_img->>'alt', ''), p_product->>'name'),
      nullif(v_img->>'color', ''),
      coalesce((v_img->>'sort_order')::integer, v_img_count)
    );
    v_img_count := v_img_count + 1;
  end loop;

  -- ---------------------------------------------------------------------
  -- 3. Variants. Barcode uniqueness is enforced by the UNIQUE index, but a
  --    duplicate would surface as a cryptic constraint name in the panel.
  --    The pre-check produces a message naming the SKU. The index remains the
  --    real guarantee — this is for the operator, not for correctness.
  -- ---------------------------------------------------------------------
  for v_variant in select * from jsonb_array_elements(p_variants)
  loop
    v_sku := nullif(trim(v_variant->>'sku'), '');
    if v_sku is null then
      raise exception 'every variant requires a sku' using errcode = '22023';
    end if;

    if nullif(v_variant->>'color', '') is null
       or nullif(v_variant->>'size', '') is null
       or nullif(v_variant->>'price_cents', '') is null then
      raise exception 'variant % requires color, size and price_cents', v_sku using errcode = '22023';
    end if;

    v_barcode := nullif(trim(v_variant->>'barcode'), '');

    if v_barcode is not null and v_barcode !~ '^[0-9]{8,14}$' then
      raise exception 'variant % barcode "%" must be 8-14 digits', v_sku, v_barcode
        using errcode = '22023';
    end if;

    if v_barcode is not null and exists (
      select 1 from public.variants
       where barcode = v_barcode and sku <> v_sku
    ) then
      raise exception 'barcode % is already used by another variant', v_barcode
        using errcode = '23505';
    end if;

    insert into public.variants (
      sku, product_slug, color, color_hex, size,
      price_cents, status, quantity, barcode
    ) values (
      v_sku,
      v_slug,
      v_variant->>'color',
      coalesce(nullif(v_variant->>'color_hex', ''), '#121214'),
      v_variant->>'size',
      (v_variant->>'price_cents')::integer,
      coalesce(nullif(v_variant->>'status', ''), 'in-stock'),
      coalesce((v_variant->>'quantity')::integer, 10),
      v_barcode
    )
    on conflict (sku) do update set
      color       = excluded.color,
      color_hex   = excluded.color_hex,
      size        = excluded.size,
      price_cents = excluded.price_cents,
      status      = excluded.status,
      quantity    = excluded.quantity,
      barcode     = excluded.barcode;

    v_count := v_count + 1;
  end loop;

  -- Unconditionally re-assert the parent, so a variant upsert can never land
  -- on a product_slug other than the one being published.
  update public.variants set product_slug = v_slug where sku in (
    select value->>'sku' from jsonb_array_elements(p_variants)
  );

  -- ---------------------------------------------------------------------
  -- 4. Craft provenance. Optional — a product may have no embroidery record.
  --    Note this is a real table, not invented prose: artisan_hours and
  --    technique must describe work that happened.
  -- ---------------------------------------------------------------------
  if p_product ? 'embroidery' and jsonb_typeof(p_product->'embroidery') = 'object' then
    insert into public.embroidery_details (
      product_slug, technique, technique_label, artisan_hours,
      placement, thread_composition, motif_story
    ) values (
      v_slug,
      coalesce(nullif(p_product->'embroidery'->>'technique', ''), 'hand-embroidery'),
      coalesce(nullif(p_product->'embroidery'->>'technique_label', ''), 'Hand Embroidery'),
      coalesce((p_product->'embroidery'->>'artisan_hours')::integer, 0),
      coalesce(
        (select array_agg(value::text)
           from jsonb_array_elements_text(p_product->'embroidery'->'placement')),
        '{}'::text[]
      ),
      coalesce(nullif(p_product->'embroidery'->>'thread_composition', ''), ''),
      coalesce(nullif(p_product->'embroidery'->>'motif_story', ''), '')
    )
    on conflict (product_slug) do update set
      technique          = excluded.technique,
      technique_label    = excluded.technique_label,
      artisan_hours      = excluded.artisan_hours,
      placement          = excluded.placement,
      thread_composition = excluded.thread_composition,
      motif_story        = excluded.motif_story;
  end if;

  return jsonb_build_object(
    'slug',       v_slug,
    'variants',   v_count,
    'images',     v_img_count,
    'published',  true
  );
end;
$$;

comment on function public.publish_product(jsonb, jsonb) is
  'Publishes a product and its children in one transaction. Admin-only; validates '
  'the attribute contract via the products trigger. Replaces paste-into-Supabase.';

-- Only authenticated callers may even reach the gate. anon is deliberately
-- excluded: the whole point is that the public key cannot publish. The role
-- exists on Supabase but not in a bare Postgres used for verification, so
-- revoke conditionally rather than making the migration fail on a test box.
revoke all on function public.publish_product(jsonb, jsonb) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on function public.publish_product(jsonb, jsonb) from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'grant execute on function public.publish_product(jsonb, jsonb) to authenticated';
  end if;
end $$;

commit;
