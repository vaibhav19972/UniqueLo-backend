-- ====================================================================
-- UniqueLo — Production Database Seed
-- Minimal Baseline: Complete Master Taxonomy + 2 Flagship Reference Products
--
-- Purpose:
--   1. Seed all foundational master tables (Universes, Motifs, Categories,
--      Garments, Collections) so that foreign key constraints, menus,
--      and catalog filters operate seamlessly.
--   2. Seed exactly 2 authentic, handcrafted showcase products (with real
--      variants, image links to disk, and complete embroidery specifications).
--   3. Keep the catalog lean and pristine so you can manually upload real
--      products one-by-one via the Admin Studio (/admin) or Supabase Table Editor.
-- ====================================================================

-- 0. Schema Pre-flight: Ensure modern taxonomy tables & columns exist
-- This guarantees execution succeeds even if running against an older database schema.
CREATE TABLE IF NOT EXISTS public.universes (
  slug text PRIMARY KEY,
  name text NOT NULL,
  tagline text NOT NULL,
  lore text NOT NULL,
  emblem_src text,
  hero_image text,
  drop_cadence text,
  is_active boolean DEFAULT true,
  order_num integer DEFAULT 0,
  theme_tokens jsonb DEFAULT '{}'::jsonb,
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
  created_at timestamptz DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE TABLE IF NOT EXISTS public.motifs (
  id text PRIMARY KEY,
  universe_slug text REFERENCES public.universes(slug) ON DELETE CASCADE NOT NULL,
  name text NOT NULL,
  meaning text NOT NULL,
  symbol_notes text,
  ip_cleared boolean DEFAULT true,
  created_at timestamptz DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE TABLE IF NOT EXISTS public.categories (
  slug text PRIMARY KEY,
  name text NOT NULL,
  label text NOT NULL,
  description text NOT NULL,
  image text,
  order_num integer DEFAULT 0,
  created_at timestamptz DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE TABLE IF NOT EXISTS public.garments (
  slug text PRIMARY KEY,
  name text NOT NULL,
  category_slug text REFERENCES public.categories(slug) ON DELETE SET NULL,
  description text NOT NULL,
  order_num integer DEFAULT 0,
  created_at timestamptz DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE TABLE IF NOT EXISTS public.collections (
  slug text PRIMARY KEY,
  name text NOT NULL,
  tagline text,
  description text,
  universe_slug text REFERENCES public.universes(slug) ON DELETE SET NULL,
  cover_image text,
  featured boolean DEFAULT true,
  order_num integer DEFAULT 0,
  created_at timestamptz DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Ensure all modern columns exist on public.products
ALTER TABLE IF EXISTS public.products
  ADD COLUMN IF NOT EXISTS foreign_tagline text,
  ADD COLUMN IF NOT EXISTS universe_slug text REFERENCES public.universes(slug) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS collection_slug text REFERENCES public.collections(slug) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS garment_type text REFERENCES public.garments(slug) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS gender text DEFAULT 'unisex',
  ADD COLUMN IF NOT EXISTS motif_id text REFERENCES public.motifs(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS handcrafted boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS expression_score smallint DEFAULT 3,
  ADD COLUMN IF NOT EXISTS expression_slug text DEFAULT 'cult',
  ADD COLUMN IF NOT EXISTS craft_techniques text[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS edits text[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS rating numeric(3,1) DEFAULT 5.0,
  ADD COLUMN IF NOT EXISTS review_count integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS sold_count text;

-- Ensure RLS and public read policies exist on all taxonomy tables
ALTER TABLE IF EXISTS public.universes ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.motifs ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.garments ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.collections ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  -- 1. Public Read Policies
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'universes' AND policyname = 'Allow public read universes') THEN
    CREATE POLICY "Allow public read universes" ON public.universes FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'motifs' AND policyname = 'Allow public read motifs') THEN
    CREATE POLICY "Allow public read motifs" ON public.motifs FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'categories' AND policyname = 'Allow public read categories') THEN
    CREATE POLICY "Allow public read categories" ON public.categories FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'garments' AND policyname = 'Allow public read garments') THEN
    CREATE POLICY "Allow public read garments" ON public.garments FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'collections' AND policyname = 'Allow public read collections') THEN
    CREATE POLICY "Allow public read collections" ON public.collections FOR SELECT USING (true);
  END IF;

  -- 2. Admin Studio Write Policies for taxonomy
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'universes' AND policyname = 'Allow admin insert universes') THEN
    CREATE POLICY "Allow admin insert universes" ON public.universes FOR INSERT WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'universes' AND policyname = 'Allow admin update universes') THEN
    CREATE POLICY "Allow admin update universes" ON public.universes FOR UPDATE USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'motifs' AND policyname = 'Allow admin insert motifs') THEN
    CREATE POLICY "Allow admin insert motifs" ON public.motifs FOR INSERT WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'motifs' AND policyname = 'Allow admin update motifs') THEN
    CREATE POLICY "Allow admin update motifs" ON public.motifs FOR UPDATE USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'categories' AND policyname = 'Allow admin insert categories') THEN
    CREATE POLICY "Allow admin insert categories" ON public.categories FOR INSERT WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'categories' AND policyname = 'Allow admin update categories') THEN
    CREATE POLICY "Allow admin update categories" ON public.categories FOR UPDATE USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'garments' AND policyname = 'Allow admin insert garments') THEN
    CREATE POLICY "Allow admin insert garments" ON public.garments FOR INSERT WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'garments' AND policyname = 'Allow admin update garments') THEN
    CREATE POLICY "Allow admin update garments" ON public.garments FOR UPDATE USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'collections' AND policyname = 'Allow admin insert collections') THEN
    CREATE POLICY "Allow admin insert collections" ON public.collections FOR INSERT WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'collections' AND policyname = 'Allow admin update collections') THEN
    CREATE POLICY "Allow admin update collections" ON public.collections FOR UPDATE USING (true);
  END IF;

  -- 3. Safely link garment_type to garments table if not already linked
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'products_garment_type_fkey') THEN
    BEGIN
      ALTER TABLE public.products
        ADD CONSTRAINT products_garment_type_fkey
        FOREIGN KEY (garment_type) REFERENCES public.garments(slug) ON DELETE SET NULL NOT VALID;
    EXCEPTION
      WHEN others THEN NULL;
    END;
  END IF;
END $$;


-- --------------------------------------------------------------------
-- 1. Master Universes (Brand Pillars & Thematic Worlds)
-- --------------------------------------------------------------------
INSERT INTO public.universes (
  slug, name, tagline, lore, emblem_src, hero_image, drop_cadence, is_active, order_num, theme_tokens,
  portal_title_color, lore_heading, hero_headline, hero_headline_accent, hero_lead_color, hero_accent_color,
  hero_headline_case, hero_kicker, hero_ornament, hero_note, hero_vertical_text
) VALUES (
  'animeverse',
  'Animeverse',
  'Icons. Emotions. Forever.',
  'Beloved worlds, reimagined in threads. Embroidered apparel inspired by the stories that shaped a generation — from timeless classics to modern legends.',
  '/images/categories/tops.jpg',
  '/images/campaigns/hero-animeverse.jpg',
  'Seasonal arcs + monthly mini-drops',
  true,
  1,
  '{"bg":"#10131f","surface":"#191f36","ink":"#f4efe6","accent":"#e9b9cd","accent2":"#86d3e6","product_zone":"#f7f5f0","divider":"sakura-petal","card_frame":"torii","texture_opacity":0.06,"display_font":"condensed-bold"}'::jsonb,
  '#7a1f23',
  'More Than Characters.',
  NULL,
  NULL,
  NULL,
  NULL,
  'caps',
  '動 漫',
  NULL,
  NULL,
  '物語は、永遠に着られる。'
) ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  tagline = EXCLUDED.tagline,
  lore = EXCLUDED.lore,
  hero_image = EXCLUDED.hero_image,
  theme_tokens = EXCLUDED.theme_tokens;

INSERT INTO public.universes (
  slug, name, tagline, lore, emblem_src, hero_image, drop_cadence, is_active, order_num, theme_tokens,
  portal_title_color, lore_heading, hero_headline, hero_headline_accent, hero_lead_color, hero_accent_color,
  hero_headline_case, hero_kicker, hero_ornament, hero_note, hero_vertical_text
) VALUES (
  'heroverse',
  'Heroverse',
  'Courage lives differently here.',
  'Legends, icons and everyday heroes stitched to inspire. Cosmic-scale embroidery for those who carry their own weight — and then some.',
  '/images/categories/outerwear.jpg',
  '/images/campaigns/hero-heroverse.jpg',
  'Monthly New-Issue drops',
  true,
  2,
  '{"bg":"#131316","surface":"#1d161a","ink":"#f5f0e8","accent":"#c0392b","accent2":"#d4af37","product_zone":"#faf6ee","divider":"action-lines","card_frame":"badge","texture_opacity":0.06,"display_font":"extra-bold-italic"}'::jsonb,
  '#a8862f',
  'Icons Are Ideas.',
  'Extraordinary Lives Ahead.',
  'Extraordinary',
  NULL,
  '#d4af37',
  'sentence',
  NULL,
  'compass',
  'Same people. Brighter versions.',
  NULL
) ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  tagline = EXCLUDED.tagline,
  lore = EXCLUDED.lore,
  hero_image = EXCLUDED.hero_image,
  theme_tokens = EXCLUDED.theme_tokens;

INSERT INTO public.universes (
  slug, name, tagline, lore, emblem_src, hero_image, drop_cadence, is_active, order_num, theme_tokens,
  portal_title_color, lore_heading, hero_headline, hero_headline_accent, hero_lead_color, hero_accent_color,
  hero_headline_case, hero_kicker, hero_ornament, hero_note, hero_vertical_text
) VALUES (
  'itihaas',
  'Itihaas',
  'Our history. Always relevant.',
  'Moments, empires and folk stories in contemporary forms. Royal Indian craft lineages — processions, arches, jaals — embroidered for the everyday wardrobe.',
  '/images/categories/knitwear.jpg',
  '/images/campaigns/hero-itihaas.jpg',
  'Festive darbar collections',
  true,
  3,
  '{"bg":"#f7f3ea","surface":"#eee7d9","ink":"#2e241a","accent":"#6d1f2c","accent2":"#0e6a63","product_zone":"#faf8f5","divider":"mughal-arch","card_frame":"arch","texture_opacity":0.05,"display_font":"elegant-serif"}'::jsonb,
  '#6d1f2c',
  'Symbols That Shaped Us.',
  'Threads of a Brighter Bharat.',
  'Bharat.',
  '#2e241a',
  '#6d1f2c',
  'sentence',
  NULL,
  'lotus',
  NULL,
  'अतीत से प्रेरणा वर्तमान के लिए।'
) ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  tagline = EXCLUDED.tagline,
  lore = EXCLUDED.lore,
  hero_image = EXCLUDED.hero_image,
  theme_tokens = EXCLUDED.theme_tokens;

-- --------------------------------------------------------------------
-- 2. IP-Cleared Motifs
-- --------------------------------------------------------------------
INSERT INTO public.motifs (id, universe_slug, name, meaning, symbol_notes, ip_cleared) VALUES
  ('red-sun', 'animeverse', 'The Red Sun', 'A symbol of hope, resilience and new beginnings.', 'Flat crimson disc, minimal, pairs with mountain/wave linework.', true),
  ('koi', 'animeverse', 'The Koi', 'Perseverance through every current.', 'Swimming koi with wave curls, dynamic diagonal flow.', true),
  ('sakura', 'animeverse', 'Sakura', 'Beauty in impermanence, strength in renewal.', 'Five-petal blossoms on bare branches, scattered petals.', true),
  ('ascendant-crest', 'heroverse', 'The Ascendant Crest', 'Rise, carry, protect — the everyday hero''s mark.', 'Bold shield-crest geometry, gold on deep red.', true),
  ('guardian-stripes', 'heroverse', 'Guardian Stripes', 'Speed lines of those who show up first.', 'Diagonal action-line bands, navy and burst yellow.', true),
  ('procession-elephant', 'itihaas', 'The Royal Procession', 'Ceremony, memory and rightful pride.', 'Caparisoned elephant with arch-and-jaal backdrop.', true),
  ('arch-jaal', 'itihaas', 'Arch Jaal', 'Courtyards of patience — geometry as devotion.', 'Mughal arch lattice, symmetric, gold on maroon.', true)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  meaning = EXCLUDED.meaning;

-- --------------------------------------------------------------------
-- 3. Categories Table
-- --------------------------------------------------------------------
INSERT INTO public.categories (slug, name, label, description, image, order_num) VALUES
  ('outerwear', 'Outerwear', 'Outerwear', 'Tailored chore jackets, kimono overcoats, and embroidered denim outerwear.', '/images/categories/outerwear.jpg', 1),
  ('knitwear', 'Knitwear', 'Knitwear', 'Pure cashmere cardigans, merino sweaters, and chain-stitched crewnecks.', '/images/categories/knitwear.jpg', 2),
  ('tops', 'Tops & Shirts', 'Tops', 'Heavyweight organic cotton box tees, silk-floss oxfords, and band-collar tunics.', '/images/categories/tops.jpg', 3),
  ('bottoms', 'Bottoms', 'Bottoms', 'Pleated wide-leg trousers, raw selvedge denim, and kantha-embroidered work pants.', '/images/categories/bottoms.jpg', 4),
  ('accessories', 'Accessories', 'Accessories', 'Embroidered silk scarves, raw canvas tote bags, and heirloom monogram badges.', '/images/categories/accessories.jpg', 5)
ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description;

-- --------------------------------------------------------------------
-- 4. Garments Table (Silhouette Taxonomy)
-- --------------------------------------------------------------------
INSERT INTO public.garments (slug, name, category_slug, description, order_num) VALUES
  ('hoodie', 'Hoodies', 'tops', 'Heavyweight fleece hoodies with back-panel and crest embroidery.', 1),
  ('tee', 'Tees', 'tops', 'Combed-cotton tees carrying chest and back threadwork.', 2),
  ('shirt', 'Shirts', 'tops', 'Oxfords, poplins and band-collar tunics with monogram detail.', 3),
  ('jacket', 'Jackets', 'outerwear', 'Chore jackets, capes and overcoats with procession-scale embroidery.', 4),
  ('cardigan', 'Cardigans', 'knitwear', 'Cashmere cardigans with crewel relief.', 5),
  ('vest', 'Vests', 'knitwear', 'Knit vests with sculpted knot texture.', 6),
  ('pants', 'Pants', 'bottoms', 'Selvedge denim and work pants with structural stitching.', 7),
  ('scarf', 'Scarves', 'accessories', 'Silk scarves with arch-jaal and flora borders.', 8),
  ('tote', 'Totes', 'accessories', 'Raw-canvas totes with sun-disc and motif hits.', 9)
ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  category_slug = EXCLUDED.category_slug,
  description = EXCLUDED.description,
  order_num = EXCLUDED.order_num;

-- --------------------------------------------------------------------
-- 5. Collections Table (Seasonal Drops & Thematic Capsules)
-- --------------------------------------------------------------------
INSERT INTO public.collections (slug, name, tagline, description, universe_slug, featured, order_num) VALUES
  ('spring-sakura', 'Spring Sakura Collection', 'Japanese woodblock waves, blossom scatter, ink-line calm.', 'Inspired by spring in the floating world — flat sun discs, wave curls, and floating cherry blossom embroidery.', 'animeverse', true, 1),
  ('royal-heritage', 'Royal Heritage Collection', 'Arches, jaals and royal court processions in gold zardozi.', 'Arch lattices, elephant processions, and intricate jaal geometry drawn from royal court lineages.', 'itihaas', true, 2),
  ('midnight-atelier', 'Midnight Atelier Collection', 'No world, just pure cloth, heroic crests, and tonal needlecraft.', 'Universe-neutral and nocturnal luxury pieces — sashiko grids, crewel relief, comic noir geometry, and understated crest detailing.', NULL, true, 3)
ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  tagline = EXCLUDED.tagline,
  description = EXCLUDED.description,
  universe_slug = EXCLUDED.universe_slug,
  featured = EXCLUDED.featured,
  order_num = EXCLUDED.order_num;

-- --------------------------------------------------------------------
-- 6. Flagship Showcase Products (Exactly 2 Handcrafted SKUs, is_mock = false)
-- --------------------------------------------------------------------

-- Product 1: Sakura Ronin Heavyweight Hoodie (Animeverse · Tops/Hoodie)
INSERT INTO public.products (
  slug, name, subtitle, foreign_tagline, description, category_slug, universe_slug,
  collection_slug, garment_type, gender, motif_id, handcrafted,
  craft_techniques, edits, expression_score, expression_slug,
  rating, review_count, sold_count, tags, featured, customizable,
  material, care, fit, batch_number, batch_total, craft_region, craft_cluster, fabric_gsm
) VALUES (
  'sakura-ronin-hoodie',
  'Sakura Ronin Heavyweight Hoodie',
  '450 GSM fleece with high-density back-panel cherry blossom embroidery',
  '桜の浪人',
  'An artisanal heavyweight hoodie combining structured boxy streetwear silhouettes with authentic floating-world needlework. Features 48,000 stitches of high-relief silk-poly thread across the back yoke and left chest crest.',
  'tops',
  'animeverse',
  'spring-sakura',
  'hoodie',
  'unisex',
  'sakura',
  true,
  ARRAY['high-relief-fill', 'satin-stitch'],
  ARRAY['cherry-blossom', 'street-atelier'],
  3,
  'cult',
  4.9,
  18,
  '80+',
  ARRAY['hoodie', 'embroidery', 'animeverse', 'sakura', 'heavyweight'],
  true,
  true,
  ARRAY['100% GOTS Combed Cotton Fleece (450 GSM)', 'Japanese Rayon & Silk-poly threads'],
  ARRAY['Machine wash cold inside out on gentle cycle', 'Dry flat in shade', 'Do not iron directly over embroidery'],
  'Relaxed dropped-shoulder atelier fit',
  1,
  50,
  'Kyoto & Tirupur Guild',
  'Master Needlecraft Studio',
  '450 GSM'
) ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  subtitle = EXCLUDED.subtitle,
  foreign_tagline = EXCLUDED.foreign_tagline,
  description = EXCLUDED.description,
  category_slug = EXCLUDED.category_slug,
  universe_slug = EXCLUDED.universe_slug,
  collection_slug = EXCLUDED.collection_slug,
  garment_type = EXCLUDED.garment_type,
  gender = EXCLUDED.gender,
  motif_id = EXCLUDED.motif_id,
  handcrafted = EXCLUDED.handcrafted,
  craft_techniques = EXCLUDED.craft_techniques,
  edits = EXCLUDED.edits,
  expression_score = EXCLUDED.expression_score,
  expression_slug = EXCLUDED.expression_slug,
  rating = EXCLUDED.rating,
  review_count = EXCLUDED.review_count,
  sold_count = EXCLUDED.sold_count,
  tags = EXCLUDED.tags,
  featured = EXCLUDED.featured,
  customizable = EXCLUDED.customizable;

-- Product 1 Images
DELETE FROM public.product_images WHERE product_slug = 'sakura-ronin-hoodie';
INSERT INTO public.product_images (product_slug, src, alt, color, sort_order) VALUES
  ('sakura-ronin-hoodie', '/images/products/sakura-ronin-hoodie-1.jpg', 'Sakura Ronin Heavyweight Hoodie — front view', '#1a191b', 0),
  ('sakura-ronin-hoodie', '/images/products/sakura-ronin-hoodie-2.jpg', 'Sakura Ronin Heavyweight Hoodie — back embroidery panel', '#1a191b', 1),
  ('sakura-ronin-hoodie', '/images/products/sakura-ronin-hoodie-3.jpg', 'Sakura Ronin Heavyweight Hoodie — macro stitch detail', '#1a191b', 2),
  ('sakura-ronin-hoodie', '/images/products/sakura-ronin-hoodie-4.jpg', 'Sakura Ronin Heavyweight Hoodie — cuff and silhouette detail', '#1a191b', 3);

-- Product 1 Variants
DELETE FROM public.variants WHERE product_slug = 'sakura-ronin-hoodie';
INSERT INTO public.variants (sku, product_slug, color, color_hex, size, price_cents, compare_at_price_cents, status, quantity) VALUES
  ('UNI-SRH-BLK-S', 'sakura-ronin-hoodie', 'Washed Charcoal', '#1a191b', 'S', 899000, 1050000, 'in-stock', 12),
  ('UNI-SRH-BLK-M', 'sakura-ronin-hoodie', 'Washed Charcoal', '#1a191b', 'M', 899000, 1050000, 'in-stock', 18),
  ('UNI-SRH-BLK-L', 'sakura-ronin-hoodie', 'Washed Charcoal', '#1a191b', 'L', 899000, 1050000, 'in-stock', 15),
  ('UNI-SRH-BLK-XL', 'sakura-ronin-hoodie', 'Washed Charcoal', '#1a191b', 'XL', 899000, 1050000, 'low-stock', 5);

-- Product 1 Embroidery Specification
DELETE FROM public.embroidery_details WHERE product_slug = 'sakura-ronin-hoodie';
INSERT INTO public.embroidery_details (
  product_slug, technique, technique_label, artisan_hours, placement,
  thread_composition, motif_story, macro_image_src, macro_image_alt
) VALUES (
  'sakura-ronin-hoodie',
  'high-density-fill',
  'High-Density Threadwork',
  14,
  ARRAY['Center Back Full Panel', 'Left Chest Crest'],
  '100% Japanese Rayon & High-Luster Silk-Poly',
  'The Sakura blossom signifies resilience and the beauty of fleeting moments, stitched in graduated pastel pink and gold filaments across 48,000 distinct punctures.',
  '/images/products/sakura-ronin-hoodie-3.jpg',
  'Macro close-up of Sakura needlework'
);

-- Product 1 Verified Review
DELETE FROM public.reviews WHERE product_slug = 'sakura-ronin-hoodie';
INSERT INTO public.reviews (product_slug, author, rating, title, comment, verified) VALUES (
  'sakura-ronin-hoodie',
  'Aditya S.',
  5,
  'Unrivaled drape and embroidery weight',
  'The stitch density on the back panel is astonishing in person. Fabric is thick, structured, and holds shape perfectly.',
  true
);


-- Product 2: Heritage Kantha Stitch Chore Jacket (Itihaas · Outerwear/Jacket)
INSERT INTO public.products (
  slug, name, subtitle, foreign_tagline, description, category_slug, universe_slug,
  collection_slug, garment_type, gender, motif_id, handcrafted,
  craft_techniques, edits, expression_score, expression_slug,
  rating, review_count, sold_count, tags, featured, customizable,
  material, care, fit, batch_number, batch_total, craft_region, craft_cluster, fabric_gsm
) VALUES (
  'kantha-chore-jacket',
  'Heritage Kantha Stitch Chore Jacket',
  'Hand-stitched running kantha threads on 14oz raw selvedge canvas',
  'कांथा शिल्प',
  'A timeless chore silhouette tailored from unbleached organic canvas and layered with Bengal running-stitch Kantha embroidery along the pocket flaps, collar points, and back yoke.',
  'outerwear',
  'itihaas',
  'royal-heritage',
  'jacket',
  'unisex',
  'arch-jaal',
  true,
  ARRAY['kantha-running-stitch', 'zari-relief'],
  ARRAY['heritage', 'quiet-luxury'],
  2,
  'understated',
  5.0,
  12,
  '45+',
  ARRAY['jacket', 'chore', 'kantha', 'itihaas', 'outerwear', 'handcrafted'],
  true,
  false,
  ARRAY['100% Unbleached Heavy Cotton Canvas (380 GSM)', 'Wild Tussar Silk Floss'],
  ARRAY['Dry clean recommended for first 2 washes', 'Cold hand wash with mild eco-detergent', 'Line dry in shade'],
  'Structured atelier utility cut, boxy drape',
  1,
  35,
  'Santiniketan, West Bengal',
  'Bengal Artisan Guild',
  '380 GSM'
) ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  subtitle = EXCLUDED.subtitle,
  foreign_tagline = EXCLUDED.foreign_tagline,
  description = EXCLUDED.description,
  category_slug = EXCLUDED.category_slug,
  universe_slug = EXCLUDED.universe_slug,
  collection_slug = EXCLUDED.collection_slug,
  garment_type = EXCLUDED.garment_type,
  gender = EXCLUDED.gender,
  motif_id = EXCLUDED.motif_id,
  handcrafted = EXCLUDED.handcrafted,
  craft_techniques = EXCLUDED.craft_techniques,
  edits = EXCLUDED.edits,
  expression_score = EXCLUDED.expression_score,
  expression_slug = EXCLUDED.expression_slug,
  rating = EXCLUDED.rating,
  review_count = EXCLUDED.review_count,
  sold_count = EXCLUDED.sold_count,
  tags = EXCLUDED.tags,
  featured = EXCLUDED.featured,
  customizable = EXCLUDED.customizable;

-- Product 2 Images
DELETE FROM public.product_images WHERE product_slug = 'kantha-chore-jacket';
INSERT INTO public.product_images (product_slug, src, alt, color, sort_order) VALUES
  ('kantha-chore-jacket', '/images/products/kantha-chore-jacket-1.jpg', 'Heritage Kantha Stitch Chore Jacket — front view', '#ece6d9', 0),
  ('kantha-chore-jacket', '/images/products/kantha-chore-jacket-2.jpg', 'Heritage Kantha Stitch Chore Jacket — craft detail & embroidery', '#ece6d9', 1);

-- Product 2 Variants
DELETE FROM public.variants WHERE product_slug = 'kantha-chore-jacket';
INSERT INTO public.variants (sku, product_slug, color, color_hex, size, price_cents, compare_at_price_cents, status, quantity) VALUES
  ('UNI-KCJ-ECR-S', 'kantha-chore-jacket', 'Raw Ecru', '#ece6d9', 'S', 1249000, 1499000, 'in-stock', 8),
  ('UNI-KCJ-ECR-M', 'kantha-chore-jacket', 'Raw Ecru', '#ece6d9', 'M', 1249000, 1499000, 'in-stock', 14),
  ('UNI-KCJ-ECR-L', 'kantha-chore-jacket', 'Raw Ecru', '#ece6d9', 'L', 1249000, 1499000, 'in-stock', 10),
  ('UNI-KCJ-ECR-XL', 'kantha-chore-jacket', 'Raw Ecru', '#ece6d9', 'XL', 1249000, 1499000, 'low-stock', 3);

-- Product 2 Embroidery Specification
DELETE FROM public.embroidery_details WHERE product_slug = 'kantha-chore-jacket';
INSERT INTO public.embroidery_details (
  product_slug, technique, technique_label, artisan_hours, placement,
  thread_composition, motif_story, macro_image_src, macro_image_alt
) VALUES (
  'kantha-chore-jacket',
  'kantha-running-stitch',
  'Bengal Kantha Needlecraft',
  22,
  ARRAY['Collar Lapels', 'Chest Pocket Border', 'Back Yoke Arch'],
  'Hand-spun Wild Tussar Silk Floss',
  'Inspired by traditional Bengal kantha textiles, where continuous running stitches reinforce cloth while tracing architectural jaal motifs in golden tussar silk.',
  '/images/products/kantha-chore-jacket-2.jpg',
  'Macro close-up of Kantha running stitch on raw canvas'
);

-- Product 2 Verified Review
DELETE FROM public.reviews WHERE product_slug = 'kantha-chore-jacket';
INSERT INTO public.reviews (product_slug, author, rating, title, comment, verified) VALUES (
  'kantha-chore-jacket',
  'Meera K.',
  5,
  'A museum piece you can wear every day',
  'The texture of raw ecru canvas paired with the uneven kantha running stitch feels genuine and deeply grounded in craft history.',
  true
);

-- --------------------------------------------------------------------
-- 7. Supabase Storage Setup (For Future Admin Product Photo Uploads)
-- --------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('product-images', 'product-images', true)
ON CONFLICT (id) DO NOTHING;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'Public Read Product Images'
  ) THEN
    CREATE POLICY "Public Read Product Images" ON storage.objects FOR SELECT USING (bucket_id = 'product-images');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'Public Upload Product Images'
  ) THEN
    CREATE POLICY "Public Upload Product Images" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'product-images');
  END IF;
END $$;
