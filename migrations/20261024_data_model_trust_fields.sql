-- ============================================================================
-- 20261024_data_model_trust_fields.sql
--
-- Reconciles the product contract with docs/11-data-model/00-product-data-audit.md:
-- subtracts four fabricated/duplicated fields and adds the trust fields a
-- Rs 699-3,999 India-first storefront requires.
--
-- DESTRUCTIVE AND NON-IDEMPOTENT. Read docs/11 before running.
--
-- Sequencing (docs/11/README.md "Order of work"):
--   Step 1 (this file, part A) - remove fabrications
--   Step 2 (part B)            - split craft provenance from manufacturing origin
--   Step 4 (part C)            - add trust + logistics fields
--   Step 5 (later, separate)   - reprice to the ladder; must NOT precede this
--
-- Part D adds a suppliers table so craft_cluster can become a real FK once the
-- named collectives are confirmed as actual suppliers. Until then the column is
-- dropped, because an unverifiable supplier name on a product page is a
-- sourcing claim nobody measured.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- PART A - remove fabricated and duplicated product fields
-- ---------------------------------------------------------------------------

-- Fabricated provenance. Both were free text with prose defaults in the Admin
-- create form (Admin.tsx:334-337), so every product inherited one supplier
-- name and one region unless an operator overrode them.
--
-- craft_region additionally cannot serve as country-of-origin because it
-- describes a craft tradition, not where a garment was made, and it mixes
-- granularities (a state beside "Kutch & Okayama Collaboration").
alter table public.products
  drop column if exists craft_cluster,
  drop column if exists craft_region;

-- Limited-edition claim present on 2 of 13 products. Either every SKU carries a
-- real batch run or the claim does not belong on the row.
alter table public.products
  drop column if exists batch_number,
  drop column if exists batch_total;

-- exact rename of expression_score: measured 1:1 across all 13 products
-- (1=minimal 2=understated 3=cult 4=expressive 5=maximalist). Display labels
-- live in src/data/expression.json, which is where copy belongs.
alter table public.products
  drop column if exists expression_slug;

-- array exists for a multi-character capability nothing uses:
-- character_ids === [motif_id] on 8 of 8 products that have both.
alter table public.products
  drop column if exists character_ids;

-- sold_count is a hand-typed display string ("1.2K+") typed as text, so it can
-- never be summed, sorted or validated. SOCIAL PROOF MUST BE REAL OR ABSENT:
-- this is dropped rather than defaulted. When real, reintroduce as
-- `sold_count integer` maintained from the orders table, never hand-authored.
alter table public.products
  drop column if exists sold_count;

-- rating / review_count stay, but only as caches maintained from the reviews
-- table. They must never be authored by hand; see the guard at the end of
-- part C.

-- ---------------------------------------------------------------------------
-- PART B - manufacturing origin, separated from craft provenance
-- ---------------------------------------------------------------------------

-- Legally required for e-commerce in India and impossible to express with
-- craft_region. Defaults to IN because every SKU is made domestically today;
-- the column exists so that stops being an assumption.
alter table public.products
  add column if not exists country_of_origin char(2) not null default 'IN';

alter table public.products
  drop constraint if exists products_country_of_origin_iso;
alter table public.products
  add constraint products_country_of_origin_iso
  check (country_of_origin ~ '^[A-Z]{2}$');

comment on column public.products.country_of_origin is
  'ISO 3166-1 alpha-2 country of manufacture. Distinct from craft tradition, which is motif/universe metadata.';

-- Legal Metrology declarations: who made it and who packed it.
alter table public.products
  add column if not exists manufacturer_name text,
  add column if not exists manufacturer_address text,
  add column if not exists packed_by text;

-- ---------------------------------------------------------------------------
-- PART C - trust and logistics fields (the actual product work)
-- ---------------------------------------------------------------------------

-- COD is the #1 first-order blocker in tier-2/3. Boolean with no default on
-- purpose: a new product must state this explicitly rather than inherit a
-- policy that may be wrong for its price point or category.
alter table public.products
  add column if not exists cod_available boolean not null default false;

-- A promised range, not a vague "5-7 days". min/max so the PDP can state a
-- window and the checkout can state a date.
alter table public.products
  add column if not exists delivery_days_min smallint,
  add column if not exists delivery_days_max smallint;

alter table public.products
  drop constraint if exists products_delivery_window_valid;
alter table public.products
  add constraint products_delivery_window_valid
  check (
    (delivery_days_min is null and delivery_days_max is null)
    or (delivery_days_min >= 0 and delivery_days_max >= delivery_days_min)
  );

-- Return window drives completion for a first-time buyer. 0 means
-- non-returnable, which is the honest value for personalised pieces.
alter table public.products
  add column if not exists return_window_days smallint not null default 0;

alter table public.products
  drop constraint if exists products_return_window_valid;
alter table public.products
  add constraint products_return_window_valid
  check (return_window_days >= 0);

-- Shipping cost and courier selection.
alter table public.products
  add column if not exists weight_grams integer;

alter table public.products
  drop constraint if exists products_weight_positive;
alter table public.products
  add constraint products_weight_positive
  check (weight_grams is null or weight_grams > 0);

-- GST invoicing.
alter table public.products
  add column if not exists hsn_code text;

alter table public.products
  drop constraint if exists products_hsn_format;
alter table public.products
  add constraint products_hsn_format
  check (hsn_code is null or hsn_code ~ '^[0-9]{4,8}$');

-- Size uncertainty is the top apparel return cause. JSON so a chart can vary by
-- garment type without a migration per silhouette.
alter table public.products
  add column if not exists size_chart jsonb;

-- `care` already exists in this schema and on the Product interface
-- (data.ts:273) and is mapped from the DB (data.ts:525) — but the JSON seed
-- omits it, so it renders empty on every product. Schema is fine; the seed needs
-- filling. Nullable, no change required here.

-- ---------------------------------------------------------------------------
-- PART D - suppliers, so craft_cluster can be a real FK later
-- ---------------------------------------------------------------------------

create table if not exists public.suppliers (
  id                uuid primary key default gen_random_uuid(),
  slug              text unique not null,
  name              text not null,
  -- where the work is physically done; distinct from craft tradition
  city              text,
  state             text,
  country_code      char(2) not null default 'IN',
  gstin             text,
  contact_email     text,
  contact_phone     text,
  -- whether anyone has actually visited/verified, not whether the name sounds real
  verified_at       timestamptz,
  notes             text,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),

  constraint suppliers_country_iso check (country_code ~ '^[A-Z]{2}$'),
  constraint suppliers_gstin_format
    check (gstin is null or gstin ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]{3}$')
);

comment on table public.suppliers is
  'Real manufacturing partners. A product references a supplier only when verified_at is set; craft tradition is separate (motifs/universe).';

create index if not exists suppliers_active_idx on public.suppliers (is_active)
  where is_active;

-- Join table rather than a column, because one SKU can involve more than one
-- workshop (embroidery vs stitching).
create table if not exists public.product_suppliers (
  product_slug  text not null references public.products(slug) on delete cascade,
  supplier_id   uuid not null references public.suppliers(id) on delete restrict,
  role          text not null default 'manufacturer',
  created_at    timestamptz not null default now(),
  primary key (product_slug, supplier_id, role),
  constraint product_suppliers_role_valid
    check (role in ('manufacturer', 'embroiderer', 'packer', 'dyer'))
);

alter table public.suppliers enable row level security;
alter table public.product_suppliers enable row level security;

-- Public storefront may read active suppliers' display fields; nobody writes
-- through the anon key.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'suppliers'
      and policyname = 'suppliers_public_read'
  ) then
    create policy suppliers_public_read on public.suppliers
      for select using (is_active);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'product_suppliers'
      and policyname = 'product_suppliers_public_read'
  ) then
    create policy product_suppliers_public_read on public.product_suppliers
      for select using (true);
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- PART E - cache guard: rating/review_count are derived, never authored
-- ---------------------------------------------------------------------------

-- The audit found rating and review_count hand-present on rows. Denormalised
-- caches are fine; hand-authored social proof is not. This trigger refuses a
-- manual change unless a flag is set, so the only writer is the review
-- aggregation job.
create or replace function public.products_guard_rating_cache()
returns trigger
language plpgsql
as $$
begin
  -- rows inserted by the aggregation job set this for the transaction
  if current_setting('app.rating_cache_update', true) = 'on' then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if new.rating is distinct from old.rating
       or new.review_count is distinct from old.review_count then
      raise exception
        'rating/review_count are derived from public.reviews; set app.rating_cache_update=on to refresh from the aggregation job'
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists products_guard_rating_cache on public.products;
create trigger products_guard_rating_cache
  before insert or update on public.products
  for each row execute function public.products_guard_rating_cache();

commit;
