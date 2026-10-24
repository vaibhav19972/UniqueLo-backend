-- ✅ SUPERSEDED 2026-10-23 by 20260104000000_lockdown_auth_admin.sql (D-15) —
--    the OA-5 trigger fired (Admin Studio authenticated); retained for fresh-
--    environment replay history (order 02 → 03 → 04 composes correctly).
-- ─────────────────────────────────────────────────────────────────────────────
-- INTERIM catalogue write lockdown (D-13) — core-only revoke.
--
-- Context: the hosted project has no Supabase Auth yet, and the web app's
-- Admin Studio (web repo `src/pages/Admin.tsx`) runs under the PUBLIC
-- publishable key. It performs two write paths the full lockdown would break:
--   * product-photography uploads into the `product-images` storage bucket
--     (`supabase.storage.from('product-images').upload(...)`)
--   * taxonomy quick-add upserts on `categories`, `garments`, `collections`
-- The full lockdown (20260102000000_lock_catalogue_writes.sql — OA-2, paused)
-- revokes those too, so until an authenticated admin flow exists, this interim
-- revokes only what Admin Studio does NOT write:
--   products, variants, product_images, embroidery_details, universes, motifs
--
-- Accepted residual risks until OA-5 completes the lockdown (explicit, D-13):
--   * anyone holding the publishable key can still upload files into the
--     product-images bucket (anonymous file hosting on this project's quota);
--   * taxonomy tables stay insert/updatable: a bad actor can deface labels,
--     imagery and ordering, but CANNOT touch products, variants, prices,
--     stock or embroidery content;
--   * the permissive demo POLICIES on the revoked tables remain in place —
--     inert while their grants are revoked (revoke is the enforcing control);
--     the completion file drops them.
--
-- Completion trigger (OA-5): wire an authenticated admin gate on web /admin,
-- then deploy 20260102000000_lock_catalogue_writes.sql in full — its revokes
-- supersede this interim (idempotent) and it additionally drops the upload
-- policy. Admin-Studio anon writes deliberately break at that point and must
-- move to the service_role / authenticated role.
--
-- Post-run verification: POST /rest/v1/products with type-valid columns
-- ({name, slug} — no 'subtitle') must flip from 23502 (not-null constraint,
-- grant live) to permission denied (42501/403). Same for garments.
-- ─────────────────────────────────────────────────────────────────────────────

revoke insert, update, delete
  on public.products, public.variants, public.product_images,
     public.embroidery_details, public.universes, public.motifs
  from anon, authenticated;
