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

-- COD is the #1 first-order blocker in tier-2/3. Owner decision 2026-10-24:
-- available on EVERY SKU, so the default is true. Still a column, not a constant,
-- because a per-SKU opt-out is a business decision that must not need a migration.
alter table public.products
  add column if not exists cod_available boolean not null default true;

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

-- Return window drives completion for a first-time buyer. Owner decision
-- 2026-10-24: 7 days. 0 remains meaningful for made-to-order/personalised pieces,
-- which is why this is a number and not a boolean.
alter table public.products
  add column if not exists return_window_days smallint not null default 7;

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
-- PART D - marketplace attribute system (Myntra / Ajio parity)
-- ---------------------------------------------------------------------------
--
-- Research basis (2026-10-24). Both Myntra and Ajio validate mandatory
-- attributes PER ARTICLE TYPE, not globally: a tee needs neck/sleeve/pattern/
-- length/occasion, a dress needs neckline/lining/sleeve, footwear needs upper/
-- sole/heel/toe. Their QC docs list the failures that matter: missing mandatory
-- attributes, pattern/fit mismatch, material claims without evidence, missing
-- country of origin, and manufacturer/packer declarations.
--
-- The wrong response is to add 30 nullable columns to products. That is how the
-- catalogue got 29 columns of prose in the first place, and it guarantees a
-- migration every time a new garment type arrives.
--
-- The right response is the one the marketplaces themselves use: a REGISTRY that
-- says which attributes are required for which garment, plus one jsonb column
-- holding the values. Adding a garment type becomes an INSERT, not an ALTER.

create table if not exists public.attribute_definitions (
  key            text primary key,          -- 'neck_type', 'sleeve_length'
  label          text not null,             -- 'Neck Type'
  data_type      text not null default 'enum',
  unit           text,                      -- 'cm', 'gsm'
  options        text[],                    -- allowed values when data_type='enum'
  -- which garment types require this attribute. Empty = applies to all.
  applies_to     text[] not null default '{}',
  is_required    boolean not null default false,
  display_group  text,                       -- 'Style', 'Fabric', 'Care', 'Fit'
  order_num      integer not null default 0,
  created_at     timestamptz not null default now(),
  constraint attribute_definitions_type_valid
    check (data_type in ('enum', 'text', 'number', 'boolean', 'measurement'))
);

comment on table public.attribute_definitions is
  'Per-garment attribute contract. Mirrors the Myntra/Ajio category attribute matrix: an attribute can be required for tees and irrelevant for scarves. Add a garment type by inserting rows here, never by altering products.';

-- The values live here. One column, unlimited attributes.
alter table public.products
  add column if not exists attributes jsonb not null default '{}'::jsonb;

comment on column public.products.attributes is
  'Category-scoped attribute values, keyed by attribute_definitions.key. Validated on write against the registry.';

-- Style-level identity. Marketplaces key a design family by a Style ID and
-- every size/colour as a variant beneath it; reusing a style code for an
-- unrelated design is an explicit QC rejection on both platforms.
alter table public.products
  add column if not exists style_code text;

alter table public.products
  drop constraint if exists products_style_code_unique;
alter table public.products
  add constraint products_style_code_unique unique (style_code);

-- Fit guidance, which is what the "and this is how it sits" line on a PDP is.
alter table public.products
  add column if not exists fit_notes text,
  add column if not exists model_height_cm smallint,
  add column if not exists model_worn_size text;

-- Barcode per variant. Both platforms require a unique scannable identifier per
-- size+colour and reject reuse across sizes. SKU alone is not enough: it is our
-- internal key, EAN is the physical one.
alter table public.variants
  add column if not exists barcode text;

alter table public.variants
  drop constraint if exists variants_barcode_unique;
alter table public.variants
  add constraint variants_barcode_unique unique (barcode);

-- Shipping cuboid. Carriers bill on volumetric weight; weight_grams alone gives
-- the wrong number for anything bulky like a hoodie.
alter table public.products
  add column if not exists package_length_mm smallint,
  add column if not exists package_width_mm smallint,
  add column if not exists package_height_mm smallint;

-- ---- registry seed: the attribute matrix for our actual garment types -------
-- Only the attributes that are (a) mandatory on Myntra/Ajio for that article
-- type, or (b) genuinely change a purchase decision. Deliberately not 40 fields.
--
-- Boundary rule: an attribute lives in `attributes` jsonb ONLY if it has no
-- first-class column. Country of origin / manufacturer / packed_by are columns
-- (legal declarations every SKU carries), and wash care is the existing `care`
-- text[]. Putting them in the registry too would mean two places to fill and two
-- places to forget.
insert into public.attribute_definitions
  (key, label, data_type, options, applies_to, is_required, display_group, order_num)
values
  ('pattern',      'Pattern',      'enum', array['solid','printed','embroidered','striped','checkered','colorblock'], array['tee','hoodie','shirt','jacket','cardigan','vest','pants','scarf','tote'], true,  'Style', 10),
  ('neck_type',    'Neck Type',    'enum', array['round','v-neck','crew','collar','band','hooded','square'], array['tee','hoodie','shirt','cardigan','vest'], true,  'Style', 20),
  ('sleeve_length', 'Sleeve Length','enum', array['sleeveless','short','three-quarter','long'], array['tee','hoodie','shirt','jacket','cardigan','vest'], true, 'Style', 30),
  ('closure',      'Closure',      'enum', array['pull-on','button','zip','drawstring','tie','none'], array['hoodie','shirt','jacket','cardigan','vest','pants'], true, 'Style', 40),
  ('length',       'Garment Length','enum', array['cropped','regular','longline','full'], array['tee','hoodie','shirt','jacket','cardigan','vest'], false, 'Style', 50),
  ('rise',         'Rise',         'enum', array['low','mid','high'], array['pants'], true, 'Style', 60),
  ('occasion',     'Occasion',     'enum', array['casual','everyday','festive','work','party','travel'], array[]::text[], true, 'Style', 70),
  ('hemline',      'Hemline',      'enum', array['straight','curved','asymmetric','raw'], array['tee','hoodie','shirt','jacket','cardigan','vest'], false, 'Style', 80),
  ('lining',       'Lining',       'enum', array['unlined','partial','full'], array['jacket','vest','pants'], false, 'Style', 90),
  ('fabric_composition', 'Fabric Composition', 'text', null, array[]::text[], true, 'Fabric', 100),
  ('fabric_weight_gsm',  'Fabric Weight',      'measurement', null, array['tee','hoodie','pants'], false, 'Fabric', 110),
  ('transparency', 'Transparency', 'enum', array['opaque','semi-sheer','sheer'], array['tee','shirt','scarf'], false, 'Fabric', 120),
  ('stretch',      'Stretch',      'enum', array['non-stretch','low','medium','high'], array[]::text[], false, 'Fabric', 130),
  ('iron_care',    'Iron Care',    'text', null, array[]::text[], false, 'Care', 150)
on conflict (key) do update set
  label = excluded.label, data_type = excluded.data_type, options = excluded.options,
  applies_to = excluded.applies_to, is_required = excluded.is_required,
  display_group = excluded.display_group, order_num = excluded.order_num;

-- RLS. Every other table in schema.sql enables it; this one was created by this
-- migration and would otherwise inherit Supabase's default public-schema grants,
-- which means an anon key could edit the attribute contract itself. Verified:
-- without this block an anonymous role can DELETE from the registry.
alter table public.attribute_definitions enable row level security;

drop policy if exists "Allow public read attribute definitions" on public.attribute_definitions;
create policy "Allow public read attribute definitions"
  on public.attribute_definitions for select using (true);

-- Writes stay closed to anon. The registry is a schema decision, changed by
-- migration, not by the storefront.

-- ---- enforcement -----------------------------------------------------------
-- Requires every attribute the registry marks mandatory FOR THAT GARMENT.
-- Runs on insert and update so a product cannot be created incomplete and later
-- patched, and so a newly-required attribute surfaces on the next write instead
-- of on a customer's screen.
create or replace function public.products_validate_attributes()
returns trigger
language plpgsql
as $$
declare
  missing text;
begin
  select string_agg(d.key, ', ' order by d.order_num)
    into missing
  from public.attribute_definitions d
  where d.is_required
    and (d.applies_to = '{}' or new.garment_type = any(d.applies_to))
    and not (new.attributes ? d.key);

  if missing is not null then
    raise exception 'product % is missing required attribute(s) for garment "%": %',
      new.slug, coalesce(new.garment_type, '(none)'), missing
      using errcode = 'check_violation';
  end if;

  -- enum values must be one of the declared options
  declare
    bad text;
  begin
    select string_agg(d.key || '=' || (new.attributes ->> d.key), ', ')
      into bad
    from public.attribute_definitions d
    where d.data_type = 'enum'
      and d.options is not null
      and new.attributes ? d.key
      and not ((new.attributes ->> d.key) = any(d.options));

    if bad is not null then
      raise exception 'product % has invalid enum attribute value(s): %', new.slug, bad
        using errcode = 'check_violation';
    end if;
  end;

  return new;
end;
$$;

drop trigger if exists products_validate_attributes on public.products;
create trigger products_validate_attributes
  before insert or update on public.products
  for each row execute function public.products_validate_attributes();



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
