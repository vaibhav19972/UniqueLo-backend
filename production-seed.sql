-- ====================================================================
-- production-seed.sql — GENERATED FILE, DO NOT EDIT BY HAND
--
-- Regenerate:  node backend/scripts/gen-seed.mjs
-- Verify:      node backend/scripts/gen-seed.mjs --check
--
-- Source:       web/src/data/mock-products.json
-- Products:     3
-- Variants:     25
-- Price range:  Rs 1899 - Rs 3599
-- Median var.:  Rs 3499
--
-- Replaces the previous hand-maintained seed, which carried 2 of 13 products
-- and priced the hoodie at Rs 8,990 against a catalog price of Rs 3,499.
-- ====================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Master taxonomy
-- ---------------------------------------------------------------------------

insert into public.universes (
  slug, name, tagline, lore, emblem_src, hero_image, drop_cadence, is_active,
  order_num, theme_tokens, portal_title_color, lore_heading, hero_headline_case,
  hero_vertical_text
) values
  ('animeverse', 'Animeverse', 'Icons. Emotions. Forever.', 'Beloved worlds, reimagined in threads. Embroidered apparel inspired by the stories that shaped a generation — from timeless classics to modern legends.', '/images/categories/tops.jpg', '/images/campaigns/hero-animeverse.jpg', 'Seasonal arcs + monthly mini-drops', true, 1, '{"bg":"#10131f","surface":"#191f36","ink":"#f4efe6","accent":"#e9b9cd","accent2":"#86d3e6","product_zone":"#f7f5f0","divider":"sakura-petal","card_frame":"torii","texture_opacity":0.06,"display_font":"condensed-bold"}'::jsonb, '#7a1f23', 'More Than Characters.', 'caps', '物語は、永遠に着られる。'),
  ('heroverse', 'Heroverse', 'Courage lives differently here.', 'Legends, icons and everyday heroes stitched to inspire. Cosmic-scale embroidery for those who carry their own weight — and then some.', '/images/categories/outerwear.jpg', '/images/campaigns/hero-heroverse.jpg', 'Monthly New-Issue drops', true, 2, '{"bg":"#131316","surface":"#1d161a","ink":"#f5f0e8","accent":"#c0392b","accent2":"#d4af37","product_zone":"#faf6ee","divider":"action-lines","card_frame":"badge","texture_opacity":0.06,"display_font":"extra-bold-italic"}'::jsonb, '#a8862f', 'Icons Are Ideas.', 'sentence', NULL),
  ('itihaas', 'Itihaas', 'Our history. Always relevant.', 'Moments, empires and folk stories in contemporary forms. Royal Indian craft lineages — processions, arches, jaals — embroidered for the everyday wardrobe.', '/images/categories/knitwear.jpg', '/images/campaigns/hero-itihaas.jpg', 'Festive darbar collections', true, 3, '{"bg":"#f7f3ea","surface":"#eee7d9","ink":"#2e241a","accent":"#6d1f2c","accent2":"#0e6a63","product_zone":"#faf8f5","divider":"mughal-arch","card_frame":"arch","texture_opacity":0.05,"display_font":"elegant-serif"}'::jsonb, '#6d1f2c', 'Symbols That Shaped Us.', 'sentence', 'अतीत से प्रेरणा वर्तमान के लिए।')
on conflict (slug) do update set name = excluded.name, tagline = excluded.tagline, lore = excluded.lore, emblem_src = excluded.emblem_src, hero_image = excluded.hero_image, drop_cadence = excluded.drop_cadence, is_active = excluded.is_active, order_num = excluded.order_num, theme_tokens = excluded.theme_tokens, portal_title_color = excluded.portal_title_color, lore_heading = excluded.lore_heading, hero_headline_case = excluded.hero_headline_case, hero_vertical_text = excluded.hero_vertical_text;

insert into public.categories (slug, name, label, description, image, order_num) values
  ('all', 'All Collections', 'All', 'The complete atelier edit spanning artisanal embroidery, heirloom tailoring, and pure natural yarns.', NULL, 0),
  ('outerwear', 'Outerwear', 'Outerwear', 'Tailored chore jackets, kimono overcoats, and embroidered denim outerwear.', '/images/categories/outerwear.jpg', 1),
  ('knitwear', 'Knitwear', 'Knitwear', 'Pure cashmere cardigans, merino sweaters, and chain-stitched crewnecks.', '/images/categories/knitwear.jpg', 2),
  ('tops', 'Tops & Shirts', 'Tops', 'Heavyweight organic cotton box tees, silk-floss oxfords, and band-collar tunics.', '/images/categories/tops.jpg', 3),
  ('bottoms', 'Bottoms', 'Bottoms', 'Pleated wide-leg trousers, raw selvedge denim, and kantha-embroidered work pants.', '/images/categories/bottoms.jpg', 4),
  ('accessories', 'Accessories', 'Accessories', 'Embroidered silk scarves, raw canvas tote bags, and heirloom monogram badges.', '/images/categories/accessories.jpg', 5)
on conflict (slug) do update set name = excluded.name, label = excluded.label, description = excluded.description, image = excluded.image, order_num = excluded.order_num;

insert into public.garments (slug, name, category_slug, description, order_num) values
  ('hoodie', 'Hoodies', 'tops', 'Heavyweight fleece hoodies with back-panel and crest embroidery.', 1),
  ('tee', 'Tees', 'tops', 'Combed-cotton tees carrying chest and back threadwork.', 2),
  ('shirt', 'Shirts', 'tops', 'Oxfords, poplins and band-collar tunics with monogram detail.', 3),
  ('jacket', 'Jackets', 'outerwear', 'Chore jackets, capes and overcoats with procession-scale embroidery.', 4),
  ('cardigan', 'Cardigans', 'knitwear', 'Cashmere cardigans with crewel relief.', 5),
  ('vest', 'Vests', 'knitwear', 'Knit vests with sculpted knot texture.', 6),
  ('pants', 'Pants', 'bottoms', 'Selvedge denim and work pants with structural stitching.', 7),
  ('scarf', 'Scarves', 'accessories', 'Silk scarves with arch-jaal and flora borders.', 8),
  ('tote', 'Totes', 'accessories', 'Raw-canvas totes with sun-disc and motif hits.', 9)
on conflict (slug) do update set name = excluded.name, category_slug = excluded.category_slug, description = excluded.description, order_num = excluded.order_num;

insert into public.collections (slug, name, tagline, description, universe_slug, featured, order_num) values
  ('spring-sakura', 'Spring Sakura Collection', 'Japanese woodblock waves, blossom scatter, ink-line calm.', 'Inspired by spring in the floating world — flat sun discs, wave curls, and floating cherry blossom embroidery across heavyweight fleece, combed cotton, and raw canvas.', 'animeverse', true, 1),
  ('royal-heritage', 'Royal Heritage Collection', 'Arches, jaals and royal court processions in gold zardozi.', 'Arch lattices, elephant processions, and intricate jaal geometry drawn from royal court lineages, rendered in metallic zari, raw silk, and fine needlework.', 'itihaas', true, 2),
  ('midnight-atelier', 'Midnight Atelier Collection', 'No world, just pure cloth, heroic crests, and tonal needlecraft.', 'Universe-neutral and nocturnal luxury pieces — sashiko grids, crewel relief, comic noir geometry, and understated crest detailing on heavyweight unbleached and charcoal yarns.', NULL, true, 3)
on conflict (slug) do update set name = excluded.name, tagline = excluded.tagline, description = excluded.description, universe_slug = excluded.universe_slug, featured = excluded.featured, order_num = excluded.order_num;

insert into public.motifs (id, universe_slug, name, meaning, symbol_notes, ip_cleared) values
  ('red-sun', 'animeverse', 'The Red Sun', 'A symbol of hope, resilience and new beginnings.', 'Flat crimson disc, minimal, pairs with mountain/wave linework.', true),
  ('koi', 'animeverse', 'The Koi', 'Perseverance through every current.', 'Swimming koi with wave curls, dynamic diagonal flow.', true),
  ('sakura', 'animeverse', 'Sakura', 'Beauty in impermanence, strength in renewal.', 'Five-petal blossoms on bare branches, scattered petals.', true),
  ('ascendant-crest', 'heroverse', 'The Ascendant Crest', 'Rise, carry, protect — the everyday hero''s mark.', 'Bold shield-crest geometry, gold on deep red.', true),
  ('guardian-stripes', 'heroverse', 'Guardian Stripes', 'Speed lines of those who show up first.', 'Diagonal action-line bands, navy and burst yellow.', true),
  ('procession-elephant', 'itihaas', 'The Royal Procession', 'Ceremony, memory and rightful pride.', 'Caparisoned elephant with arch-and-jaal backdrop.', true),
  ('arch-jaal', 'itihaas', 'Arch Jaal', 'Courtyards of patience — geometry as devotion.', 'Mughal arch lattice, symmetric, gold on maroon.', true)
on conflict (id) do update set universe_slug = excluded.universe_slug, name = excluded.name, meaning = excluded.meaning, symbol_notes = excluded.symbol_notes, ip_cleared = excluded.ip_cleared;

-- ---------------------------------------------------------------------------
-- 2. Products
-- ---------------------------------------------------------------------------

-- Sakura Ronin Hoodie  (animeverse · tops/hoodie)
insert into public.products (
  slug,
  name,
  subtitle,
  foreign_tagline,
  description,
  category_slug,
  universe_slug,
  collection_slug,
  garment_type,
  gender,
  motif_id,
  handcrafted,
  craft_techniques,
  edits,
  expression_score,
  rating,
  review_count,
  tags,
  featured,
  customizable,
  material,
  care,
  fit,
  fabric_gsm,
  country_of_origin,
  manufacturer_name,
  manufacturer_address,
  packed_by,
  cod_available,
  delivery_days_min,
  delivery_days_max,
  return_window_days,
  weight_grams,
  hsn_code,
  size_chart
) values (
  'sakura-ronin-hoodie',
  'Sakura Ronin Hoodie',
  'A lone journey, a blossoming hope.',
  '桜の浪人',
  'Oversized hoodie carrying the Sakura Ronin — a wandering swordsman beneath falling cherry blossoms. Embroidered zardozi and layered threadwork across the back panel.',
  'tops',
  'animeverse',
  'spring-sakura',
  'hoodie',
  'unisex',
  'sakura',
  true,
  ARRAY['hand-zardozi'],
  ARRAY['statement', 'everyday'],
  5,
  4.8,
  320,
  ARRAY['animeverse', 'hoodie', 'unisex', 'bestseller'],
  true,
  false,
  ARRAY['400 GSM cotton fleece', 'Brass drawcord tips'],
  '{}',
  'Oversized Fit',
  '380 GSM',
  'IN',
  NULL,
  NULL,
  NULL,
  true,
  5,
  7,
  7,
  650,
  '6109',
  '{"S":{"chest":100,"length":66},"M":{"chest":105,"length":68},"L":{"chest":110,"length":70},"XL":{"chest":115,"length":72}}'::jsonb
) on conflict (slug) do update set
  name = excluded.name,
  subtitle = excluded.subtitle,
  foreign_tagline = excluded.foreign_tagline,
  description = excluded.description,
  category_slug = excluded.category_slug,
  universe_slug = excluded.universe_slug,
  collection_slug = excluded.collection_slug,
  garment_type = excluded.garment_type,
  gender = excluded.gender,
  motif_id = excluded.motif_id,
  handcrafted = excluded.handcrafted,
  craft_techniques = excluded.craft_techniques,
  edits = excluded.edits,
  expression_score = excluded.expression_score,
  rating = excluded.rating,
  review_count = excluded.review_count,
  tags = excluded.tags,
  featured = excluded.featured,
  customizable = excluded.customizable,
  material = excluded.material,
  care = excluded.care,
  fit = excluded.fit,
  fabric_gsm = excluded.fabric_gsm,
  country_of_origin = excluded.country_of_origin,
  manufacturer_name = excluded.manufacturer_name,
  manufacturer_address = excluded.manufacturer_address,
  packed_by = excluded.packed_by,
  cod_available = excluded.cod_available,
  delivery_days_min = excluded.delivery_days_min,
  delivery_days_max = excluded.delivery_days_max,
  return_window_days = excluded.return_window_days,
  weight_grams = excluded.weight_grams,
  hsn_code = excluded.hsn_code,
  size_chart = excluded.size_chart;

delete from public.product_images where product_slug = 'sakura-ronin-hoodie';
insert into public.product_images (product_slug, src, alt, color, sort_order) values
  ('sakura-ronin-hoodie', '/images/products/sakura-ronin-hoodie-1.jpg', 'Sakura Ronin Hoodie — front', NULL, 0),
  ('sakura-ronin-hoodie', '/images/products/sakura-ronin-hoodie-2.jpg', 'Sakura Ronin Hoodie — back panel embroidery', NULL, 1),
  ('sakura-ronin-hoodie', '/images/products/sakura-ronin-hoodie-3.jpg', 'Sakura Ronin Hoodie — stitch detail', NULL, 2),
  ('sakura-ronin-hoodie', '/images/products/sakura-ronin-hoodie-4.jpg', 'Sakura Ronin Hoodie — lifestyle', NULL, 3),
  ('sakura-ronin-hoodie', '/images/products/sakura-ronin-hoodie-5.jpg', 'Sakura Ronin Hoodie — collar detail', NULL, 4),
  ('sakura-ronin-hoodie', '/images/products/sakura-ronin-hoodie-6.jpg', 'Sakura Ronin Hoodie — lifestyle shot', NULL, 5);

delete from public.variants where product_slug = 'sakura-ronin-hoodie';
insert into public.variants (sku, product_slug, color, color_hex, size, price_cents, compare_at_price_cents, status, quantity) values
  ('SRH-WARM-XS', 'sakura-ronin-hoodie', 'Warm Ivory', '#f3ede2', 'XS', 349900, NULL, 'in-stock', 14),
  ('SRH-WARM-S', 'sakura-ronin-hoodie', 'Warm Ivory', '#f3ede2', 'S', 349900, NULL, 'in-stock', 14),
  ('SRH-WARM-M', 'sakura-ronin-hoodie', 'Warm Ivory', '#f3ede2', 'M', 349900, NULL, 'low-stock', 2),
  ('SRH-WARM-L', 'sakura-ronin-hoodie', 'Warm Ivory', '#f3ede2', 'L', 349900, NULL, 'in-stock', 14),
  ('SRH-WARM-XL', 'sakura-ronin-hoodie', 'Warm Ivory', '#f3ede2', 'XL', 349900, NULL, 'in-stock', 14),
  ('SRH-WARM-2XL', 'sakura-ronin-hoodie', 'Warm Ivory', '#f3ede2', '2XL', 349900, NULL, 'in-stock', 14),
  ('SRH-WARM-3XL', 'sakura-ronin-hoodie', 'Warm Ivory', '#f3ede2', '3XL', 349900, NULL, 'low-stock', 2),
  ('SRH-MIDNIGHT-S', 'sakura-ronin-hoodie', 'Midnight Ink', '#1c1c24', 'S', 349900, NULL, 'in-stock', 9),
  ('SRH-MIDNIGHT-M', 'sakura-ronin-hoodie', 'Midnight Ink', '#1c1c24', 'M', 349900, NULL, 'in-stock', 9),
  ('SRH-MIDNIGHT-L', 'sakura-ronin-hoodie', 'Midnight Ink', '#1c1c24', 'L', 349900, NULL, 'in-stock', 9),
  ('SRH-MIDNIGHT-XL', 'sakura-ronin-hoodie', 'Midnight Ink', '#1c1c24', 'XL', 349900, NULL, 'in-stock', 9),
  ('SRH-MIDNIGHT-2XL', 'sakura-ronin-hoodie', 'Midnight Ink', '#1c1c24', '2XL', 349900, NULL, 'in-stock', 9);

delete from public.embroidery_details where product_slug = 'sakura-ronin-hoodie';
insert into public.embroidery_details (
  product_slug, technique, technique_label, artisan_hours, placement,
  thread_composition, motif_story, macro_image_src, macro_image_alt
) values (
  'sakura-ronin-hoodie', 'hand-zardozi', 'Hand Zardozi', 40,
  ARRAY['back panel', 'sleeves'], 'Silk floss, gilded bullion wire', 'The ronin walks beneath blossoms that fall faster than he moves — beauty and transience stitched at 40 hours.',
  '/images/products/sakura-ronin-hoodie-5.jpg', 'Sakura Ronin zardozi macro'
);

-- Guardian Stripes Pullover  (heroverse · tops/hoodie)
insert into public.products (
  slug,
  name,
  subtitle,
  foreign_tagline,
  description,
  category_slug,
  universe_slug,
  collection_slug,
  garment_type,
  gender,
  motif_id,
  handcrafted,
  craft_techniques,
  edits,
  expression_score,
  rating,
  review_count,
  tags,
  featured,
  customizable,
  material,
  care,
  fit,
  fabric_gsm,
  country_of_origin,
  manufacturer_name,
  manufacturer_address,
  packed_by,
  cod_available,
  delivery_days_min,
  delivery_days_max,
  return_window_days,
  weight_grams,
  hsn_code,
  size_chart
) values (
  'guardian-stripes-pullover',
  'Guardian Stripes Pullover',
  'Speed lines of those who show up first.',
  NULL,
  'Loopback crewneck pullover with Guardian Stripes running diagonal across the chest — navy bands and burst-yellow knots in structural sashiko grid.',
  'tops',
  'heroverse',
  'midnight-atelier',
  'hoodie',
  'unisex',
  'guardian-stripes',
  true,
  ARRAY['sashiko-selvedge'],
  ARRAY['statement', 'everyday'],
  3,
  4.7,
  68,
  ARRAY['heroverse', 'hoodie', 'unisex'],
  false,
  false,
  ARRAY['340 GSM loopback cotton'],
  '{}',
  'Relaxed Fit',
  '340 GSM',
  'IN',
  NULL,
  NULL,
  NULL,
  true,
  5,
  7,
  7,
  700,
  '6110',
  '{"S":{"chest":102,"length":67},"M":{"chest":107,"length":69},"L":{"chest":112,"length":71},"XL":{"chest":117,"length":73}}'::jsonb
) on conflict (slug) do update set
  name = excluded.name,
  subtitle = excluded.subtitle,
  foreign_tagline = excluded.foreign_tagline,
  description = excluded.description,
  category_slug = excluded.category_slug,
  universe_slug = excluded.universe_slug,
  collection_slug = excluded.collection_slug,
  garment_type = excluded.garment_type,
  gender = excluded.gender,
  motif_id = excluded.motif_id,
  handcrafted = excluded.handcrafted,
  craft_techniques = excluded.craft_techniques,
  edits = excluded.edits,
  expression_score = excluded.expression_score,
  rating = excluded.rating,
  review_count = excluded.review_count,
  tags = excluded.tags,
  featured = excluded.featured,
  customizable = excluded.customizable,
  material = excluded.material,
  care = excluded.care,
  fit = excluded.fit,
  fabric_gsm = excluded.fabric_gsm,
  country_of_origin = excluded.country_of_origin,
  manufacturer_name = excluded.manufacturer_name,
  manufacturer_address = excluded.manufacturer_address,
  packed_by = excluded.packed_by,
  cod_available = excluded.cod_available,
  delivery_days_min = excluded.delivery_days_min,
  delivery_days_max = excluded.delivery_days_max,
  return_window_days = excluded.return_window_days,
  weight_grams = excluded.weight_grams,
  hsn_code = excluded.hsn_code,
  size_chart = excluded.size_chart;

delete from public.product_images where product_slug = 'guardian-stripes-pullover';
insert into public.product_images (product_slug, src, alt, color, sort_order) values
  ('guardian-stripes-pullover', '/images/products/kantha-chore-jacket-1.jpg', 'Guardian Stripes Pullover — front', NULL, 0),
  ('guardian-stripes-pullover', '/images/products/sashiko-selvedge-denim-1.jpg', 'Guardian Stripes Pullover — stripe macro', NULL, 1);

delete from public.variants where product_slug = 'guardian-stripes-pullover';
insert into public.variants (sku, product_slug, color, color_hex, size, price_cents, compare_at_price_cents, status, quantity) values
  ('GSP-NAVY-XS', 'guardian-stripes-pullover', 'Navy Surge', '#25314d', 'XS', 359900, NULL, 'in-stock', 14),
  ('GSP-NAVY-S', 'guardian-stripes-pullover', 'Navy Surge', '#25314d', 'S', 359900, NULL, 'in-stock', 14),
  ('GSP-NAVY-M', 'guardian-stripes-pullover', 'Navy Surge', '#25314d', 'M', 359900, NULL, 'in-stock', 14),
  ('GSP-NAVY-L', 'guardian-stripes-pullover', 'Navy Surge', '#25314d', 'L', 359900, NULL, 'in-stock', 14),
  ('GSP-NAVY-XL', 'guardian-stripes-pullover', 'Navy Surge', '#25314d', 'XL', 359900, NULL, 'in-stock', 14),
  ('GSP-NAVY-2XL', 'guardian-stripes-pullover', 'Navy Surge', '#25314d', '2XL', 359900, NULL, 'in-stock', 14),
  ('GSP-NAVY-3XL', 'guardian-stripes-pullover', 'Navy Surge', '#25314d', '3XL', 359900, NULL, 'in-stock', 14),
  ('GSP-STORM-S', 'guardian-stripes-pullover', 'Storm Grey', '#6b6f76', 'S', 359900, NULL, 'in-stock', 9),
  ('GSP-STORM-M', 'guardian-stripes-pullover', 'Storm Grey', '#6b6f76', 'M', 359900, NULL, 'in-stock', 9),
  ('GSP-STORM-L', 'guardian-stripes-pullover', 'Storm Grey', '#6b6f76', 'L', 359900, NULL, 'in-stock', 9),
  ('GSP-STORM-XL', 'guardian-stripes-pullover', 'Storm Grey', '#6b6f76', 'XL', 359900, NULL, 'in-stock', 9),
  ('GSP-STORM-2XL', 'guardian-stripes-pullover', 'Storm Grey', '#6b6f76', '2XL', 359900, NULL, 'in-stock', 9);

delete from public.embroidery_details where product_slug = 'guardian-stripes-pullover';
insert into public.embroidery_details (
  product_slug, technique, technique_label, artisan_hours, placement,
  thread_composition, motif_story, macro_image_src, macro_image_alt
) values (
  'guardian-stripes-pullover', 'sashiko-selvedge', 'Sashiko Selvedge', 16,
  ARRAY['chest', 'cuffs'], 'White cotton thread, burst-yellow accent', 'Diagonal action-line bands — the geometry of first responders.',
  '/images/products/sashiko-selvedge-denim-2.jpg', 'Guardian stripes sashiko macro'
);

-- Arch Jaal Silk Scarf  (itihaas · accessories/scarf)
insert into public.products (
  slug,
  name,
  subtitle,
  foreign_tagline,
  description,
  category_slug,
  universe_slug,
  collection_slug,
  garment_type,
  gender,
  motif_id,
  handcrafted,
  craft_techniques,
  edits,
  expression_score,
  rating,
  review_count,
  tags,
  featured,
  customizable,
  material,
  care,
  fit,
  fabric_gsm,
  country_of_origin,
  manufacturer_name,
  manufacturer_address,
  packed_by,
  cod_available,
  delivery_days_min,
  delivery_days_max,
  return_window_days,
  weight_grams,
  hsn_code,
  size_chart
) values (
  'arch-jaal-scarf',
  'Arch Jaal Silk Scarf',
  'Courtyards of patience — geometry as devotion.',
  NULL,
  'Mulberry silk scarf with the Arch Jaal lattice worked in tonal gold — Mughal geometry held to a whisper.',
  'accessories',
  'itihaas',
  'royal-heritage',
  'scarf',
  'unisex',
  'arch-jaal',
  true,
  ARRAY['metallic-zari'],
  ARRAY['heritage', 'festive-gifting'],
  2,
  4.8,
  33,
  ARRAY['itihaas', 'accessories', 'unisex'],
  false,
  false,
  ARRAY['18 Momme Mulberry Silk Twill'],
  '{}',
  'One Size',
  '18 momme silk',
  'IN',
  NULL,
  NULL,
  NULL,
  true,
  4,
  6,
  7,
  180,
  '6214',
  '{"ONE":{"length":180,"width":70}}'::jsonb
) on conflict (slug) do update set
  name = excluded.name,
  subtitle = excluded.subtitle,
  foreign_tagline = excluded.foreign_tagline,
  description = excluded.description,
  category_slug = excluded.category_slug,
  universe_slug = excluded.universe_slug,
  collection_slug = excluded.collection_slug,
  garment_type = excluded.garment_type,
  gender = excluded.gender,
  motif_id = excluded.motif_id,
  handcrafted = excluded.handcrafted,
  craft_techniques = excluded.craft_techniques,
  edits = excluded.edits,
  expression_score = excluded.expression_score,
  rating = excluded.rating,
  review_count = excluded.review_count,
  tags = excluded.tags,
  featured = excluded.featured,
  customizable = excluded.customizable,
  material = excluded.material,
  care = excluded.care,
  fit = excluded.fit,
  fabric_gsm = excluded.fabric_gsm,
  country_of_origin = excluded.country_of_origin,
  manufacturer_name = excluded.manufacturer_name,
  manufacturer_address = excluded.manufacturer_address,
  packed_by = excluded.packed_by,
  cod_available = excluded.cod_available,
  delivery_days_min = excluded.delivery_days_min,
  delivery_days_max = excluded.delivery_days_max,
  return_window_days = excluded.return_window_days,
  weight_grams = excluded.weight_grams,
  hsn_code = excluded.hsn_code,
  size_chart = excluded.size_chart;

delete from public.product_images where product_slug = 'arch-jaal-scarf';
insert into public.product_images (product_slug, src, alt, color, sort_order) values
  ('arch-jaal-scarf', '/images/products/embroidered-silk-scarf-2.jpg', 'Arch Jaal Silk Scarf — drape', NULL, 0),
  ('arch-jaal-scarf', '/images/products/embroidered-silk-scarf-1.jpg', 'Arch Jaal Silk Scarf — lattice macro', NULL, 1);

delete from public.variants where product_slug = 'arch-jaal-scarf';
insert into public.variants (sku, product_slug, color, color_hex, size, price_cents, compare_at_price_cents, status, quantity) values
  ('AJS-OS-GLD', 'arch-jaal-scarf', 'Ivory & Gold', '#efe4c8', 'OS', 189900, NULL, 'in-stock', 11);

delete from public.embroidery_details where product_slug = 'arch-jaal-scarf';
insert into public.embroidery_details (
  product_slug, technique, technique_label, artisan_hours, placement,
  thread_composition, motif_story, macro_image_src, macro_image_alt
) values (
  'arch-jaal-scarf', 'metallic-zari', 'Metallic Zari', 9,
  ARRAY['border', 'allover lattice'], 'Champagne zari on ivory silk', 'Mughal arch lattice, symmetric, tonal — the geometry reads only at arm’s length.',
  '/images/products/embroidered-silk-scarf-1.jpg', 'Arch jaal lattice macro'
);

commit;
