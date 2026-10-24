# Write-path policies — what to change and in what order

**Status as measured on 2026-10-25 against `heimnfjuwmmmejqcjbbd.supabase.co`.**

The catalogue was loaded through the storefront's **publishable** key, using the
plain table endpoints. That worked because the write policies are still the
permissive ones from `schema.sql` (`using (true)` / `with check (true)`). This
document records what that means, and what to run to close it.

---

## 1. What is actually applied on the hosted project

| Migration | Applied? | Evidence |
|---|---|---|
| `schema.sql` | yes | 13 tables, 29 products readable |
| `20261024_data_model_trust_fields.sql` | **yes** | `attributes` column returns 200; `attribute_definitions` seeded (14 rows); the attribute trigger fires — inserting a sweater with `{}` attributes is refused with *"missing required attribute(s) … occasion, fabric_composition"* |
| `20261026_catalogue_garment_types.sql` | **yes** | `sweater`, `blouse`, `kurta`, `jeans` all resolve in `garments` |
| `20261025_admin_write_policies.sql` | **NO** | `public.admins` → HTTP 404 (table does not exist); `public.is_admin()` → *function not found* |
| `20261026_publish_product.sql` | **NO** | `rpc/publish_product` → *permission denied* / 404; `rpc/place_order` → *function not found* |

Measured consequence — an unauthenticated caller holding the key that ships in the
browser bundle can:

```
PATCH  /rest/v1/products?slug=eq.<anything>        -> HTTP 204   (updated)
DELETE /rest/v1/product_images?product_slug=eq.<x> -> HTTP 204   (deleted)
POST   /rest/v1/products                           -> HTTP 201   (created)
```

`204` on a write is success. This is not theoretical: a probe row created and
deleted through that key during this session was gone from the catalogue
afterwards. Anyone who opens devtools on the storefront can delete the entire
catalogue, and the storefront will simply render empty sections.

**Nothing about the load you just did was privileged.** It succeeded for the same
reason an attacker's request would.

---

## 2. The one thing that changes the risk profile

`20261024` and the garment-types migration are applied; `20261025` is not. Running
it is what converts the anon key from *"can delete everything"* to *"can read"*.

**Order matters** — `20261026_publish_product.sql` calls `public.is_admin()`, which
`20261025` creates. Reversed, the function fails to compile.

```
1. 20261025_admin_write_policies.sql     <- closes the hole
2. 20261026_publish_product.sql          <- the panel's transactional write path
3. promote an admin (bootstrap, below)
4. verify (below)
```

### 2a. Bootstrap problem — there is no admin yet

`20261025` grants write only to rows in `public.admins` or a JWT whose
`app_metadata.role` is `admin`/`service_role`. On a database where that table was
just created, **every** write is refused, including the admin panel's. So step 3 is
not optional — decide it before you run step 1, or the panel goes read-only.

Pick one:

```sql
-- Option A: promote an existing auth user (the panel's sign-in account)
insert into public.admins (user_id, email, note)
select id, email, 'bootstrap owner'
from auth.users
where email = 'admin@uniquelo.com'
on conflict (user_id) do nothing;

-- Option B: server-set claim, no table row needed
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
                        || '{"role":"admin"}'::jsonb
where email = 'admin@uniquelo.com';
```

Use `app_metadata`, never `user_metadata` — a user can set their own
`user_metadata`, which would make the gate self-service.

### 2b. Verify the lock took, by row count

RLS blocks **silently**: a refused delete returns success with zero rows affected.
Asserting "no error raised" inverts the verdict and certifies a locked table as
vulnerable. Measure the way an attacker would, and check both directions.

```bash
K="<publishable key>"; U="https://<ref>.supabase.co/rest/v1"

# BEFORE / AFTER counts
curl -s -I "$U/products?select=slug" -H "apikey: $K" -H "Authorization: Bearer $K" \
  -H "Prefer: count=exact" -H "Range: 0-0" | grep -i content-range

# The write must not change the count. 204 with an unchanged count = blocked.
curl -s -X DELETE "$U/products?slug=eq.arch-jaal-scarf" \
  -H "apikey: $K" -H "Authorization: Bearer $K" -w " HTTP %{http_code}\n"
```

Expected after `20261025`: the delete returns `2xx`/`204` **and the row is still
there**. A shrinking count is a failed lockdown.

Then confirm the *read* still works anonymously — a lockdown that also breaks the
storefront is an outage, not a fix.

### 2c. The table `20261025` does not cover

Its loop lists nine tables. `attribute_definitions` is **not** among them — it was
added by `20261024`, and the loop only touches tables it names. Measure it:

```bash
curl -s -X PATCH "$U/attribute_definitions?key=eq.pattern" \
  -H "apikey: $K" -H "Authorization: Bearer $K" \
  -H "Content-Type: application/json" -d '{"options":["sabotaged"]}' -w " HTTP %{http_code}\n"
```

If that succeeds, an anonymous caller can rewrite the attribute contract that the
trigger enforces — which lets them bypass validation for every future write. Add it
to the policy loop in the same migration:

```sql
-- inside the do $$ ... $$ loop's array, add 'attribute_definitions'
foreach t in array array['products','variants','product_images','collections',
                         'embroidery_details','categories','garments','motifs',
                         'universes','attribute_definitions']
```

---

## 3. How to load the catalogue once `20261025` is applied

`upload.py` will stop working the moment the lockdown lands — it uses the table
endpoints and the publishable key, deliberately, because that is the identity the
admin panel uses.

Two supported paths afterwards, in order of preference:

**A. `publish_product()` RPC (transactional — use this).** Grant is to
`authenticated` only, so the script needs a real admin session, not the anon key:

```bash
# sign in once, export the access token
TOKEN=$(curl -s -X POST "$U/../auth/v1/token?grant_type=password" \
  -H "apikey: $K" -H "Content-Type: application/json" \
  -d '{"email":"admin@uniquelo.com","password":"..."}' | jq -r .access_token)
```

Then POST `{"p_product": {...}, "p_variants": [...]}` to `rpc/publish_product`.
One transaction across four tables, so a mid-way failure cannot leave a product
with no variants. `upload.py` would need a `--token` mode; the payload shape is
already produced by `backend/scripts/render-publish-payload.mjs`.

**B. Keep `upload.py` as-is** and add the service-role key, server-side only.
Faster, but it reintroduces the bypass `20261026` exists to remove. If you choose
this, the key must never reach the web bundle — and the note in
`mobile/docs/phase-2-audit.md` about admin writes needing `service_role`
server-side is pointing at the same thing.

**C. Leave both unapplied.** Acceptable only while the project is a private
throwaway. Sampled above: it is not private, and the storefront's key is in the
bundle.

---

## 4. Smaller items worth fixing

- **`products` has no `status` / `is_mock` column.** Every row is live the instant
  it is inserted, and `getProducts()` serves all of them. There is no draft state,
  so a half-reviewed product cannot be staged. The 28 rows just loaded are
  therefore **already served by the storefront** — worth knowing before you share
  the URL.
- **No storage bucket exists** (`GET /storage/v1/bucket` → `[]`), and creating one
  is refused for the publishable key. Images are served from the web app's own
  `public/` directory as web-relative paths (`/images/products/<slug>-1.jpg`), so
  **the mobile client renders no product photography** — `ProductImage.isRemote`
  gates on an `http(s)` prefix and a leading `/` fails that test. Either host the
  images and write absolute URLs, or accept web-only and record it in the client
  contract.
- **`place_order()` is not installed** (`404`). Checkout and the mobile app's only
  write path are both non-functional against this database. Confirm whether orders
  are meant to work yet.

---

## 5. What was changed in the pipeline for this load

Both defects were silent — the build stayed green and the data looked plausible.

1. **`publish.py` emitted image URLs that were never written.** It built
   `src` as `/images/products/01-angles/00-front.png` (the *source crop* path),
   while `export_images.py` writes flat `/images/products/<slug>-1.jpg`. Every PDP
   image would have 404'd. `collect_images()` now emits the exported path, and the
   validator refuses to publish when the emitted `src` has no file on disk — so
   this cannot come back unnoticed.

2. **Two products derived identical SKUs.** `floral-skeleton-hoodie` and
   `floral-swoosh-hoodie` both reduced to `FSH-BLACK-*`. `variants.sku` is the
   primary key, so the second upload overwrote the first's rows and one product
   would have gone live with **zero variants** — a card with no price that cannot
   be bought. The SKU prefix now comes from `style_code` (already unique per
   product, derived from the slug), and a cross-product uniqueness check in
   `publish.py --all` fails the batch on any SKU or barcode collision. Both guards
   were proved by rejection: the old path and a forced collision each fail with
   their own message.

3. **`upload.py` added** as the missing publish stage, and `export_images.py` was
   run for the whole set (two products had stale exports, so they had no delivered
   JPEGs at all).
