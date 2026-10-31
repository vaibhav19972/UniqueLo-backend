-- ====================================================================
-- UniqueLo — Supabase schema (bootstrap DDL)
--
-- SCOPE: this file owns TABLES, COLUMNS, INDEXES and the BASELINE RLS posture
-- (enable row level security + the original permissive read policies). It does
-- NOT own the FINAL policies, functions or triggers — the migration chain does,
-- because their correct form depends on objects a migration creates first (the
-- storage write policy needs is_admin(); the order RPCs are plpgsql).
--
-- CAUTION: running this file alone leaves writes PERMISSIVE by design — the
-- baseline mirrors the original pre-lockdown state so a fresh project boots.
-- The lockdown arrives with migrations 20261025 + 20261031. Do not point a
-- public deployment at a schema.sql-only database.
--
-- TARGET PLATFORM: Supabase. Five tables below carry `references auth.users(id)`
-- (admins, orders.user_id, customer_addresses, customer_wishlists,
-- coupon_redemptions),
-- because that is where Supabase keeps identities. On **plain Postgres** that
-- schema does not exist, so for a local build apply the stub first:
--
--   backend/scripts/local-bootstrap.sql   <- plain Postgres only
--   backend/schema.sql                    <- this file
--   backend/migrations/                   <- ordered
--   backend/production-seed.sql
--
-- On Supabase, skip the stub: auth.users and storage.* already exist.
--
-- Documented load order: schema.sql -> migrations/ (ordered) -> production-seed.sql
-- Dev seed.sql is legacy/local-only and is NOT a production path.
--
-- This baseline was 7 tables and 1 column behind the migration chain until
-- 2026-10-31; scripts/check-schema-completeness.mjs now fails the build if that
-- ever happens again. Do not add a table to migrations/ without adding it here.
-- ====================================================================


-- 1. Enable UUID Extension
create extension if not exists "uuid-ossp";

-- 2. Clean Drop (Optional / For Fresh Re-initialization)
-- To completely wipe and rebuild, run the following DROP block:
/*
drop table if exists public.order_items cascade;
drop table if exists public.orders cascade;
drop table if exists public.reviews cascade;
drop table if exists public.newsletter_subscribers cascade;
drop table if exists public.embroidery_details cascade;
drop table if exists public.product_images cascade;
drop table if exists public.variants cascade;
drop table if exists public.products cascade;
drop table if exists public.garments cascade;
drop table if exists public.collections cascade;
drop table if exists public.motifs cascade;
drop table if exists public.universes cascade;
drop table if exists public.categories cascade;
*/

-- 3. Universes Table (Animeverse, Heroverse, Itihaas)
create table if not exists public.universes (
  slug text primary key,
  name text not null,
  tagline text not null,
  lore text not null,
  emblem_src text,
  hero_image text,
  drop_cadence text,
  is_active boolean default true,
  order_num integer default 0,
  theme_tokens jsonb default '{}'::jsonb,
  portal_title_color text,
  lore_heading text,
  hero_headline text,
  hero_headline_accent text,
  hero_lead_color text,
  hero_accent_color text,
  hero_headline_case text,
  hero_kicker text,
  hero_ornament text,
  hero_note text,
  hero_vertical_text text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 4. IP-Cleared Motifs Table
create table if not exists public.motifs (
  id text primary key,
  universe_slug text references public.universes(slug) on delete cascade not null,
  name text not null,
  meaning text not null,
  symbol_notes text,
  ip_cleared boolean default true,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 5. Categories Table
create table if not exists public.categories (
  slug text primary key,
  name text not null,
  label text not null,
  description text not null,
  image text,
  order_num integer default 0,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 5b. Garments Table (Silhouette Taxonomy: Hoodies, Tees, Jackets, etc.)
create table if not exists public.garments (
  slug text primary key,
  name text not null,
  category_slug text references public.categories(slug) on delete set null,
  description text not null,
  order_num integer default 0,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 5c. Collections Table (Seasonal Drops & Thematic Capsules)
create table if not exists public.collections (
  slug text primary key,
  name text not null,
  tagline text,
  description text,
  universe_slug text references public.universes(slug) on delete set null,
  cover_image text,
  featured boolean default true,
  order_num integer default 0,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 6. Products Table (Fully synchronized with current TypeScript domain model)
create table if not exists public.products (
  slug text primary key,
  name text not null,
  subtitle text not null,
  foreign_tagline text,
  description text not null,
  category_slug text references public.categories(slug) on delete set null,
  universe_slug text references public.universes(slug) on delete set null,
  collection_slug text references public.collections(slug) on delete set null,
  garment_type text references public.garments(slug) on delete set null,
  gender text default 'unisex' check (gender in ('men', 'women', 'unisex')),
  motif_id text references public.motifs(id) on delete set null,
  handcrafted boolean default false,
  craft_techniques text[] default '{}',
  edits text[] default '{}',
  expression_score smallint default 3 check (expression_score between 1 and 5),
  rating numeric(3,1) default 5.0,
  review_count integer default 0,
  tags text[] default '{}',
  featured boolean default false,
  customizable boolean default false,
  material text[] default '{}',
  care text[] default '{}',
  fit text,
  fabric_gsm text,
  -- trust + logistics (added by migrations/20261024, mirrored here so a fresh
  -- build from schema.sql matches the live catalogue shape)
  country_of_origin char(2) not null default 'IN' check (country_of_origin ~ '^[A-Z]{2}$'),
  manufacturer_name text,
  manufacturer_address text,
  packed_by text,
  cod_available boolean not null default true,
  delivery_days_min smallint,
  delivery_days_max smallint,
  return_window_days smallint not null default 7 check (return_window_days >= 0),
  weight_grams integer check (weight_grams is null or weight_grams > 0),
  hsn_code text check (hsn_code is null or hsn_code ~ '^[0-9]{4,8}$'),
  size_chart jsonb,
  -- marketplace parity (migrations/20261024)
  attributes jsonb not null default '{}'::jsonb,
  style_code text unique,
  fit_notes text,
  model_height_cm smallint,
  model_worn_size text,
  package_length_mm smallint,
  package_width_mm smallint,
  package_height_mm smallint,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  constraint products_delivery_window_valid check (
    (delivery_days_min is null and delivery_days_max is null)
    or (delivery_days_min >= 0 and delivery_days_max >= delivery_days_min)
  )
);

-- 7. Product Variants Table
create table if not exists public.variants (
  sku text primary key,
  product_slug text references public.products(slug) on delete cascade not null,
  color text not null,
  color_hex text not null,
  size text not null,
  price_cents integer not null,
  compare_at_price_cents integer,
  -- MRP expiry (migrations/20261101): a dated markdown stops being claimable
  -- once this passes. NULL = no expiry. Added to the baseline so a fresh build
  -- matches the hosted shape, same rationale as the trust columns above.
  compare_at_ends_at timestamp with time zone,
  status text default 'in-stock' check (status in ('in-stock', 'low-stock', 'out-of-stock')),
  quantity integer default 10,
  -- physical scannable identifier (migrations/20261024); unique when present
  barcode text unique,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  -- An MRP at or below the selling price is not a discount; an expiry with no
  -- MRP is meaningless. Enforced here so no admin paste or script can create a
  -- fabricated markdown claim.
  constraint variants_mrp_exceeds_price
    check (compare_at_price_cents is null or compare_at_price_cents > price_cents),
  constraint variants_mrp_ends_needs_mrp
    check (compare_at_ends_at is null or compare_at_price_cents is not null)
);

-- 8. Product Images Table
create table if not exists public.product_images (
  id uuid primary key default uuid_generate_v4(),
  product_slug text references public.products(slug) on delete cascade not null,
  src text not null,
  alt text not null,
  color text,
  sort_order integer default 0
);

-- 9. Embroidery Details Table
create table if not exists public.embroidery_details (
  id uuid primary key default uuid_generate_v4(),
  product_slug text references public.products(slug) on delete cascade not null unique,
  technique text not null,
  technique_label text not null,
  artisan_hours integer default 0,
  placement text[] default '{}',
  thread_composition text not null,
  motif_story text not null,
  macro_image_src text,
  macro_image_alt text
);

-- 10. Reviews Table
create table if not exists public.reviews (
  id uuid primary key default uuid_generate_v4(),
  product_slug text references public.products(slug) on delete cascade not null,
  author text not null,
  rating integer check (rating >= 1 and rating <= 5) not null,
  title text not null,
  comment text not null,
  verified boolean default true,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 11. Newsletter Subscribers Table
create table if not exists public.newsletter_subscribers (
  id uuid primary key default uuid_generate_v4(),
  email text unique not null,
  subscribed_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 12. Orders & Order Items Table
create table if not exists public.orders (
  id uuid primary key default uuid_generate_v4(),
  customer_name text not null,
  customer_email text not null,
  -- Order ownership (migrations/20261031). DERIVED SERVER-SIDE by place_order
  -- from auth.uid(); a user_id in the RPC payload is ignored. NULL for guest
  -- checkout, and guests are never visible to a signed-in user.
  user_id uuid references auth.users(id) on delete set null,
  status text not null default 'confirmed',
  -- Fulfilment (migrations/20261102). NULL until the order ships; written by
  -- admin fulfilment, never by a client.
  tracking_number text,
  carrier         text,
  subtotal_cents integer not null,
  discount_cents integer default 0,
  shipping_cents integer default 0,
  -- COD surcharge (migrations/20261101). Kept separate from shipping_cents so
  -- courier cost is never misstated and COD-vs-prepaid margin stays analyzable.
  cod_fee_cents integer not null default 0,
  total_cents integer not null,
  coupon_code text,
  gift_note text,
  shipping_address jsonb,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  -- CONTRACT.md §6 vocabulary, enforced (migrations/20261102). 'pending' is
  -- included for a prepaid reservation that has not been paid yet.
  constraint orders_status_valid
    check (status in ('pending', 'reserved', 'confirmed', 'confirmed-cod',
                      'processing', 'shipped', 'delivered', 'cancelled')),
  -- A tracking number without a carrier is unusable, and vice versa.
  constraint orders_tracking_pairs_with_carrier
    check ((tracking_number is null and carrier is null)
        or (tracking_number is not null and carrier is not null)),
  -- `shipped` means "with courier", so it must carry an AWB (migrations/20261103).
  -- `delivered` is exempt: a hand-delivered order completes without one.
  constraint orders_shipped_needs_tracking
    check (status <> 'shipped'
        or (tracking_number is not null and carrier is not null))
);

create table if not exists public.order_items (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid references public.orders(id) on delete cascade not null,
  product_slug text not null,
  variant_sku text not null,
  product_name text not null,
  color text not null,
  size text not null,
  quantity integer not null,
  price_cents integer not null,
  customization jsonb
);

-- ====================================================================
-- Promotion / account / admin tables
--
-- These were created by migrations between 20261024 and 20261101 and were
-- absent from this baseline, which meant a fresh build could not run
-- quote_order() at all. Ordering below is FK-safe: coupons before
-- coupon_redemptions (which FKs it), orders already exists above.
-- ====================================================================

-- 15. Attribute contract (per-garment attribute definitions)
-- Values themselves live in products.attributes jsonb.
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

-- 16. Admin allowlist — the gate for every catalogue/asset write
create table if not exists public.admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  email      text,
  note       text,
  created_at timestamptz not null default now()
);

-- 17. Coupons (the promotion engine)
create table if not exists public.coupons (
  code               text primary key,
  description        text,
  -- 'percent'       discount_value is percentage points (10 = 10%)
  -- 'fixed'         discount_value is paise
  -- 'free_shipping' discount_value is ignored; waives the shipping line
  discount_type      text not null check (discount_type in ('percent', 'fixed', 'free_shipping')),
  discount_value     integer not null default 0 check (discount_value >= 0),
  -- Ceiling for percentage coupons. NULL = uncapped (dangerous; prefer a cap).
  max_discount_cents integer check (max_discount_cents is null or max_discount_cents > 0),
  min_subtotal_cents integer not null default 0 check (min_subtotal_cents >= 0),
  starts_at          timestamptz not null default now(),
  expires_at         timestamptz,
  total_usage_limit  integer check (total_usage_limit is null or total_usage_limit > 0),
  per_user_limit     integer not null default 1 check (per_user_limit > 0),
  first_order_only   boolean not null default false,
  -- Only one coupon applies per order today. The column exists so stacking can
  -- be switched on later without a schema change; false means "cannot combine".
  stackable          boolean not null default false,
  -- Whether this code may be ADVERTISED to a customer who has not typed it.
  -- Staff/VIP/compensation codes set this false: they stay redeemable if you
  -- know the code, but the best_coupon prompt will never reveal them.
  is_public          boolean not null default true,
  is_active          boolean not null default true,
  created_at         timestamptz not null default now(),
  constraint coupons_window_valid check (expires_at is null or expires_at > starts_at),
  constraint coupons_percent_sane check (discount_type <> 'percent' or discount_value between 1 and 100)
);

-- 18. Shipping rules (data-driven carriage)
create table if not exists public.shipping_rules (
  id               uuid primary key default gen_random_uuid(),
  name             text not null,
  flat_rate_cents  integer not null default 0 check (flat_rate_cents >= 0),
  -- NULL = always free. Otherwise: free when PRE-DISCOUNT subtotal reaches this.
  free_above_cents integer check (free_above_cents is null or free_above_cents >= 0),
  cod_fee_cents    integer not null default 0 check (cod_fee_cents >= 0),
  -- Unit count, not rupees. NULL = no cap.
  cod_max_units    integer check (cod_max_units is null or cod_max_units > 0),
  cod_enabled      boolean not null default true,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now()
);

-- 19. Saved delivery addresses (migrations/20261031)
create table if not exists public.customer_addresses (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  label          text,
  is_default     boolean not null default false,
  recipient_name text not null,
  phone          text not null,
  address_line   text not null,
  landmark       text,
  city           text not null,
  state          text not null,
  pincode        text not null check (pincode ~ '^[0-9]{6}$'),
  created_at     timestamptz not null default now()
);

-- 20. Cloud saved pieces. NO FK to products — a delisted product must not
-- erase a customer's saved piece (D-18).
create table if not exists public.customer_wishlists (
  user_id      uuid not null references auth.users(id) on delete cascade,
  product_slug text not null,
  created_at   timestamptz not null default now(),
  primary key (user_id, product_slug)
);

-- 21. Redemption ledger (coupon usage accounting)
create table if not exists public.coupon_redemptions (
  id                     uuid primary key default gen_random_uuid(),
  coupon_code            text not null references public.coupons(code) on delete restrict,
  order_id               uuid not null references public.orders(id) on delete cascade,
  -- Set when a signed-in customer placed the order. NULL for guest orders,
  -- which is why email is the fallback identity below.
  user_id                uuid references auth.users(id) on delete set null,
  customer_email         text not null,
  discount_applied_cents integer not null check (discount_applied_cents >= 0),
  created_at             timestamptz not null default now()
);

-- 22. Payment intents (migrations/20261104) — the gateway ledger.
--
-- Deliberately NOT columns on `orders`. 20261103 revoked client writes there and
-- granted back only a three-column admin UPDATE, so a payment_status column would
-- be writable only by a SECURITY DEFINER function. More importantly, a captured
-- payment whose order failed to place must OUTLIVE the order — it is the refund
-- queue — and a column on `orders` has nowhere to live when the order never
-- exists. `client_order_id` is the client-generated uuid place_order writes as
-- orders.id, so reconciliation is an equality, not a lookup table.
--
-- RLS on with NO policies: service role only, same posture as coupon_redemptions.
create table if not exists public.payment_intents (
  id uuid primary key default gen_random_uuid(),
  -- 'razorpay' today; free text so the next gateway is a row, not a migration.
  provider text not null default 'razorpay',
  client_order_id uuid not null,
  placed_order_id uuid,
  provider_order_id text unique,
  provider_payment_id text unique,
  -- Paise. Identical to the repo's *_cents convention and to Razorpay's unit.
  amount_cents integer not null check (amount_cents >= 100),
  currency text not null default 'INR',
  status text not null default 'created'
    check (status in ('created', 'authorized', 'captured', 'failed', 'expired')),
  customer_email text not null,
  customer_name text,
  customer_phone text,
  shipping_address jsonb,
  coupon_code text,
  -- The priced cart as created. place_order is called with THIS, never with a
  -- cart the browser re-submits after the charge.
  items jsonb not null,
  failure_reason text,
  created_at timestamptz not null default now(),
  captured_at timestamptz
);

-- ====================================================================
-- Indexes for High Performance
-- ====================================================================
create index if not exists idx_products_category on public.products(category_slug);
create index if not exists idx_products_universe on public.products(universe_slug);
create index if not exists idx_products_collection on public.products(collection_slug);
create index if not exists idx_products_garment on public.products(garment_type);
create index if not exists idx_products_gender on public.products(gender);
create index if not exists idx_products_featured on public.products(featured);
create index if not exists idx_variants_product on public.variants(product_slug);
create index if not exists idx_product_images_product on public.product_images(product_slug);
create index if not exists idx_reviews_product on public.reviews(product_slug);
-- orders.user_id (migrations/20261031). Partial: guest orders are NULL.
create index if not exists idx_orders_user_id on public.orders(user_id)
  where user_id is not null;
-- Payment intents (migrations/20261104).
create index if not exists idx_payment_intents_client_order
  on public.payment_intents (client_order_id);
-- The refund/ops queue: any intent with no order, whether or not verify ran.
create index if not exists idx_payment_intents_orphans
  on public.payment_intents (created_at desc)
  where placed_order_id is null;

-- ====================================================================
-- Row Level Security (RLS)
-- ====================================================================
alter table public.universes enable row level security;
alter table public.motifs enable row level security;
alter table public.categories enable row level security;
alter table public.garments enable row level security;
alter table public.collections enable row level security;
alter table public.products enable row level security;
alter table public.variants enable row level security;
alter table public.product_images enable row level security;
alter table public.embroidery_details enable row level security;
alter table public.newsletter_subscribers enable row level security;
alter table public.reviews enable row level security;
alter table public.orders enable row level security;
-- The payment ledger (migrations/20261104). RLS on, NO policies: deny-all to
-- anon/authenticated, service role only. Money is never readable from a browser.
alter table public.payment_intents enable row level security;
-- The seven tables restored to this baseline on 2026-10-31 came from migrations
-- that were BORN locked. Leaving them out would make the baseline weaker than
-- the chain: `admins` would be a readable/writable admin allowlist and
-- `coupons` a public promo book. RLS-on with no policy is deny-all, which is
-- the correct baseline; the migrations supply the real policies.
alter table public.attribute_definitions enable row level security;
alter table public.admins enable row level security;
alter table public.coupons enable row level security;
alter table public.shipping_rules enable row level security;
alter table public.customer_addresses enable row level security;
alter table public.customer_wishlists enable row level security;
alter table public.coupon_redemptions enable row level security;
alter table public.order_items enable row level security;

-- Public READ policies for catalog
create policy "Allow public read universes" on public.universes for select using (true);
create policy "Allow public read motifs" on public.motifs for select using (true);
create policy "Allow public read categories" on public.categories for select using (true);
create policy "Allow public read garments" on public.garments for select using (true);
create policy "Allow public read collections" on public.collections for select using (true);
create policy "Allow public read products" on public.products for select using (true);
create policy "Allow public read variants" on public.variants for select using (true);
create policy "Allow public read product images" on public.product_images for select using (true);
create policy "Allow public read embroidery details" on public.embroidery_details for select using (true);
create policy "Allow public read reviews" on public.reviews for select using (true);

-- Public WRITE policies for storefront operations
create policy "Allow public newsletter subscribe" on public.newsletter_subscribers for insert with check (true);
create policy "Allow public submit review" on public.reviews for insert with check (true);
create policy "Allow public create orders" on public.orders for insert with check (true);
create policy "Allow public create order items" on public.order_items for insert with check (true);

-- Allow in-app Admin Studio to insert/update/delete catalog rows
create policy "Allow admin insert universes" on public.universes for insert with check (true);
create policy "Allow admin update universes" on public.universes for update using (true);
create policy "Allow admin insert motifs" on public.motifs for insert with check (true);
create policy "Allow admin update motifs" on public.motifs for update using (true);
create policy "Allow admin insert categories" on public.categories for insert with check (true);
create policy "Allow admin update categories" on public.categories for update using (true);
create policy "Allow admin insert garments" on public.garments for insert with check (true);
create policy "Allow admin update garments" on public.garments for update using (true);
create policy "Allow admin delete garments" on public.garments for delete using (true);
create policy "Allow admin insert collections" on public.collections for insert with check (true);
create policy "Allow admin update collections" on public.collections for update using (true);
create policy "Allow admin delete collections" on public.collections for delete using (true);
create policy "Allow admin insert products" on public.products for insert with check (true);
create policy "Allow admin update products" on public.products for update using (true);
create policy "Allow admin delete products" on public.products for delete using (true);
create policy "Allow admin insert variants" on public.variants for insert with check (true);
create policy "Allow admin update variants" on public.variants for update using (true);
create policy "Allow admin delete variants" on public.variants for delete using (true);
create policy "Allow admin insert product images" on public.product_images for insert with check (true);
create policy "Allow admin delete product images" on public.product_images for delete using (true);
create policy "Allow admin insert embroidery details" on public.embroidery_details for insert with check (true);
create policy "Allow admin update embroidery details" on public.embroidery_details for update using (true);
create policy "Allow admin delete embroidery details" on public.embroidery_details for delete using (true);

-- ====================================================================
-- Storage Bucket for Product Imagery (Media CDN)
-- ====================================================================
insert into storage.buckets (id, name, public) 
values ('product-images', 'product-images', true) 
on conflict (id) do nothing;

create policy "Public Read Product Images" on storage.objects 
for select using (bucket_id = 'product-images');

create policy "Public Upload Product Images" on storage.objects 
for insert with check (bucket_id = 'product-images');

-- ====================================================================
-- Seeding Instructions:
-- ====================================================================
-- This file is the BASELINE DDL. The migration chain in migrations/ is
-- authoritative for attribute_definitions, the attribute/rating triggers, the
-- order RPCs and the write-path policies; apply it before seeding.
--
--   1. Production baseline: backend/production-seed.sql  (generated by
--      scripts/gen-seed.mjs; 29 products / 197 variants)
--   2. Local / dev:        backend/seed.sql  (legacy, hand-maintained, expected
--      to lag the schema — NOT a production path)
--
-- Hosted state measured 2026-10-31 (read-only probes):
--   products = 44 columns (trust shape; no is_mock, no intensity)
--   place_order / quote_order / get_order_details installed
--   public.admins present                   -> 20261025 applied
--   anon INSERT garments -> 401 42501       -> catalogue write path CLOSED
--   customer_addresses / customer_wishlists / orders.user_id present
--                                           -> 20261031 applied
--   coupons / shipping_rules / coupon_redemptions present
--                                           -> 20261101 applied
--   intensity absent BY DECISION; 01_web_20261013 retired to migrations/_archive/
--   (both clients derive intensity from expression_score — parity gap #2)
--
-- The earlier "write path is open / admins absent" reading was accurate on
-- 2026-10-25 and is superseded by the measurements above.
-- ====================================================================
