-- ═════════════════════════════════════════════════════════════════════════════
-- ℹ️ SUPERSEDED (2026-10-23, D-15/OA-5) — the lockdown completion shipped as
--    `20260104000000_lockdown_auth_admin.sql`: the Admin Studio moved to
--    Supabase Auth, so the finish line became the authenticated-admin variant
--    (this file's anon revokes + grants/policies/storage for `authenticated`
--    there) rather than this file's blanket revoke. Kept for fresh-environment
--    replay history: `02 → 03 → 04` in order composes to the current hosted
--    state (this file's revoke from `authenticated` is re-granted by
--    20260104 step 3). Do not re-run standalone against a live project.
-- ═════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- Catalogue write lockdown (audit A13 → decision D-5, open action OA-2).
--
-- The sample/demo data shipped permissive public write policies on the
-- catalogue tables: any visitor holding the anon key could insert, update or
-- delete products, variants, images, details, and merchandising tables.
--
-- This script:
--   1. drops every policy that grants `public`, `anon` or `authenticated` any
--      write action on those tables (names unknown → enumerated from
--      pg_policies),
--   2. revokes INSERT/UPDATE/DELETE privileges from anon and authenticated,
--   3. drops the demo policy that lets any visitor upload into the public
--      `product-images` storage bucket (the app only reads images; admin
--      uploads will use service_role).
--
-- It deliberately does NOT touch:
--   - SELECT (the catalogue must stay publicly readable),
--   - orders / order_items / newsletter_subscribers / reviews (guest
--     insert-only flows stay as-is, governed by their own policies),
--   - the anon/authenticated roles' ability to read.
--
-- Admin edits should run under the service_role key once an admin flow
-- exists. Apply in the Supabase dashboard SQL editor (or `supabase db push`).
-- Safe to re-run: every statement is idempotent.
-- ─────────────────────────────────────────────────────────────────────────────

do $$
declare
  policy record;
  catalogue_tables text[] := array[
    'products', 'variants', 'product_images', 'embroidery_details',
    'universes', 'categories', 'collections', 'motifs', 'garments'
  ];
begin
  -- pg_policies.permissive is text ('PERMISSIVE'/'RESTRICTIVE' on PG 14+) and
  -- introduced version drift here once already; match on the write command and
  -- the granted roles instead, which are stable across releases.
  --
  -- Role overlap (&&) rather than equality: the shipped schema creates these
  -- policies without a `to` clause (roles = {public}), but dashboard-created
  -- policies are often explicit `to anon, authenticated`. Both must go.
  for policy in
    select p.tablename, p.policyname
    from pg_policies p
    where p.schemaname = 'public'
      and p.tablename = any (catalogue_tables)
      and p.cmd in ('ALL', 'INSERT', 'UPDATE', 'DELETE')
      and p.roles && array['public', 'anon', 'authenticated']::name[]
  loop
    execute format('drop policy if exists %I on public.%I',
                   policy.policyname, policy.tablename);
  end loop;
end $$;

revoke insert, update, delete
  on public.products, public.variants, public.product_images,
     public.embroidery_details, public.universes, public.categories,
     public.collections, public.motifs, public.garments
  from anon, authenticated;

-- The bucket stays publicly readable (the app hotlinks product photography),
-- but no client flow uploads. Guarded so the migration also runs on a bare
-- local PostgreSQL clone that has no Supabase `storage` schema.
do $$
begin
  if to_regclass('storage.objects') is not null then
    drop policy if exists "Public Upload Product Images" on storage.objects;
  end if;
end $$;

-- Sanity check (run manually afterwards):
--   select tablename, policyname, cmd from pg_policies
--    where schemaname = 'public'
--      and tablename in ('products','variants','product_images',
--                        'embroidery_details','universes','categories',
--                        'collections','motifs','garments')
--      and cmd in ('ALL','INSERT','UPDATE','DELETE')
--      and roles && array['public','anon','authenticated']::name[];
-- Expected: 0 rows.
--
--   select tablename, policyname, cmd from pg_policies
--    where schemaname = 'storage' and tablename = 'objects'
--      and cmd in ('ALL','INSERT','UPDATE','DELETE')
--      and roles && array['public','anon','authenticated']::name[];
-- Expected: no policy that permits uploads to `product-images`.
--
-- Executed against a local PostgreSQL 16.15 clone built from the real
-- `supabase/schema.sql` DDL and Supabase-style grants: 23 write policies on
-- nine catalogue tables plus the product-image upload policy dropped; re-run
-- is idempotent; anon SELECT retained; anon INSERT/UPDATE/DELETE denied;
-- guest orders, order items, newsletter inserts and `place_order` still work.
