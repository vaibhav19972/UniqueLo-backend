# Product images: where they live, and why not in git

**Decision (2026-10-25): Supabase Storage, with an absolute public URL in
`product_images.src`. Images are never committed to the repo.**

The migration path to a real CDN (Cloudflare R2) is open, because clients read an
absolute URL out of the database — moving hosts is a data update, not a code change.

---

## 1. Why "commit them to git" does not work

It is not a matter of preference or bundle size. It is disqualified by the mobile
client's image gate.

```kotlin
// mobile/.../model/Product.kt
val isRemote: Boolean
    get() = src.startsWith("http://") || src.startsWith("https://")

val remoteImages: List<ProductImage>
    get() = images.filter { it.isRemote }.sortedBy { it.sortOrder }
```

`Mappers.kt` passes `src` through unmodified. A repo-relative path
(`/images/products/white-tee-1.jpg`) therefore fails `isRemote`, is filtered out of
`remoteImages`, and `ProductArtwork`'s drawn placeholder is shown. Not a broken
image icon, not an error — a product that quietly looks illustrated. Confirmed by
reading the call path, not assumed.

This is the general trap: **a relative path is a web-only convention.** The browser
resolves it; every other client skips it.

---

## 2. The three image namespaces, and which is allowed to be truth

| Path | What it is | In git? |
|---|---|---|
| `products/<slug>/01-angles/*.png` | full-res board crop — the **master** | yes |
| `web/public/images/products/<slug>-N.jpg` | 420px q82 render, local mirror | **no** — generated |
| `https://<project>/storage/v1/object/public/product-images/products/<slug>-N.jpg` | what clients actually load | n/a (object storage) |

`web/public/images/products/` is output, like `dist/`. `export_images.py`
regenerates it from the masters in one command, so versioning 13 MB of derivative
JPEG that can drift from its source buys nothing.

`web/.gitignore` ignores that directory **specifically**:

```gitignore
/public/images/products
```

Not the blanket `/public` that was there before. That one line silently excluded
`public/fonts/` and `public/images/categories/`, `campaigns/`, `placeholders/` —
assets the storefront genuinely serves from the bundle and cannot fetch from
anywhere else. Net effect of the blanket line: 289 of 310 product JPEGs *and* the
fonts would never have deployed.

---

## 3. What the pipeline does now

```
products/<slug>/01-angles/00-front.png          master (tracked)
        │
        │  export_images.py   (render, resize to 420px q82)
        ▼
web/public/images/products/<slug>-1.jpg         local mirror (ignored)
        │
        │  export_images.py   (upload to bucket, x-upsert)
        ▼
https://…/product-images/products/<slug>-1.jpg  public URL
        │
        │  author.py          (baked into product.yaml — the source of truth)
        ▼
product_images.src                              absolute URL, read by both clients
```

Order matters — each stage consumes the previous one's output:

```bash
python3 _pipeline/scripts/export_images.py <slug>    # render AND upload, returns URLs
python3 _pipeline/scripts/author.py  <slug>          # write absolute src into product.yaml
python3 _pipeline/scripts/publish.py <slug> --dry-run
python3 _pipeline/scripts/upload.py  <slug>          # rows into Postgres
```

`export_images.py` also writes `_pipeline/build/image-urls.json` (slug → URL list),
which is a build artifact — useful for diffing before and after a re-crop.

**Object naming is `products/<slug>-N.jpg` inside the bucket**, matching the Admin
Studio's own upload path (`storage.from('product-images').upload('products/…')`), so
panel uploads and pipeline uploads share one namespace and a re-upload overwrites
rather than duplicating.

---

## 4. What is blocking, and the fix

The bucket **does not exist**. It was deleted by hand during a cleanup, and nothing
recreates it — `schema.sql`'s `insert … on conflict (id) do nothing` is a no-op once
the row is gone. Measured state:

```
GET  /storage/v1/bucket                           -> []       no bucket
GET  /storage/v1/object/public/product-images/…    -> 400      public URL dead
POST /storage/v1/object/product-images/…           -> 403      upload refused
```

That also means the Admin Studio's upload button has been broken since the deletion,
not just the live site.

**Run `backend/migrations/20261027_product_images_bucket.sql` once** in the Supabase
SQL editor. It creates the bucket, sets `public = true`, and restores the public-read
policy. Idempotent.

Then, with an upload-capable key exported (service-role or secret — **never** in a
client bundle):

```bash
export SUPABASE_SERVICE_ROLE_KEY=...
cd products && python3 _pipeline/scripts/export_images.py --all
```

That uploads 310 JPEGs / ~12.5 MB and rewrites `image-urls.json`. Then re-author and
re-upload the rows so `product_images.src` points at the CDN:

```bash
python3 _pipeline/scripts/author.py && python3 _pipeline/scripts/upload.py --all
```

Verify before trusting it — one object, fetched anonymously:

```bash
curl -s -o /dev/null -w '%{http_code} %{content_type} %{size_download}\n' \
  "https://<project>.supabase.co/storage/v1/object/public/product-images/products/white-tee-1.jpg"
# expect: 200 image/jpeg ~40000
```

---

## 5. Cost, for deciding when to move to R2

310 files, 12.53 MB, avg 41 KB per image. A PDP loads ~12 images ≈ 0.5 MB.

| | Supabase Storage | Cloudflare R2 |
|---|---|---|
| Egress | 5 GB/mo free, then ~$0.09/GB | **free** |
| Capacity | 1 GB free | 10 GB free |
| Rough page views/mo on free tier | ~10,000 | unlimited-ish |
| Auth/policies | already written | needs its own |
| Change to move | — | rewrite `src` values (`UPDATE product_images SET src = replace(...)`) |

The 420px cap is what makes this comfortable: at full board resolution the same
catalogue is ~226 MB and the free egress would last days. **Keep the resize.**

Move to R2 when bandwidth becomes the binding constraint, or when you want
image-optimisation at the edge. Because `src` is an absolute URL in the database,
that migration touches data and one upload script — not the web app or the mobile
app.

---

## 6. Rules that keep this from regressing

- **`src` is absolute `http(s)`.** `publish.py` now rejects a web-relative `src`
  with the reason (mobile drops it) and the fix (run `export_images.py`). Proved by
  rejection, not assumed.
- **Never ignore `/public` wholesale.** Ignore the generated subdirectory.
- **The bucket is infrastructure, not bootstrap.** It is created by a numbered
  migration so deleting it is recoverable. Do not rely on `schema.sql` for anything
  that must exist after a manual change.
- **No public insert policy on the bucket.** `schema.sql` ships one with no role,
  i.e. anonymous upload to your quota. Writes go through a service-role key
  (pipeline, server-side) or an authenticated admin (panel, `20260104` policies).
