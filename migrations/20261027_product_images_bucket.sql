-- ============================================================================
-- 20261027_product_images_bucket.sql
--
-- Recreate the `product-images` storage bucket and its public-read policy.
--
-- WHY THIS FILE EXISTS
--   `schema.sql` creates the bucket via `insert into storage.buckets ... on
--   conflict do nothing`. That is idempotent against a bucket that still exists,
--   and does nothing at all once the row has been deleted -- which is what
--   happened: the bucket was removed by hand to clean up, and no later file puts
--   it back. Measured on the hosted project before this migration:
--
--     GET /storage/v1/bucket                          -> []      (no bucket)
--     GET /storage/v1/object/public/product-images/..  -> 400     (dead URL)
--     POST /storage/v1/object/product-images/..        -> 403     (refused)
--
--   So the Admin Studio's upload button was broken too, not just the
--   storefront's image URLs. A bucket is infrastructure, and infrastructure that
--   only exists in a bootstrap file is one dashboard click away from gone.
--
-- WHAT IT DOES
--   1. creates the bucket if absent (public = true: product photography is
--      served to anonymous storefront and mobile clients)
--   2. creates the public SELECT policy, so any client can read an object by URL
--   3. leaves WRITE gated -- see the note at the bottom. Upload happens with a
--      service-role key from the pipeline or an authenticated admin in the panel.
--
-- IDEMPOTENT: safe to run more than once.
--
-- ORDER: after schema.sql (needs the storage schema) and before any upload.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. The bucket
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do update
  set public = true;

-- ---------------------------------------------------------------------------
-- 2. Public read
-- ---------------------------------------------------------------------------
-- The storefront and the mobile app read images anonymously; without this the
-- public URL returns 400 even for a bucket that exists.
do $$
begin
  if to_regclass('storage.objects') is not null then
    drop policy if exists "Public Read Product Images" on storage.objects;
    create policy "Public Read Product Images" on storage.objects
      for select using (bucket_id = 'product-images');
  end if;
end $$;

commit;

-- ============================================================================
-- NOTE ON WRITES — do not add a public insert policy
-- ============================================================================
-- `schema.sql` ships `create policy "Public Upload Product Images" ... for insert
-- with check (bucket_id = 'product-images')` -- no role, so it applies to anon.
-- With the publishable key public in the browser bundle, that is anonymous
-- upload access to your project's storage quota, which is exactly the class of
-- hole 20260102/20260103/20260104 exist to close.
--
-- Keep writes on one of these two paths instead:
--
--   * the pipeline: a service-role/secret key in the environment, used by
--     products/_pipeline/scripts/export_images.py (never shipped to a client);
--   * the Admin Studio: an authenticated admin, covered by the
--     "Admin Upload Product Images" / "Admin Modify Product Images" policies
--     created in 20260104.
--
-- Verify after running:
--
--   curl -s -o /dev/null -w '%{http_code}\n' \
--     "$URL/storage/v1/object/public/product-images/does-not-exist.jpg"
--   # 400/404 both prove the bucket resolved; 400 with `Bucket not found` does not.
--
--   curl -s "$URL/storage/v1/bucket" -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
--   # -> [{"id":"product-images","name":"product-images","public":true,...}]
