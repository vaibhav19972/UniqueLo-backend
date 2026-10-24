-- ============================================================================
-- 20261026_catalogue_garment_types.sql
--
-- The garment registry shipped with 9 silhouettes (hoodie, tee, shirt, jacket,
-- cardigan, vest, pants, scarf, tote). The 25-product photo catalogue contains
-- seven more that had no legal value, so every one of those rows would have been
-- forced into a wrong type or refused by the FK.
--
-- This is the case the attribute system was designed for: adding a garment type
-- is an INSERT, not an ALTER. No column changes, no client adapter changes --
-- the discounts are the filter UI picking up the new slugs.
--
-- Also extends attribute_definitions.applies_to so the required attributes are
-- actually required FOR THE NEW TYPES. Without that, a kurta would pass with
-- occasion+fabric only, while a tee needed five.
--
-- Idempotent: safe to run more than once.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. New garment silhouettes
-- ---------------------------------------------------------------------------
insert into public.garments (slug, name, category_slug, description, order_num)
values
  ('sweater',    'Sweaters',    'knitwear', 'Knit pullovers with mandarin collars and tonal botanical embroidery.', 10),
  ('sweatshirt', 'Sweatshirts', 'tops',     'Fleece-back crewneck sweatshirts with chest graphics.', 11),
  ('blouse',     'Blouses',     'tops',     'Button-front and tie-neck blouses with sleeve and yoke embroidery.', 12),
  ('kurta',      'Kurtas',      'tops',     'Tunic-length kurtas with folk embroidery and tassel ties.', 13),
  ('tunic',      'Tunics',      'tops',     'Relaxed tunic tops with embroidered necklines and hem bands.', 14),
  ('skirt',      'Skirts',      'bottoms',  'Gathered A-line skirts with waistband and trailing floral embroidery.', 15),
  ('jeans',      'Jeans',       'bottoms',  'Wide-leg denim with embroidered hems and contrast topstitching.', 16)
on conflict (slug) do update set
  name = excluded.name,
  category_slug = excluded.category_slug,
  description = excluded.description,
  order_num = excluded.order_num;

-- ---------------------------------------------------------------------------
-- 2. Attribute coverage for the new types
-- ---------------------------------------------------------------------------
-- Only `applies_to` changes. `is_required` is left exactly as it was: the
-- attributes a blouse must declare are the ones the registry already marks
-- mandatory for a collared woven top, no new mandatory fields invented.
update public.attribute_definitions
   set applies_to = array['tee','hoodie','shirt','jacket','cardigan','vest','pants','scarf','tote',
                          'sweater','sweatshirt','blouse','kurta','tunic','skirt','jeans']
 where key = 'pattern';

update public.attribute_definitions
   set applies_to = array['tee','hoodie','shirt','cardigan','vest',
                          'sweater','sweatshirt','blouse','kurta','tunic']
 where key = 'neck_type';

update public.attribute_definitions
   set applies_to = array['tee','hoodie','shirt','jacket','cardigan','vest',
                          'sweater','sweatshirt','blouse','kurta','tunic']
 where key = 'sleeve_length';

update public.attribute_definitions
   set applies_to = array['hoodie','shirt','jacket','cardigan','vest','pants',
                          'sweatshirt','blouse','kurta','skirt','jeans',
                          'sweater','tunic']
 where key = 'closure';

update public.attribute_definitions
   set applies_to = array['tee','hoodie','shirt','jacket','cardigan','vest',
                          'sweater','sweatshirt','blouse','kurta','tunic','skirt','jeans']
 where key = 'length';

update public.attribute_definitions
   set applies_to = array['pants','jeans']
 where key = 'rise';

update public.attribute_definitions
   set applies_to = array['tee','hoodie','shirt','jacket','cardigan','vest',
                          'sweater','sweatshirt','blouse','kurta','tunic','skirt','jeans']
 where key = 'hemline';

update public.attribute_definitions
   set applies_to = array['jacket','vest','pants','skirt','jeans']
 where key = 'lining';

update public.attribute_definitions
   set applies_to = array['tee','shirt','scarf','blouse','kurta','tunic']
 where key = 'transparency';

update public.attribute_definitions
   set applies_to = array['tee','hoodie','pants','sweatshirt','sweater','jeans']
 where key = 'fabric_weight_gsm';

commit;
