-- ====================================================================
-- UniqueLo — Production Seed Data
-- 13 Original Atelier Products (Zero Mock Data) + Universes + Motifs + Categories
-- ====================================================================

-- 1. Seed Universes
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

-- 2. Seed Motifs
INSERT INTO public.motifs (id, universe_slug, name, meaning, symbol_notes, ip_cleared) VALUES (
  'red-sun', 'animeverse', 'The Red Sun', 'A symbol of hope, resilience and new beginnings.', 'Flat crimson disc, minimal, pairs with mountain/wave linework.', true
) ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  meaning = EXCLUDED.meaning;
INSERT INTO public.motifs (id, universe_slug, name, meaning, symbol_notes, ip_cleared) VALUES (
  'koi', 'animeverse', 'The Koi', 'Perseverance through every current.', 'Swimming koi with wave curls, dynamic diagonal flow.', true
) ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  meaning = EXCLUDED.meaning;
INSERT INTO public.motifs (id, universe_slug, name, meaning, symbol_notes, ip_cleared) VALUES (
  'sakura', 'animeverse', 'Sakura', 'Beauty in impermanence, strength in renewal.', 'Five-petal blossoms on bare branches, scattered petals.', true
) ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  meaning = EXCLUDED.meaning;
INSERT INTO public.motifs (id, universe_slug, name, meaning, symbol_notes, ip_cleared) VALUES (
  'ascendant-crest', 'heroverse', 'The Ascendant Crest', 'Rise, carry, protect — the everyday hero''s mark.', 'Bold shield-crest geometry, gold on deep red.', true
) ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  meaning = EXCLUDED.meaning;
INSERT INTO public.motifs (id, universe_slug, name, meaning, symbol_notes, ip_cleared) VALUES (
  'guardian-stripes', 'heroverse', 'Guardian Stripes', 'Speed lines of those who show up first.', 'Diagonal action-line bands, navy and burst yellow.', true
) ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  meaning = EXCLUDED.meaning;
INSERT INTO public.motifs (id, universe_slug, name, meaning, symbol_notes, ip_cleared) VALUES (
  'procession-elephant', 'itihaas', 'The Royal Procession', 'Ceremony, memory and rightful pride.', 'Caparisoned elephant with arch-and-jaal backdrop.', true
) ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  meaning = EXCLUDED.meaning;
INSERT INTO public.motifs (id, universe_slug, name, meaning, symbol_notes, ip_cleared) VALUES (
  'arch-jaal', 'itihaas', 'Arch Jaal', 'Courtyards of patience — geometry as devotion.', 'Mughal arch lattice, symmetric, gold on maroon.', true
) ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  meaning = EXCLUDED.meaning;

-- 3. Seed Categories
INSERT INTO public.categories (slug, name, label, description, image, order_num) VALUES (
  'outerwear', 'Outerwear', 'Outerwear', 'Tailored chore jackets, kimono overcoats, and embroidered denim outerwear.', '/images/categories/outerwear.jpg', 1
) ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description;
INSERT INTO public.categories (slug, name, label, description, image, order_num) VALUES (
  'knitwear', 'Knitwear', 'Knitwear', 'Pure cashmere cardigans, merino sweaters, and chain-stitched crewnecks.', '/images/categories/knitwear.jpg', 2
) ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description;
INSERT INTO public.categories (slug, name, label, description, image, order_num) VALUES (
  'tops', 'Tops & Shirts', 'Tops', 'Heavyweight organic cotton box tees, silk-floss oxfords, and band-collar tunics.', '/images/categories/tops.jpg', 3
) ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description;
INSERT INTO public.categories (slug, name, label, description, image, order_num) VALUES (
  'bottoms', 'Bottoms', 'Bottoms', 'Pleated wide-leg trousers, raw selvedge denim, and kantha-embroidered work pants.', '/images/categories/bottoms.jpg', 4
) ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description;
INSERT INTO public.categories (slug, name, label, description, image, order_num) VALUES (
  'accessories', 'Accessories', 'Accessories', 'Embroidered silk scarves, raw canvas tote bags, and heirloom monogram badges.', '/images/categories/accessories.jpg', 5
) ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description;

-- 3b. Seed Garment Silhouettes (Taxonomy Definition)
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

-- 3c. Seed Collections (Seasonal Drops & Thematic Capsules)
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

-- 4. Seed Original Handcrafted Products (13 SKUs, is_mock = false)
-- Product: Botanical Silk Embroidered Jacket
INSERT INTO public.products (
  slug, name, subtitle, foreign_tagline, description, category_slug, universe_slug,
  garment_type, gender, motif_id, is_mock, handcrafted, vibes, moods,
  rating, review_count, sold_count, tags, featured, customizable,
  material, care, fit, batch_number, batch_total, craft_region, craft_cluster, fabric_gsm
) VALUES (
  'botanical-silk-embroidered-jacket',
  'Botanical Silk Embroidered Jacket',
  'Hand-stitched flora on heavy washed organic cotton canvas',
  'वानस्पतिक रेशम',
  'An unstructured atelier workwear jacket featuring intricate hand-embroidered botanical floral vine motifs along the collar, lapel, and back yoke using pure mulberry silk floss.',
  'outerwear',
  'itihaas',
  'jacket',
  'unisex',
  'arch-jaal',
  false,
  true,
  ARRAY['aesthetic', 'expressive'],
  ARRAY['heritage', 'statement'],
  4.9,
  28,
  '120+',
  ARRAY['jacket', 'embroidery', 'hand-stitched', 'silk', 'outerwear'],
  true,
  true,
  ARRAY['100% GOTS Organic Cotton Canvas', 'Mulberry Silk Floss'],
  ARRAY['Delicate dry clean only', 'Store folded in breathable garment bag'],
  'Boxy relaxed atelier fit, true to size',
  8,
  40,
  'Lucknow, Uttar Pradesh',
  'Chikankari & Silk Chain Guild',
  '340 GSM Organic Cotton Canvas'
) ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  universe_slug = EXCLUDED.universe_slug,
  garment_type = EXCLUDED.garment_type,
  gender = EXCLUDED.gender,
  is_mock = EXCLUDED.is_mock,
  handcrafted = EXCLUDED.handcrafted,
  vibes = EXCLUDED.vibes,
  moods = EXCLUDED.moods;

INSERT INTO public.product_images (product_slug, src, alt, color, sort_order) VALUES
  ('botanical-silk-embroidered-jacket', '/images/products/botanical-silk-jacket-1.png', 'Botanical Silk Embroidered Jacket — front view', '#1d2a44', 0),
  ('botanical-silk-embroidered-jacket', '/images/products/botanical-silk-jacket-2.png', 'Botanical Silk Embroidered Jacket — macro stitch detail', '#1d2a44', 1);

INSERT INTO public.variants (sku, product_slug, color, color_hex, size, price_cents, compare_at_price_cents, status, quantity) VALUES
  ('bse-ind-s', 'botanical-silk-embroidered-jacket', 'Indigo', '#1d2a44', 'S', 4814000, NULL, 'in-stock', 10),
  ('bse-ind-m', 'botanical-silk-embroidered-jacket', 'Indigo', '#1d2a44', 'M', 4814000, NULL, 'in-stock', 10),
  ('bse-ind-l', 'botanical-silk-embroidered-jacket', 'Indigo', '#1d2a44', 'L', 4814000, NULL, 'low-stock', 2),
  ('bse-ecr-s', 'botanical-silk-embroidered-jacket', 'Ecru', '#f4efe6', 'S', 4814000, NULL, 'in-stock', 10),
  ('bse-ecr-m', 'botanical-silk-embroidered-jacket', 'Ecru', '#f4efe6', 'M', 4814000, NULL, 'in-stock', 10)
ON CONFLICT (sku) DO NOTHING;

INSERT INTO public.embroidery_details (
  product_slug, technique, technique_label, artisan_hours, placement, thread_composition, motif_story
) VALUES (
  'botanical-silk-embroidered-jacket',
  'botanical-chain',
  'Hand-stitched Chain & Satin Needlework',
  18,
  ARRAY['Collar', 'Back Yoke', 'Left Cuff'],
  '100% Spun Mulberry Silk Floss',
  'Inspired by 18th-century botanical field plates, meticulously rendered with micro-chain loops.'
) ON CONFLICT (product_slug) DO UPDATE SET
  technique = EXCLUDED.technique,
  technique_label = EXCLUDED.technique_label,
  artisan_hours = EXCLUDED.artisan_hours;

-- Product: Celestial Zardozi Wool Overcoat
INSERT INTO public.products (
  slug, name, subtitle, foreign_tagline, description, category_slug, universe_slug,
  garment_type, gender, motif_id, is_mock, handcrafted, vibes, moods,
  rating, review_count, sold_count, tags, featured, customizable,
  material, care, fit, batch_number, batch_total, craft_region, craft_cluster, fabric_gsm
) VALUES (
  'celestial-zardozi-wool-coat',
  'Celestial Zardozi Wool Overcoat',
  '24K metallic gold bullion thread on double-faced melton wool',
  'स्वर्गीय ज़रदोज़ी',
  'A tailored single-breasted overcoat accented with historic Zardozi wire embroidery depicting constellations and celestial geometry along the notched lapels and sleeve cuffs.',
  'outerwear',
  'heroverse',
  'jacket',
  'unisex',
  'ascendant-crest',
  false,
  true,
  ARRAY['gilded', 'noir'],
  ARRAY['statement', 'festive-gifting', 'collector'],
  5,
  19,
  '85+',
  ARRAY['coat', 'zardozi', 'metallic', 'wool', 'outerwear', 'couture'],
  true,
  false,
  ARRAY['100% Virgin Melton Wool', 'Cupro Bemberg Lining'],
  ARRAY['Specialist couture dry clean only'],
  'Structured tailored silhouette, hits mid-calf',
  3,
  25,
  'Jaipur, Rajasthan',
  'Pink City Zardozi Bullion Guild',
  '480 GSM Double-Faced Melton Wool'
) ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  universe_slug = EXCLUDED.universe_slug,
  garment_type = EXCLUDED.garment_type,
  gender = EXCLUDED.gender,
  is_mock = EXCLUDED.is_mock,
  handcrafted = EXCLUDED.handcrafted,
  vibes = EXCLUDED.vibes,
  moods = EXCLUDED.moods;

INSERT INTO public.product_images (product_slug, src, alt, color, sort_order) VALUES
  ('celestial-zardozi-wool-coat', '/images/products/celestial-zardozi-coat-1.png', 'Celestial Zardozi Wool Overcoat — silhouette view', '#121214', 0),
  ('celestial-zardozi-wool-coat', '/images/products/celestial-zardozi-coat-2.png', 'Celestial Zardozi Wool Overcoat — metallic wire embroidery detail', '#121214', 1);

INSERT INTO public.variants (sku, product_slug, color, color_hex, size, price_cents, compare_at_price_cents, status, quantity) VALUES
  ('czw-blk-38', 'celestial-zardozi-wool-coat', 'Nocturne Black', '#121214', '38', 10375000, NULL, 'in-stock', 10),
  ('czw-blk-40', 'celestial-zardozi-wool-coat', 'Nocturne Black', '#121214', '40', 10375000, NULL, 'in-stock', 10),
  ('czw-blk-42', 'celestial-zardozi-wool-coat', 'Nocturne Black', '#121214', '42', 10375000, NULL, 'low-stock', 1)
ON CONFLICT (sku) DO NOTHING;

INSERT INTO public.embroidery_details (
  product_slug, technique, technique_label, artisan_hours, placement, thread_composition, motif_story
) VALUES (
  'celestial-zardozi-wool-coat',
  'hand-zardozi',
  'Authentic Hand Zardozi Wirework',
  32,
  ARRAY['Lapel Peaks', 'Back Collar', 'Sleeve Cuffs'],
  'Gilt French Wire & Metallic Zari Thread',
  'Astral cartography crafted with traditional coiled bullion wires hand-anchored onto heavy melton wool.'
) ON CONFLICT (product_slug) DO UPDATE SET
  technique = EXCLUDED.technique,
  technique_label = EXCLUDED.technique_label,
  artisan_hours = EXCLUDED.artisan_hours;

-- Product: Heirloom Kantha Quilted Chore Jacket
INSERT INTO public.products (
  slug, name, subtitle, foreign_tagline, description, category_slug, universe_slug,
  garment_type, gender, motif_id, is_mock, handcrafted, vibes, moods,
  rating, review_count, sold_count, tags, featured, customizable,
  material, care, fit, batch_number, batch_total, craft_region, craft_cluster, fabric_gsm
) VALUES (
  'kantha-quilted-chore-jacket',
  'Heirloom Kantha Quilted Chore Jacket',
  'Repurposed vintage indigo textiles with continuous running stitch',
  'कांथा रजाई',
  'Each piece is completely unique, built from vintage hand-dyed indigo textiles layered and reinforced with thousands of dense Kantha running stitches by women artisan collectives.',
  'outerwear',
  'itihaas',
  'jacket',
  'unisex',
  'procession-elephant',
  false,
  true,
  ARRAY['aesthetic', 'minimal'],
  ARRAY['heritage', 'collector'],
  4.8,
  34,
  '150+',
  ARRAY['jacket', 'kantha', 'indigo', 'quilted', 'outerwear'],
  false,
  false,
  ARRAY['Upcycled Handloom Cotton', 'Plant Indigo Dye'],
  ARRAY['Cold hand wash separately', 'Line dry in shade'],
  'Casual straight box cut',
  12,
  50,
  'Bolpur & Murshidabad, West Bengal',
  'Shantiniketan Kantha Collective',
  '360 GSM Vintage Handloom Quilt'
) ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  universe_slug = EXCLUDED.universe_slug,
  garment_type = EXCLUDED.garment_type,
  gender = EXCLUDED.gender,
  is_mock = EXCLUDED.is_mock,
  handcrafted = EXCLUDED.handcrafted,
  vibes = EXCLUDED.vibes,
  moods = EXCLUDED.moods;

INSERT INTO public.product_images (product_slug, src, alt, color, sort_order) VALUES
  ('kantha-quilted-chore-jacket', '/images/products/kantha-chore-jacket-1.jpg', 'Heirloom Kantha Quilted Chore Jacket — full view', '#23334d', 0),
  ('kantha-quilted-chore-jacket', '/images/products/kantha-chore-jacket-2.jpg', 'Heirloom Kantha Quilted Chore Jacket — running stitch texture', '#23334d', 1);

INSERT INTO public.variants (sku, product_slug, color, color_hex, size, price_cents, compare_at_price_cents, status, quantity) VALUES
  ('kqj-ind-s', 'kantha-quilted-chore-jacket', 'Vintage Indigo', '#23334d', 'S', 5312000, NULL, 'in-stock', 10),
  ('kqj-ind-m', 'kantha-quilted-chore-jacket', 'Vintage Indigo', '#23334d', 'M', 5312000, NULL, 'in-stock', 10),
  ('kqj-ind-l', 'kantha-quilted-chore-jacket', 'Vintage Indigo', '#23334d', 'L', 5312000, NULL, 'in-stock', 10)
ON CONFLICT (sku) DO NOTHING;

INSERT INTO public.embroidery_details (
  product_slug, technique, technique_label, artisan_hours, placement, thread_composition, motif_story
) VALUES (
  'kantha-quilted-chore-jacket',
  'kantha-quilt',
  'Traditional Kantha Running Stitch Quilt',
  24,
  ARRAY['Full Garment Body', 'Sleeves'],
  '100% Unbleached Cotton Thread',
  'Centuries-old Bengali quilting method where layered fabrics are bonded through rhythmic parallel needlework.'
) ON CONFLICT (product_slug) DO UPDATE SET
  technique = EXCLUDED.technique,
  technique_label = EXCLUDED.technique_label,
  artisan_hours = EXCLUDED.artisan_hours;

-- Product: Flora Crewel Cashmere Cardigan
INSERT INTO public.products (
  slug, name, subtitle, foreign_tagline, description, category_slug, universe_slug,
  garment_type, gender, motif_id, is_mock, handcrafted, vibes, moods,
  rating, review_count, sold_count, tags, featured, customizable,
  material, care, fit, batch_number, batch_total, craft_region, craft_cluster, fabric_gsm
) VALUES (
  'flora-crewel-cashmere-cardigan',
  'Flora Crewel Cashmere Cardigan',
  'Two-ply Mongolian cashmere with hand crewel wool embroidery',
  'वनस्पति क्रूएल',
  'Ultra-soft 2-ply Mongolian cashmere cardigan framed by raised crewel embroidery in autumnal earth tones, depicting alpine wild roses and lichen mosses.',
  'knitwear',
  'heroverse',
  'cardigan',
  'unisex',
  'guardian-stripes',
  false,
  true,
  ARRAY['pearl', 'aesthetic'],
  ARRAY['comfort', 'heritage'],
  4.9,
  41,
  '180+',
  ARRAY['cardigan', 'cashmere', 'crewel', 'knitwear', 'wool'],
  true,
  true,
  ARRAY['100% Grade-A Mongolian Cashmere', 'Natural Horn Buttons'],
  ARRAY['Hand wash cold with wool shampoo or dry clean'],
  'Relaxed drape, ribbed hem and cuffs',
  6,
  30,
  'Anantnag, Kashmir',
  'Valley Aari Needlecraft Guild',
  '2-Ply 100% Mongolian Cashmere'
) ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  universe_slug = EXCLUDED.universe_slug,
  garment_type = EXCLUDED.garment_type,
  gender = EXCLUDED.gender,
  is_mock = EXCLUDED.is_mock,
  handcrafted = EXCLUDED.handcrafted,
  vibes = EXCLUDED.vibes,
  moods = EXCLUDED.moods;

INSERT INTO public.product_images (product_slug, src, alt, color, sort_order) VALUES
  ('flora-crewel-cashmere-cardigan', '/images/products/crewel-cashmere-cardigan-1.png', 'Flora Crewel Cashmere Cardigan — model shot', '#d9d2c5', 0),
  ('flora-crewel-cashmere-cardigan', '/images/products/crewel-cashmere-cardigan-2.png', 'Flora Crewel Cashmere Cardigan — raised crewel wool relief', '#d9d2c5', 1);

INSERT INTO public.variants (sku, product_slug, color, color_hex, size, price_cents, compare_at_price_cents, status, quantity) VALUES
  ('fcc-oat-s', 'flora-crewel-cashmere-cardigan', 'Oatmeal', '#d9d2c5', 'S', 5727000, NULL, 'in-stock', 10),
  ('fcc-oat-m', 'flora-crewel-cashmere-cardigan', 'Oatmeal', '#d9d2c5', 'M', 5727000, NULL, 'in-stock', 10),
  ('fcc-oat-l', 'flora-crewel-cashmere-cardigan', 'Oatmeal', '#d9d2c5', 'L', 5727000, NULL, 'low-stock', 3),
  ('fcc-chc-s', 'flora-crewel-cashmere-cardigan', 'Charcoal', '#2c2c2e', 'S', 5727000, NULL, 'in-stock', 10),
  ('fcc-chc-m', 'flora-crewel-cashmere-cardigan', 'Charcoal', '#2c2c2e', 'M', 5727000, NULL, 'in-stock', 10)
ON CONFLICT (sku) DO NOTHING;

INSERT INTO public.embroidery_details (
  product_slug, technique, technique_label, artisan_hours, placement, thread_composition, motif_story
) VALUES (
  'flora-crewel-cashmere-cardigan',
  'crewel-needlework',
  'Jacobean Raised Crewel Needlework',
  16,
  ARRAY['Front Placket', 'Left Chest Panel'],
  '2-Ply Appleton Wool Crewel Yarn',
  'Textured wool-on-knit stitchery producing dimensional moss, stem, and petal textures.'
) ON CONFLICT (product_slug) DO UPDATE SET
  technique = EXCLUDED.technique,
  technique_label = EXCLUDED.technique_label,
  artisan_hours = EXCLUDED.artisan_hours;

-- Product: French-Knot Merino Turtleneck
INSERT INTO public.products (
  slug, name, subtitle, foreign_tagline, description, category_slug, universe_slug,
  garment_type, gender, motif_id, is_mock, handcrafted, vibes, moods,
  rating, review_count, sold_count, tags, featured, customizable,
  material, care, fit, batch_number, batch_total, craft_region, craft_cluster, fabric_gsm
) VALUES (
  'french-knot-merino-turtleneck',
  'French-Knot Merino Turtleneck',
  'Extra-fine 19.5 micron merino with tactile beaded stitch constellation',
  'フレンチノット',
  'Seamless knit turtleneck adorned with hundreds of hand-twisted French knots across the yoke, creating a subtle tactile relief reminiscent of morning dew.',
  'knitwear',
  'animeverse',
  'cardigan',
  'unisex',
  'sakura',
  false,
  true,
  ARRAY['clean', 'minimal', 'pearl'],
  ARRAY['comfort', 'everyday'],
  4.8,
  22,
  '95+',
  ARRAY['knitwear', 'merino', 'french-knot', 'sweater'],
  false,
  false,
  ARRAY['100% Extra-Fine Australian Merino Wool'],
  ARRAY['Dry clean or hand wash flat'],
  'Tailored slim fit through shoulders and torso',
  9,
  45,
  'Shimla, Himachal Pradesh',
  'Himalayan Hand-Knit Cluster',
  'Extra-Fine 19.5 Micron Merino Wool'
) ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  universe_slug = EXCLUDED.universe_slug,
  garment_type = EXCLUDED.garment_type,
  gender = EXCLUDED.gender,
  is_mock = EXCLUDED.is_mock,
  handcrafted = EXCLUDED.handcrafted,
  vibes = EXCLUDED.vibes,
  moods = EXCLUDED.moods;

INSERT INTO public.product_images (product_slug, src, alt, color, sort_order) VALUES
  ('french-knot-merino-turtleneck', '/images/products/french-knot-turtleneck-1.jpg', 'French-Knot Merino Turtleneck — studio styling', '#f8f5ee', 0),
  ('french-knot-merino-turtleneck', '/images/products/french-knot-turtleneck-2.jpg', 'French-Knot Merino Turtleneck — macro cluster detail', '#f8f5ee', 1);

INSERT INTO public.variants (sku, product_slug, color, color_hex, size, price_cents, compare_at_price_cents, status, quantity) VALUES
  ('fkm-crm-s', 'french-knot-merino-turtleneck', 'Cream', '#f8f5ee', 'S', 3652000, NULL, 'in-stock', 10),
  ('fkm-crm-m', 'french-knot-merino-turtleneck', 'Cream', '#f8f5ee', 'M', 3652000, NULL, 'in-stock', 10),
  ('fkm-crm-l', 'french-knot-merino-turtleneck', 'Cream', '#f8f5ee', 'L', 3652000, NULL, 'in-stock', 10),
  ('fkm-ter-m', 'french-knot-merino-turtleneck', 'Terracotta', '#c06b52', 'M', 3652000, NULL, 'in-stock', 10)
ON CONFLICT (sku) DO NOTHING;

INSERT INTO public.embroidery_details (
  product_slug, technique, technique_label, artisan_hours, placement, thread_composition, motif_story
) VALUES (
  'french-knot-merino-turtleneck',
  'french-knot',
  'Hand-Wound French Knot Needlecraft',
  12,
  ARRAY['Collar Base', 'Front Shoulder Yoke'],
  'Spun Merino & Fine Silk Yarns',
  'Micro-sculpted spiral knots delivering an organic pebble-grain dimension that catches natural light.'
) ON CONFLICT (product_slug) DO UPDATE SET
  technique = EXCLUDED.technique,
  technique_label = EXCLUDED.technique_label,
  artisan_hours = EXCLUDED.artisan_hours;

-- Product: Atelier Monogram Poplin Shirt
INSERT INTO public.products (
  slug, name, subtitle, foreign_tagline, description, category_slug, universe_slug,
  garment_type, gender, motif_id, is_mock, handcrafted, vibes, moods,
  rating, review_count, sold_count, tags, featured, customizable,
  material, care, fit, batch_number, batch_total, craft_region, craft_cluster, fabric_gsm
) VALUES (
  'atelier-monogram-poplin-shirt',
  'Atelier Monogram Poplin Shirt',
  '120s two-ply Giza Egyptian cotton with personalized crest option',
  'मोनोग्राम शर्ट',
  'An essential tailoring piece cut from crisp Egyptian cotton poplin, engineered with an open placement zone ready for your bespoke monogram or atelier crest.',
  'tops',
  'heroverse',
  'shirt',
  'unisex',
  'ascendant-crest',
  false,
  true,
  ARRAY['clean', 'minimal'],
  ARRAY['everyday', 'statement'],
  4.7,
  52,
  '240+',
  ARRAY['shirt', 'poplin', 'monogram', 'bespoke', 'tops'],
  true,
  true,
  ARRAY['100% Egyptian Giza Cotton Poplin (120/2)'],
  ARRAY['Machine wash warm delicate', 'Medium iron while damp'],
  'Contemporary refined relaxed cut with split back yoke',
  5,
  40,
  'Jaipur, Rajasthan',
  'Pink City Monogram Atelier',
  '140 GSM Supima Cotton Poplin'
) ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  universe_slug = EXCLUDED.universe_slug,
  garment_type = EXCLUDED.garment_type,
  gender = EXCLUDED.gender,
  is_mock = EXCLUDED.is_mock,
  handcrafted = EXCLUDED.handcrafted,
  vibes = EXCLUDED.vibes,
  moods = EXCLUDED.moods;

INSERT INTO public.product_images (product_slug, src, alt, color, sort_order) VALUES
  ('atelier-monogram-poplin-shirt', '/images/products/monogram-poplin-shirt-1.jpg', 'Atelier Monogram Poplin Shirt — clean look', '#ffffff', 0),
  ('atelier-monogram-poplin-shirt', '/images/products/monogram-poplin-shirt-2.jpg', 'Atelier Monogram Poplin Shirt — monogram embroidery detail', '#ffffff', 1);

INSERT INTO public.variants (sku, product_slug, color, color_hex, size, price_cents, compare_at_price_cents, status, quantity) VALUES
  ('amp-wht-38', 'atelier-monogram-poplin-shirt', 'Paper White', '#ffffff', '38', 2656000, NULL, 'in-stock', 10),
  ('amp-wht-40', 'atelier-monogram-poplin-shirt', 'Paper White', '#ffffff', '40', 2656000, NULL, 'in-stock', 10),
  ('amp-wht-42', 'atelier-monogram-poplin-shirt', 'Paper White', '#ffffff', '42', 2656000, NULL, 'in-stock', 10),
  ('amp-sky-40', 'atelier-monogram-poplin-shirt', 'Sky Blue', '#d4e2ed', '40', 2656000, NULL, 'in-stock', 10)
ON CONFLICT (sku) DO NOTHING;

INSERT INTO public.embroidery_details (
  product_slug, technique, technique_label, artisan_hours, placement, thread_composition, motif_story
) VALUES (
  'atelier-monogram-poplin-shirt',
  'monogram-bespoke',
  'Bespoke Atelier Monogram & Crest',
  4,
  ARRAY['Left Chest', 'Left Sleeve Placket', 'Collar Leaf'],
  'Gutterman High-Tenacity Mercerized Cotton',
  'Precision hand-guided satin stitches tailored specifically to each patron''s initials.'
) ON CONFLICT (product_slug) DO UPDATE SET
  technique = EXCLUDED.technique,
  technique_label = EXCLUDED.technique_label,
  artisan_hours = EXCLUDED.artisan_hours;

-- Product: Vine Embroidered Heavyweight Tee
INSERT INTO public.products (
  slug, name, subtitle, foreign_tagline, description, category_slug, universe_slug,
  garment_type, gender, motif_id, is_mock, handcrafted, vibes, moods,
  rating, review_count, sold_count, tags, featured, customizable,
  material, care, fit, batch_number, batch_total, craft_region, craft_cluster, fabric_gsm
) VALUES (
  'vine-embroidered-heavyweight-tee',
  'Vine Embroidered Heavyweight Tee',
  '280 GSM dry-touch jersey with satin-stitch botanical collar',
  'ツタ刺繍',
  'Crafted from custom 280 GSM ringspun cotton jersey with high-density satin-stitch flora entwined along the ribbed neckline and chest pocket.',
  'tops',
  'animeverse',
  'tee',
  'unisex',
  'koi',
  false,
  true,
  ARRAY['aesthetic', 'clean'],
  ARRAY['everyday', 'comfort'],
  4.9,
  68,
  '410+',
  ARRAY['tee', 't-shirt', 'satin-stitch', 'tops', 'heavyweight'],
  false,
  true,
  ARRAY['100% Organic Heavyweight Ringspun Cotton (280 GSM)'],
  ARRAY['Machine wash cold inside out', 'Air dry flat'],
  'Boxy drop-shoulder fit',
  18,
  80,
  'Tiruppur & Lucknow Collaboration',
  'Atelier Essentials Workshop',
  '280 GSM Ringspun Cotton Jersey'
) ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  universe_slug = EXCLUDED.universe_slug,
  garment_type = EXCLUDED.garment_type,
  gender = EXCLUDED.gender,
  is_mock = EXCLUDED.is_mock,
  handcrafted = EXCLUDED.handcrafted,
  vibes = EXCLUDED.vibes,
  moods = EXCLUDED.moods;

INSERT INTO public.product_images (product_slug, src, alt, color, sort_order) VALUES
  ('vine-embroidered-heavyweight-tee', '/images/products/vine-heavyweight-tee-1.jpg', 'Vine Embroidered Heavyweight Tee — studio front', '#e6decb', 0),
  ('vine-embroidered-heavyweight-tee', '/images/products/vine-heavyweight-tee-2.jpg', 'Vine Embroidered Heavyweight Tee — collar embroidery zoom', '#e6decb', 1);

INSERT INTO public.variants (sku, product_slug, color, color_hex, size, price_cents, compare_at_price_cents, status, quantity) VALUES
  ('veh-snd-s', 'vine-embroidered-heavyweight-tee', 'Sand Mineral', '#e6decb', 'S', 1494000, NULL, 'in-stock', 10),
  ('veh-snd-m', 'vine-embroidered-heavyweight-tee', 'Sand Mineral', '#e6decb', 'M', 1494000, NULL, 'in-stock', 10),
  ('veh-snd-l', 'vine-embroidered-heavyweight-tee', 'Sand Mineral', '#e6decb', 'L', 1494000, NULL, 'in-stock', 10),
  ('veh-blk-m', 'vine-embroidered-heavyweight-tee', 'Faded Black', '#2b2a2a', 'M', 1494000, NULL, 'in-stock', 10)
ON CONFLICT (sku) DO NOTHING;

INSERT INTO public.embroidery_details (
  product_slug, technique, technique_label, artisan_hours, placement, thread_composition, motif_story
) VALUES (
  'vine-embroidered-heavyweight-tee',
  'satin-stitch',
  'High-Density Satin Stitching',
  6,
  ARRAY['Neckline Rib', 'Chest Pocket Hem'],
  'Mercerized Organic Cotton Thread',
  'Contoured botanicals drafted with seamless stitch tension to preserve garment stretch.'
) ON CONFLICT (product_slug) DO UPDATE SET
  technique = EXCLUDED.technique,
  technique_label = EXCLUDED.technique_label,
  artisan_hours = EXCLUDED.artisan_hours;

-- Product: Selvedge Sashiko Embroidered Denim
INSERT INTO public.products (
  slug, name, subtitle, foreign_tagline, description, category_slug, universe_slug,
  garment_type, gender, motif_id, is_mock, handcrafted, vibes, moods,
  rating, review_count, sold_count, tags, featured, customizable,
  material, care, fit, batch_number, batch_total, craft_region, craft_cluster, fabric_gsm
) VALUES (
  'selvedge-sashiko-embroidered-denim',
  'Selvedge Sashiko Embroidered Denim',
  '14oz Japanese redline selvedge with traditional sashiko geometry',
  '刺し子デニム',
  'Woven on vintage Toyoda shuttle looms in Okayama and finished with geometric Sashiko stitching across the front thighs and back yoke for enhanced structural resilience.',
  'bottoms',
  'animeverse',
  'pants',
  'unisex',
  'red-sun',
  false,
  true,
  ARRAY['expressive', 'noir'],
  ARRAY['collector', 'statement'],
  5,
  44,
  '190+',
  ARRAY['denim', 'sashiko', 'selvedge', 'jeans', 'bottoms'],
  true,
  false,
  ARRAY['14oz Okayama Cotton Selvedge Denim', 'Solid Brass Hardware'],
  ARRAY['Wash infrequently in cold water', 'Hang dry'],
  'Straight leg, medium rise',
  11,
  50,
  'Kutch & Okayama Craft Hub',
  'Indigo Needlecraft Guild',
  '14oz Redline Selvedge Denim'
) ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  universe_slug = EXCLUDED.universe_slug,
  garment_type = EXCLUDED.garment_type,
  gender = EXCLUDED.gender,
  is_mock = EXCLUDED.is_mock,
  handcrafted = EXCLUDED.handcrafted,
  vibes = EXCLUDED.vibes,
  moods = EXCLUDED.moods;

INSERT INTO public.product_images (product_slug, src, alt, color, sort_order) VALUES
  ('selvedge-sashiko-embroidered-denim', '/images/products/sashiko-selvedge-denim-1.jpg', 'Selvedge Sashiko Embroidered Denim — front profile', '#152238', 0),
  ('selvedge-sashiko-embroidered-denim', '/images/products/sashiko-selvedge-denim-2.jpg', 'Selvedge Sashiko Embroidered Denim — macro white sashiko stitching', '#152238', 1);

INSERT INTO public.variants (sku, product_slug, color, color_hex, size, price_cents, compare_at_price_cents, status, quantity) VALUES
  ('ssd-raw-30', 'selvedge-sashiko-embroidered-denim', 'Raw Indigo', '#152238', '30', 4316000, NULL, 'in-stock', 10),
  ('ssd-raw-32', 'selvedge-sashiko-embroidered-denim', 'Raw Indigo', '#152238', '32', 4316000, NULL, 'in-stock', 10),
  ('ssd-raw-34', 'selvedge-sashiko-embroidered-denim', 'Raw Indigo', '#152238', '34', 4316000, NULL, 'low-stock', 1)
ON CONFLICT (sku) DO NOTHING;

INSERT INTO public.embroidery_details (
  product_slug, technique, technique_label, artisan_hours, placement, thread_composition, motif_story
) VALUES (
  'selvedge-sashiko-embroidered-denim',
  'sashiko-selvedge',
  'Japanese Traditional Sashiko Reinforcement',
  14,
  ARRAY['Right Thigh', 'Left Knee', 'Back Pockets'],
  'Heavy Unwaxed Sashiko Cotton Cord',
  'Ancestral rice-grain stitch motifs originally conceived to reinforce worker clothing against wear.'
) ON CONFLICT (product_slug) DO UPDATE SET
  technique = EXCLUDED.technique,
  technique_label = EXCLUDED.technique_label,
  artisan_hours = EXCLUDED.artisan_hours;

-- Product: Pleated Silk-Zari Wool Trousers
INSERT INTO public.products (
  slug, name, subtitle, foreign_tagline, description, category_slug, universe_slug,
  garment_type, gender, motif_id, is_mock, handcrafted, vibes, moods,
  rating, review_count, sold_count, tags, featured, customizable,
  material, care, fit, batch_number, batch_total, craft_region, craft_cluster, fabric_gsm
) VALUES (
  'pleated-silk-zari-wool-trousers',
  'Pleated Silk-Zari Wool Trousers',
  'Italian wool-mohair blend with fine metallic thread side-stripe',
  'ज़री पतलून',
  'Double-pleated tailored trousers featuring an artisanal side-seam galon hand-embroidered in antique copper and gold metallic zari floss.',
  'bottoms',
  'itihaas',
  'pants',
  'unisex',
  'arch-jaal',
  false,
  true,
  ARRAY['gilded', 'clean'],
  ARRAY['festive-gifting', 'statement'],
  4.8,
  16,
  '70+',
  ARRAY['trousers', 'wool', 'zari', 'tailoring', 'bottoms'],
  false,
  false,
  ARRAY['85% Virgin Wool, 15% Mohair', 'Cupro Knee Lining'],
  ARRAY['Dry clean only'],
  'High-rise relaxed taper with crisp front crease',
  5,
  40,
  'Varanasi, Uttar Pradesh',
  'Ghat Zari Weavers Collective',
  '210 GSM Silk-Zari Wool Twill'
) ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  universe_slug = EXCLUDED.universe_slug,
  garment_type = EXCLUDED.garment_type,
  gender = EXCLUDED.gender,
  is_mock = EXCLUDED.is_mock,
  handcrafted = EXCLUDED.handcrafted,
  vibes = EXCLUDED.vibes,
  moods = EXCLUDED.moods;

INSERT INTO public.product_images (product_slug, src, alt, color, sort_order) VALUES
  ('pleated-silk-zari-wool-trousers', '/images/products/pleated-zari-trousers-1.jpg', 'Pleated Silk-Zari Wool Trousers — drape and cut', '#393e36', 0),
  ('pleated-silk-zari-wool-trousers', '/images/products/pleated-zari-trousers-2.jpg', 'Pleated Silk-Zari Wool Trousers — metallic stripe needlecraft detail', '#393e36', 1);

INSERT INTO public.variants (sku, product_slug, color, color_hex, size, price_cents, compare_at_price_cents, status, quantity) VALUES
  ('pzt-olv-46', 'pleated-silk-zari-wool-trousers', 'Deep Olive', '#393e36', '46', 3984000, NULL, 'in-stock', 10),
  ('pzt-olv-48', 'pleated-silk-zari-wool-trousers', 'Deep Olive', '#393e36', '48', 3984000, NULL, 'in-stock', 10),
  ('pzt-olv-50', 'pleated-silk-zari-wool-trousers', 'Deep Olive', '#393e36', '50', 3984000, NULL, 'in-stock', 10)
ON CONFLICT (sku) DO NOTHING;

INSERT INTO public.embroidery_details (
  product_slug, technique, technique_label, artisan_hours, placement, thread_composition, motif_story
) VALUES (
  'pleated-silk-zari-wool-trousers',
  'metallic-zari',
  'Metallic Zari Thread Inlay',
  10,
  ARRAY['Outer Side Seams', 'Ticket Pocket Rim'],
  'Copper & Silver Core Metallic Zari',
  'A modern homage to ceremonial livery stripes, hand-laid with continuous lustrous cords.'
) ON CONFLICT (product_slug) DO UPDATE SET
  technique = EXCLUDED.technique,
  technique_label = EXCLUDED.technique_label,
  artisan_hours = EXCLUDED.artisan_hours;

-- Product: Heritage Flora Embroidered Silk Scarf
INSERT INTO public.products (
  slug, name, subtitle, foreign_tagline, description, category_slug, universe_slug,
  garment_type, gender, motif_id, is_mock, handcrafted, vibes, moods,
  rating, review_count, sold_count, tags, featured, customizable,
  material, care, fit, batch_number, batch_total, craft_region, craft_cluster, fabric_gsm
) VALUES (
  'heritage-flora-embroidered-silk-scarf',
  'Heritage Flora Embroidered Silk Scarf',
  'Pure mulberry silk twill with hand-rolled edges and hand embroidery',
  'रेशमी दुपट्टा',
  'A square 90x90cm luxury silk twill foulard detailed with intricate botanical flora along each corner quadrant, hand-embroidered with shaded satin stitch needlework.',
  'accessories',
  'itihaas',
  'scarf',
  'unisex',
  'procession-elephant',
  false,
  true,
  ARRAY['pearl', 'gilded'],
  ARRAY['festive-gifting', 'collector'],
  4.9,
  38,
  '160+',
  ARRAY['scarf', 'silk', 'satin-stitch', 'accessories'],
  false,
  true,
  ARRAY['100% Mulberry Silk Twill (18mm)', 'Hand-Rolled Hem'],
  ARRAY['Dry clean only', 'Cool iron with pressing cloth'],
  '90cm x 90cm square scarf',
  5,
  40,
  'Murshidabad, West Bengal',
  'Shantiniketan Silk Guild',
  '18 Momme Mulberry Silk Twill'
) ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  universe_slug = EXCLUDED.universe_slug,
  garment_type = EXCLUDED.garment_type,
  gender = EXCLUDED.gender,
  is_mock = EXCLUDED.is_mock,
  handcrafted = EXCLUDED.handcrafted,
  vibes = EXCLUDED.vibes,
  moods = EXCLUDED.moods;

INSERT INTO public.product_images (product_slug, src, alt, color, sort_order) VALUES
  ('heritage-flora-embroidered-silk-scarf', '/images/products/embroidered-silk-scarf-1.png', 'Heritage Flora Embroidered Silk Scarf — folded styling', '#e5ded3', 0),
  ('heritage-flora-embroidered-silk-scarf', '/images/products/embroidered-silk-scarf-2.jpg', 'Heritage Flora Embroidered Silk Scarf — satin stitch corner embroidery', '#e5ded3', 1);

INSERT INTO public.variants (sku, product_slug, color, color_hex, size, price_cents, compare_at_price_cents, status, quantity) VALUES
  ('hfs-bge-os', 'heritage-flora-embroidered-silk-scarf', 'Oat Beige', '#e5ded3', 'OS', 2158000, NULL, 'in-stock', 10),
  ('hfs-ter-os', 'heritage-flora-embroidered-silk-scarf', 'Terracotta', '#c06b52', 'OS', 2158000, NULL, 'in-stock', 10)
ON CONFLICT (sku) DO NOTHING;

INSERT INTO public.embroidery_details (
  product_slug, technique, technique_label, artisan_hours, placement, thread_composition, motif_story
) VALUES (
  'heritage-flora-embroidered-silk-scarf',
  'satin-stitch',
  'Fine Shaded Silk Satin Stitch',
  15,
  ARRAY['Four Corner Medallions'],
  '100% Unspun Raw Silk Floss',
  'Delicate color-gradient needle shading capturing the translucency of alpine blossoms.'
) ON CONFLICT (product_slug) DO UPDATE SET
  technique = EXCLUDED.technique,
  technique_label = EXCLUDED.technique_label,
  artisan_hours = EXCLUDED.artisan_hours;

-- Product: Artisanal Needlework Canvas Tote
INSERT INTO public.products (
  slug, name, subtitle, foreign_tagline, description, category_slug, universe_slug,
  garment_type, gender, motif_id, is_mock, handcrafted, vibes, moods,
  rating, review_count, sold_count, tags, featured, customizable,
  material, care, fit, batch_number, batch_total, craft_region, craft_cluster, fabric_gsm
) VALUES (
  'artisanal-needlework-canvas-tote',
  'Artisanal Needlework Canvas Tote',
  '20oz heavyweight organic cotton duck with monogram patch',
  'कैनवास बैग',
  'Architectural carryall constructed from indestructible 20oz duck canvas, finished with reinforced bridle leather straps and a bespoke chain-stitched atelier crest.',
  'accessories',
  'heroverse',
  'tote',
  'unisex',
  'guardian-stripes',
  false,
  true,
  ARRAY['clean', 'minimal'],
  ARRAY['everyday', 'collector'],
  4.7,
  29,
  '130+',
  ARRAY['tote', 'bag', 'canvas', 'accessories', 'monogram'],
  false,
  true,
  ARRAY['20oz Organic Duck Canvas', 'Vegetable-Tanned Bridle Leather'],
  ARRAY['Spot clean with mild soap and soft brush'],
  '38cm W x 42cm H x 14cm D',
  22,
  90,
  'Ahmedabad, Gujarat',
  'Sabarmati Heavy Duck Canvas Guild',
  '450 GSM Heavy Unbleached Cotton Duck'
) ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  universe_slug = EXCLUDED.universe_slug,
  garment_type = EXCLUDED.garment_type,
  gender = EXCLUDED.gender,
  is_mock = EXCLUDED.is_mock,
  handcrafted = EXCLUDED.handcrafted,
  vibes = EXCLUDED.vibes,
  moods = EXCLUDED.moods;

INSERT INTO public.product_images (product_slug, src, alt, color, sort_order) VALUES
  ('artisanal-needlework-canvas-tote', '/images/products/needlework-canvas-tote-1.jpg', 'Artisanal Needlework Canvas Tote — side-profile', '#eae5da', 0),
  ('artisanal-needlework-canvas-tote', '/images/products/needlework-canvas-tote-2.jpg', 'Artisanal Needlework Canvas Tote — handle needlepoint reinforcement', '#eae5da', 1);

INSERT INTO public.variants (sku, product_slug, color, color_hex, size, price_cents, compare_at_price_cents, status, quantity) VALUES
  ('act-nat-os', 'artisanal-needlework-canvas-tote', 'Natural Canvas', '#eae5da', 'OS', 1743000, NULL, 'in-stock', 10),
  ('act-blk-os', 'artisanal-needlework-canvas-tote', 'Coal', '#1f1e1d', 'OS', 1743000, NULL, 'in-stock', 10)
ON CONFLICT (sku) DO NOTHING;

INSERT INTO public.embroidery_details (
  product_slug, technique, technique_label, artisan_hours, placement, thread_composition, motif_story
) VALUES (
  'artisanal-needlework-canvas-tote',
  'monogram-bespoke',
  'Heavy Guage Monogram & Chain Stitch',
  5,
  ARRAY['Front Pocket Panel'],
  'Bonded Heavy Marine Cotton Cord',
  'High-tension needlework tailored to withstand daily urban travel and heavy carry loads.'
) ON CONFLICT (product_slug) DO UPDATE SET
  technique = EXCLUDED.technique,
  technique_label = EXCLUDED.technique_label,
  artisan_hours = EXCLUDED.artisan_hours;

-- Product: Nocturne Velvet Crewel Waistcoat
INSERT INTO public.products (
  slug, name, subtitle, foreign_tagline, description, category_slug, universe_slug,
  garment_type, gender, motif_id, is_mock, handcrafted, vibes, moods,
  rating, review_count, sold_count, tags, featured, customizable,
  material, care, fit, batch_number, batch_total, craft_region, craft_cluster, fabric_gsm
) VALUES (
  'nocturne-velvet-crewel-vest',
  'Nocturne Velvet Crewel Waistcoat',
  'Deep cotton-silk velvet with metallic zari botanical embroidery',
  'मखमली वास्कट',
  'Tailored vest crafted from midnight cotton-silk velvet, accented with botanical flora worked in antique gold zari and crewel needlework along the vest front.',
  'tops',
  'heroverse',
  'vest',
  'unisex',
  'ascendant-crest',
  false,
  true,
  ARRAY['noir', 'gilded'],
  ARRAY['statement', 'festive-gifting'],
  4.9,
  15,
  '60+',
  ARRAY['vest', 'velvet', 'zari', 'crewel', 'tops'],
  false,
  false,
  ARRAY['Cotton-Silk Velvet', 'Mother-of-Pearl Buttons'],
  ARRAY['Dry clean only'],
  'Tailored waistcoat cut with adjustable cinch back',
  5,
  40,
  'Srinagar, Kashmir',
  'Valley Aari Craftspersons',
  '320 GSM Cotton Velvet'
) ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  universe_slug = EXCLUDED.universe_slug,
  garment_type = EXCLUDED.garment_type,
  gender = EXCLUDED.gender,
  is_mock = EXCLUDED.is_mock,
  handcrafted = EXCLUDED.handcrafted,
  vibes = EXCLUDED.vibes,
  moods = EXCLUDED.moods;

INSERT INTO public.product_images (product_slug, src, alt, color, sort_order) VALUES
  ('nocturne-velvet-crewel-vest', '/images/products/nocturne-velvet-vest-1.jpg', 'Nocturne Velvet Crewel Waistcoat — front view', '#141416', 0),
  ('nocturne-velvet-crewel-vest', '/images/products/nocturne-velvet-vest-2.jpg', 'Nocturne Velvet Crewel Waistcoat — metallic thread detail on velvet', '#141416', 1);

INSERT INTO public.variants (sku, product_slug, color, color_hex, size, price_cents, compare_at_price_cents, status, quantity) VALUES
  ('nvv-mid-s', 'nocturne-velvet-crewel-vest', 'Midnight Black', '#141416', 'S', 3818000, NULL, 'in-stock', 10),
  ('nvv-mid-m', 'nocturne-velvet-crewel-vest', 'Midnight Black', '#141416', 'M', 3818000, NULL, 'in-stock', 10),
  ('nvv-mid-l', 'nocturne-velvet-crewel-vest', 'Midnight Black', '#141416', 'L', 3818000, NULL, 'low-stock', 2)
ON CONFLICT (sku) DO NOTHING;

INSERT INTO public.embroidery_details (
  product_slug, technique, technique_label, artisan_hours, placement, thread_composition, motif_story
) VALUES (
  'nocturne-velvet-crewel-vest',
  'metallic-zari',
  'Zari Wire & Fine Silk Relief',
  20,
  ARRAY['Front Lapel Borders', 'Pocket Welts'],
  'Genuine Metallic Thread & Mulberry Silk',
  'Glimmering needlework tailored against the deep light-absorbing pile of velvet.'
) ON CONFLICT (product_slug) DO UPDATE SET
  technique = EXCLUDED.technique,
  technique_label = EXCLUDED.technique_label,
  artisan_hours = EXCLUDED.artisan_hours;

-- Product: Royal Aari Organic Cotton Tee
INSERT INTO public.products (
  slug, name, subtitle, foreign_tagline, description, category_slug, universe_slug,
  garment_type, gender, motif_id, is_mock, handcrafted, vibes, moods,
  rating, review_count, sold_count, tags, featured, customizable,
  material, care, fit, batch_number, batch_total, craft_region, craft_cluster, fabric_gsm
) VALUES (
  'royal-aari-organic-tee',
  'Royal Aari Organic Cotton Tee',
  '280 GSM heavyweight jersey with hand-hooked chain-stitch crest',
  'शाही आरी टी',
  'Cut from custom 280 GSM combed organic cotton jersey, finished with hand-hooked Kashmiri Aari floral needlework on the chest pocket.',
  'tops',
  'itihaas',
  'tee',
  'unisex',
  'arch-jaal',
  false,
  true,
  ARRAY['clean', 'aesthetic'],
  ARRAY['everyday', 'heritage'],
  4.9,
  85,
  '520+',
  ARRAY['tee', 't-shirt', 'aari', 'tops', 'organic', 'heavyweight'],
  true,
  true,
  ARRAY['100% GOTS Organic Cotton Jersey (280 GSM)', 'Mercerized Cotton Embroidery Floss'],
  ARRAY['Machine wash gentle cold (30°C) inside out', 'Line dry in shade', 'Do not iron directly on embroidery'],
  'Boxy atelier drop-shoulder fit, true to size',
  14,
  60,
  'Srinagar, Jammu & Kashmir',
  'Valley Aari Needlecraft Guild',
  '280 GSM Ringspun Combed Cotton'
) ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  universe_slug = EXCLUDED.universe_slug,
  garment_type = EXCLUDED.garment_type,
  gender = EXCLUDED.gender,
  is_mock = EXCLUDED.is_mock,
  handcrafted = EXCLUDED.handcrafted,
  vibes = EXCLUDED.vibes,
  moods = EXCLUDED.moods;

INSERT INTO public.product_images (product_slug, src, alt, color, sort_order) VALUES
  ('royal-aari-organic-tee', '/images/products/botanical-silk-jacket-1.png', 'Royal Aari Organic Cotton Tee — front silhouette', '#18181b', 0),
  ('royal-aari-organic-tee', '/images/products/botanical-silk-jacket-1.png', 'Royal Aari Organic Cotton Tee — macro Aari stitch detail', '#18181b', 1);

INSERT INTO public.variants (sku, product_slug, color, color_hex, size, price_cents, compare_at_price_cents, status, quantity) VALUES
  ('rot-blk-s', 'royal-aari-organic-tee', 'Washed Black', '#18181b', 'S', 3154000, NULL, 'in-stock', 10),
  ('rot-blk-m', 'royal-aari-organic-tee', 'Washed Black', '#18181b', 'M', 3154000, NULL, 'in-stock', 10),
  ('rot-blk-l', 'royal-aari-organic-tee', 'Washed Black', '#18181b', 'L', 3154000, NULL, 'low-stock', 3),
  ('rot-ecr-m', 'royal-aari-organic-tee', 'Natural Ecru', '#f4efe6', 'M', 3154000, NULL, 'in-stock', 10)
ON CONFLICT (sku) DO NOTHING;

INSERT INTO public.embroidery_details (
  product_slug, technique, technique_label, artisan_hours, placement, thread_composition, motif_story
) VALUES (
  'royal-aari-organic-tee',
  'botanical-chain',
  'Kashmiri Hand-Hooked Aari Chain Stitch',
  8,
  ARRAY['Chest Pocket', 'Back Collar Yoke'],
  '100% Mercerized Egyptian Cotton Thread',
  'Traditional Chinar leaf geometry reinterpreted into a modern minimalist pocket motif.'
) ON CONFLICT (product_slug) DO UPDATE SET
  technique = EXCLUDED.technique,
  technique_label = EXCLUDED.technique_label,
  artisan_hours = EXCLUDED.artisan_hours;

