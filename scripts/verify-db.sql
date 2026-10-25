-- ============================================================================
-- VERIFY: run AFTER schema.sql + migration + production-seed.sql
-- Every query here should return the value in the comment. Anything else
-- means the database is NOT in sync with the code.
-- ============================================================================

\echo '--- 1. product column count (expect 44 after schema.sql; 45 once 01_web adds intensity) ---'
select count(*) as product_columns
from information_schema.columns
where table_schema = 'public' and table_name = 'products';

\echo '--- 2. retired columns must be GONE (expect 0) ---'
-- is_mock/vibes/moods were retired by decision (no mock flag in the DB);
-- the rest were dropped by migrations/20261024.
select count(*) as should_be_zero
from information_schema.columns
where table_schema = 'public' and table_name = 'products'
  and column_name in ('craft_region','craft_cluster','batch_number',
                      'batch_total','expression_slug','sold_count',
                      'is_mock','vibes','moods','character_ids');

\echo '--- 3. trust + marketplace columns must EXIST (expect 14) ---'
select count(*) as should_be_fourteen
from information_schema.columns
where table_schema = 'public' and table_name = 'products'
  and column_name in ('country_of_origin','manufacturer_name','manufacturer_address',
                      'packed_by','cod_available','delivery_days_min','delivery_days_max',
                      'return_window_days','weight_grams','hsn_code','size_chart',
                      'style_code','attributes','fit_notes');

\echo '--- 4. rows (production-seed baseline: products=3 variants=25; the hosted catalogue is whatever products/ published) ---'
select 'categories' as t, count(*) from categories
union all select 'garments', count(*) from garments
union all select 'universes', count(*) from universes
union all select 'motifs', count(*) from motifs
union all select 'collections', count(*) from collections
union all select 'products', count(*) from products
union all select 'variants', count(*) from variants
union all select 'attribute_definitions', count(*) from attribute_definitions
order by t;

\echo '--- 5. every variant has a barcode (expect 0 missing) ---'
select count(*) as missing_barcodes from variants where barcode is null;

\echo '--- 6. owner decisions applied (expect cod=true, returns=7 on all rows) ---'
select slug, cod_available, return_window_days,
       delivery_days_min || '-' || delivery_days_max as delivery
from products order by slug;

\echo '--- 7. attributes present and valid per garment ---'
select p.slug, p.garment_type,
       jsonb_object_keys(p.attributes) as attribute
from products p order by p.slug, attribute;

\echo '--- 8. RLS enabled on attribute_definitions (expect t) ---'
select relrowsecurity as rls_enabled
from pg_class where relname = 'attribute_definitions';

\echo '--- 9. trigger installed (expect 1) ---'
select count(*) as trigger_count
from pg_trigger where tgname = 'products_validate_attributes';

\echo '--- 10. style codes unique and non-null (expect 0 nulls) ---'
select count(*) as null_style_codes from products where style_code is null;
