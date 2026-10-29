# Write-path policies — what to change and in what order

**Status as measured on 2026-10-25 against `heimnfjuwmmmejqcjbbd.supabase.co`; re-verified read-only the same day (§0).**

## 0. Re-verification — read-only probe, 2026-10-25

| Probe | Result |
|---|---|
| `products` columns | 44 — trust/marketplace set present; `is_mock`, `intensity`, `sold_count`, `batch_*`, `craft_*` all absent |
| `rpc/place_order` | **installed** — posting `{"p_order":{…},"p_items":[]}` returns `400 22023 "place_order requires at least one order item"` (the function's own guard). The signature is `(p_order, p_items)`; posting `{"items":[]}` instead returns `404 PGRST202` and is **not** evidence the function is missing |
| `rpc/get_order_details` | installed — `200 null` for an unknown uuid/email |
| `rpc/publish_product` | installed, **not anon-executable** — `401 42501 permission denied for function` |
| `admins` table | `404 PGRST205` — `20261025` still **unapplied** |
| `products.intensity` | `42703` — `01_web_20261013` still **unapplied** |

The write path is still permissive (the accepted risk above stands) and the admin allowlist is still
missing, **but `place_order` is live and orders are being received on web and mobile (owner-confirmed
2026-10-25)**. §4's "not installed (404)" line is corrected below.

> ## ⚠️ ACCEPTED RISK — DEFERRED, ON RECORD
>
> **Decision (2026-10-25, owner):** the write-policy hole below is **knowingly
> accepted for now**, not overlooked. The project is in a pre-launch testing phase;
> closing it requires deciding an admin identity first, and that would block the
> pipeline work in flight.
>
> **Revisit before the catalogue is treated as production.** Concretely, before any
> of these:
>
> - the storefront URL is shared publicly / indexed / linked from anywhere
> - real money can be taken (real prices, real stock, live checkout)
> - the catalogue is worth more than the time it takes to rebuild it
>
> The last one is the actual test. Today the catalogue is regenerable from
> `products/` in one command, so a wipe costs an hour. Once products exist only in
> the database, a wipe is unrecoverable.
>
> **Note (corrected 2026-10-25):** `place_order()` **is** installed — the empty-items
> probe returns `22023` from the function's own guard — so checkout does complete and
> orders land. The accepted risk below therefore covers the *catalogue write path*
> only, not checkout. See §0 and §4.

The catalogue was loaded through the storefront's **publishable** key, using the
plain table endpoints. That worked because the write policies are still the
permissive ones from `schema.sql` (`using (true)` / `with check (true)`). This
document records what that means, and what to run to close it.

---

## 0b. Blocking findings before customer sign-up (measured 2026-10-29)

Applying `20261025` is **not sufficient** to close the write path. Two defects in
the deployed chain were found on a PG16 replica built from `schema.sql` + the
entire migration chain + `production-seed.sql`:

**Finding 1 — the old permissive policy survives.** `20260104` created
`"Authenticated admin write <t>"` on each catalogue table as
`for all to authenticated using (true) with check (true)`. `20261025` adds
`"Admins write <t>"` (`is_admin()`) but its loop only drops the latter name.
Both policies then exist, and **Postgres ORs permissive policies**, so
`using (true)` wins: an authenticated non-admin still has full write.
Measured: `set role authenticated` + a non-admin `sub` inserted into `garments`
with `20261025` applied. `20261031` §5b drops the legacy policies; that is the
step that actually closes the hole.

**Finding 2 — storage is ungated.** `20260104` gated `product-images` uploads on
`to authenticated`, which was safe only while "authenticated" meant "the owner".
`20261025` does not touch `storage.objects` (0 references). Enabling customer
sign-up without §5 of `20261031` gives every customer write/delete on catalogue
photography. Re-gated on `is_admin()`, split into insert/update/delete, public
read preserved.

**Finding 3 — direct order inserts were still open.** `schema.sql` retains
`Allow public create orders` / `create order items` (anon INSERT `true`). With
per-user order history readable, a direct `POST /rest/v1/orders` carrying a
victim's `user_id` plants fake rows in their history. Revoked by `20261031` §5c.
`place_order` is `SECURITY DEFINER`, so RPC writes are unaffected.

---

## 1. What is actually applied on the hosted project

| Migration | Applied? | Evidence |
|---|---|---|
| `schema.sql` | yes | 13 tables, 29 products readable |
| `20261024_data_model_trust_fields.sql` | **yes** | `attributes` column returns 200; `attribute_definitions` seeded (14 rows); the attribute trigger fires — inserting a sweater with `{}` attributes is refused with *"missing required attribute(s) … occasion, fabric_composition"* |
| `20261026_catalogue_garment_types.sql` | **yes** | `sweater`, `blouse`, `kurta`, `jeans` all resolve in `garments` |
| `20261025_admin_write_policies.sql` | **NO** | `public.admins` → HTTP 404 (table does not exist); `public.is_admin()` → *function not found* |
| `20261026_publish_product.sql` | **NO** | `rpc/publish_product` → exists, `401 42501` for anon (not applied as a policy); `rpc/place_order` → **installed** (`22023` guard) |

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

- **`products` has no `status` column and `is_mock` is retired by decision (2026-10-25).** Every row is live the instant
  it is inserted, and `getProducts()` serves all of them. There is no draft state,
  so a half-reviewed product cannot be staged. The measured catalogue is **29
  products** (with 197 variants, 278 images, 29 embroidery rows — read-only count,
  2026-10-25) and every one is **already served by the storefront** — worth knowing
  before you share the URL.
- **Storage bucket is live — the earlier "no bucket" finding is resolved (re-verified
  2026-10-25).** `20261027_product_images_bucket.sql` recreated `product-images` and
  `migrations` moved image src to absolute CDN URLs. Measured: a public object returns
  `200 image/jpeg`, and **276 of 278** `product_images.src` values are absolute
  `https://…/storage/v1/object/public/product-images/...` URLs. The 2 relative rows are
  leftovers and should be rewritten.
  (`GET /storage/v1/bucket` still returns `[]` for the publishable key — that listing
  endpoint is admin-only, so it is **not** evidence the bucket is missing. Probe an
  object URL instead.)
  Mobile therefore *does* render product photography now: `ProductImage.isRemote`
  gates on an `http(s)` prefix, which the absolute URLs satisfy.
- **`place_order()` is installed** (re-verified 2026-10-25). Checkout works on web and
  mobile and orders are landing in `orders` (owner-confirmed). What is *not* installed is
  the admin allowlist (`admins` → 404), so the catalogue write path stays open — see §0.

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
