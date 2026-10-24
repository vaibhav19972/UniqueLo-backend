-- ─────────────────────────────────────────────────────────────────────────────
-- Production catalogue & storage lockdown — authenticated-admin completion
-- (closes D-5 / D-13 / OA-2 / OA-5; decision D-15, deployed 2026-10-23)
--
-- Trigger: the web Admin Studio moved to Supabase Auth, so staff no longer
-- writes under the bare publishable key. With an authenticated admin flow the
-- finish line becomes: catalogue writes go to `authenticated` only, `anon`
-- keeps read-only storefront access, and storage uploads move from the public
-- policy to authenticated-only policies.
--
-- What it does:
--   1. drops remaining public/anon write policies on the NINE catalogue tables
--      (products, variants, product_images, embroidery_details, universes,
--      categories, collections, motifs, garments)
--   2. revokes INSERT/UPDATE/DELETE from anon on all nine
--   3. grants INSERT/UPDATE/DELETE to authenticated
--   4. recreates per-table authenticated write policies
--   5. storage: drops "Public Upload Product Images"; creates authenticated
--      "Admin Upload / Admin Modify Product Images" on bucket `product-images`
--
-- Preserved: public SELECT everywhere (storefront), guest orders/order_items
-- inserts, newsletter, reviews, and the `place_order` v2 RPC (OA-1).
--
-- KNOWN GAP (OA-6): `authenticated` = any signed-in user — there is no admin
-- predicate yet (catalogue policies are `using (true) with check (true)`;
-- storage policies check only `bucket_id`). Gate both by an admin claim/
-- allowlist BEFORE public sign-up ships.
--
-- Replay history: this file supersedes the deployed D-13 interim
-- (`20260103`). On a fresh environment, running `20260102` → `20260103` →
-- `20260104` in order composes to the current hosted state (step 3 re-grants
-- what `20260102` revoked from `authenticated`).
--
-- Live verification (2026-10-23, publishable-key REST, nothing written):
-- catalogue reads 9/9 `200`; `orders` anon read → 0 rows; anon INSERT refusal
-- battery → `42501 permission denied` on all nine tables. Storage not
-- probe-tested (stray-object risk); the authenticated path is proven by the
-- Admin Studio sign-in smoke.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Drop existing public write policies on catalog tables
do $$
declare
  policy record;
  catalogue_tables text[] := array[
    'products', 'variants', 'product_images', 'embroidery_details',
    'universes', 'categories', 'collections', 'motifs', 'garments'
  ];
begin
  for policy in
    select p.tablename, p.policyname
    from pg_policies p
    where p.schemaname = 'public'
      and p.tablename = any (catalogue_tables)
      and p.cmd in ('ALL', 'INSERT', 'UPDATE', 'DELETE')
      and p.roles && array['public', 'anon']::name[]
  loop
    execute format('drop policy if exists %I on public.%I',
                   policy.policyname, policy.tablename);
  end loop;
end $$;

-- 2. Revoke write permissions from public anon role
revoke insert, update, delete
  on public.products, public.variants, public.product_images,
     public.embroidery_details, public.universes, public.categories,
     public.collections, public.motifs, public.garments
  from anon;

-- 3. Grant write permissions to authenticated staff role
grant insert, update, delete
  on public.products, public.variants, public.product_images,
     public.embroidery_details, public.universes, public.categories,
     public.collections, public.motifs, public.garments
  to authenticated;

-- 4. Enable authenticated write policies on catalog
do $$
declare
  t text;
  catalogue_tables text[] := array[
    'products', 'variants', 'product_images', 'embroidery_details',
    'universes', 'categories', 'collections', 'motifs', 'garments'
  ];
begin
  for t in select unnest(catalogue_tables) loop
    execute format('drop policy if exists "Authenticated admin write %I" on public.%I', t, t);
    execute format('create policy "Authenticated admin write %I" on public.%I for all to authenticated using (true) with check (true)', t, t);
  end loop;
end $$;

-- 5. Secure storage: Drop public upload, allow authenticated staff uploads
do $$
begin
  if to_regclass('storage.objects') is not null then
    drop policy if exists "Public Upload Product Images" on storage.objects;
    drop policy if exists "Admin Upload Product Images" on storage.objects;
    drop policy if exists "Admin Modify Product Images" on storage.objects;

    create policy "Admin Upload Product Images" on storage.objects
      for insert to authenticated
      with check (bucket_id = 'product-images');

    create policy "Admin Modify Product Images" on storage.objects
      for all to authenticated
      using (bucket_id = 'product-images')
      with check (bucket_id = 'product-images');
  end if;
end $$;
