-- Verification battery for 20261031_customer_accounts.sql
-- Mirrors Supabase's real posture: anon/authenticated HOLD table grants, so
-- RLS is the only thing standing between a customer and the catalogue.
\set ON_ERROR_STOP off
\pset pager off

do $$ declare t text; begin
  foreach t in array array['products','variants','product_images','collections',
                           'embroidery_details','categories','garments','motifs',
                           'universes','attribute_definitions','orders','order_items',
                           'customer_addresses','customer_wishlists','reviews'] loop
    execute format('alter table public.%I force row level security', t);
    execute format('grant select, insert, update, delete on public.%I to anon, authenticated', t);
  end loop;
end $$;

grant usage on schema public to anon, authenticated;
grant usage on schema storage to anon, authenticated;
grant select, insert, update, delete on storage.objects to anon, authenticated;
grant execute on all functions in schema public to anon, authenticated;

-- Real Supabase has RLS on for storage.objects. Enable it here too, or the
-- storage policies are inert and T11 passes for the wrong reason (measured
-- 2026-10-29: the customer insert succeeded until this line was added).
alter table storage.objects enable row level security;

insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'customer@example.com'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'admin@uniquelo.com')
on conflict do nothing;

insert into public.admins (user_id, email, note)
values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'admin@uniquelo.com', 'test admin')
on conflict (user_id) do nothing;

\echo '===== T1 anon cannot INSERT garments (expect RLS denial, not grant denial)'
begin;
  set local role anon;
  insert into public.garments (name, slug, description) values ('x','__probe_anon__','d');
rollback;

\echo '===== T2 authenticated NON-ADMIN cannot INSERT garments  <-- the OA-6 test'
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  insert into public.garments (name, slug, description) values ('x','__probe_cust__','d');
rollback;

\echo '===== T3 authenticated ADMIN can INSERT garments (gate not over-tight)'
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  insert into public.garments (name, slug, description) values ('Admin Garment','__probe_admin__','d');
  \echo 'ADMIN INSERT OK'
rollback;

\echo '===== T4 non-admin cannot rewrite attribute_definitions'
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  update public.attribute_definitions set label = 'sabotaged' where key = 'pattern';
rollback;

\echo '===== T5 admin CAN write attribute_definitions'
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  update public.attribute_definitions set label = label where key = 'pattern';
  \echo 'ADMIN UPDATE OK'
rollback;

\echo '===== T6 GUEST checkout works -> user_id NULL'
begin;
  set local role anon;
  select (public.place_order(
    '{"customer_name":"Guest","customer_email":"guest@example.com"}'::jsonb,
    jsonb_build_array(jsonb_build_object('variant_sku','UL-TC51-ECRU-XS','quantity',1))
  )->>'user_id') as guest_user_id,
  (public.place_order(
    '{"customer_name":"Guest","customer_email":"guest@example.com"}'::jsonb,
    jsonb_build_array(jsonb_build_object('variant_sku','UL-TC51-ECRU-S','quantity',1))
  )->>'total_cents') as guest_total;
rollback;

\echo '===== T7 SIGNED-IN checkout -> user_id = auth.uid()'
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  select public.place_order(
    '{"customer_name":"Customer","customer_email":"customer@example.com"}'::jsonb,
    jsonb_build_array(jsonb_build_object('variant_sku','UL-TC51-ECRU-XS','quantity',1))
  );
  reset role;
  select user_id, customer_email, total_cents from public.orders
   where customer_email='customer@example.com';
rollback;

\echo '===== T8 FORGED user_id in payload is IGNORED'
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  select public.place_order(
    '{"customer_name":"Attacker","customer_email":"attacker@example.com","user_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"}'::jsonb,
    jsonb_build_array(jsonb_build_object('variant_sku','UL-TC51-ECRU-XS','quantity',1))
  );
  reset role;
  select actual_owner,
         (actual_owner = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') as bound_to_caller,
         (actual_owner = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') as BOUND_TO_VICTIM_BAD
  from (select user_id as actual_owner from public.orders where customer_email='attacker@example.com') q;
rollback;

\echo '===== T9 customer sees ONLY own orders, never guests, never others'
-- Seeding happens as the table owner: §5c makes orders RPC-only for clients,
-- so a direct INSERT as `authenticated` is now (correctly) refused.
begin;
  insert into public.orders (id, customer_name, customer_email, user_id, subtotal_cents, total_cents)
  values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','Mine','customer@example.com','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',100,100);
  insert into public.orders (id, customer_name, customer_email, user_id, subtotal_cents, total_cents)
  values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd','Theirs','other@example.com','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',100,100);
  insert into public.orders (id, customer_name, customer_email, user_id, subtotal_cents, total_cents)
  values ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','Guest','guest-order@example.com',null,100,100);

  set local role authenticated;
  set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  \echo 'visible rows for customer (expect exactly 1, customer@example.com):'
  select customer_email from public.orders;
  \echo 'guest + other-user rows must stay invisible:'
  select count(*) as must_be_zero from public.orders where user_id is distinct from 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
rollback;

\echo '===== T9b clients cannot INSERT orders directly (forgery vector closed)'
begin;
  set local role anon;
  insert into public.orders (id, customer_name, customer_email, subtotal_cents, total_cents)
  values ('ffffffff-ffff-4fff-8fff-ffffffffffff','Fake','x@example.com',1,1);
rollback;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  insert into public.orders (id, customer_name, customer_email, user_id, subtotal_cents, total_cents)
  values ('ffffffff-ffff-4fff-8fff-ffffffffffff','Fake','x@example.com','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',1,1);
rollback;

\echo '===== T10 addresses: own-only, single default, pincode format'
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  insert into public.customer_addresses (user_id, recipient_name, phone, address_line, city, state, pincode, is_default)
  values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','A','9876543210','1 Road','Pune','MH','411001',true);
  \echo '-- second default EXPECTED TO FAIL:'
  savepoint s1;
  insert into public.customer_addresses (user_id, recipient_name, phone, address_line, city, state, pincode, is_default)
  values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','B','9876543211','2 Road','Pune','MH','411002',true);
  rollback to s1;
  \echo '-- bad pincode EXPECTED TO FAIL:'
  savepoint s2;
  insert into public.customer_addresses (user_id, recipient_name, phone, address_line, city, state, pincode)
  values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','C','9876543212','3 Road','Pune','MH','4110');
  rollback to s2;
  \echo '-- address for ANOTHER user EXPECTED TO FAIL:'
  savepoint s3;
  insert into public.customer_addresses (user_id, recipient_name, phone, address_line, city, state, pincode)
  values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','D','9876543213','4 Road','Pune','MH','411003');
  rollback to s3;
rollback;

\echo '===== T11 storage: customer cannot upload, admin can'
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  insert into storage.objects (bucket_id, name) values ('product-images','products/x-1.jpg');
rollback;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  insert into storage.objects (bucket_id, name) values ('product-images','products/x-1.jpg');
  \echo 'ADMIN UPLOAD OK'
rollback;

\echo '===== T12 server price wins over a client-claimed 1 paisa'
begin;
  set local role anon;
  select (public.place_order(
    '{"customer_email":"g@example.com"}'::jsonb,
    jsonb_build_array(jsonb_build_object('variant_sku','UL-TC51-ECRU-XS','quantity',1,'price_cents',1))
  )->>'total_cents') as server_total_should_be_89900;
rollback;

\echo '===== T13 error gates survive the rewrite (P0002 / P0001 / 22023)'
begin;
  set local role anon;
  select public.place_order('{"customer_email":"g@example.com"}'::jsonb,
    jsonb_build_array(jsonb_build_object('variant_sku','__nope__','quantity',1)));
rollback;

begin;
  set local role anon;
  select public.place_order('{"customer_email":"g@example.com"}'::jsonb,
    jsonb_build_array(jsonb_build_object('variant_sku','UL-TC51-ECRU-XS','quantity',999)));
rollback;

begin;
  set local role anon;
  select public.place_order('{"customer_email":"g@example.com","coupon_code":"BOGUS99"}'::jsonb,
    jsonb_build_array(jsonb_build_object('variant_sku','UL-TC51-ECRU-XS','quantity',1)));
rollback;

\echo '===== T14 customer reads their own order ITEMS (20261032), never others'
begin;
  insert into public.orders (id, customer_name, customer_email, user_id, subtotal_cents, total_cents)
  values ('11111111-2222-4333-8444-555555555555','Mine','items@example.com','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',100,100);
  insert into public.order_items (id, order_id, product_slug, variant_sku, product_name, color, size, quantity, price_cents)
  values ('21111111-2222-4333-8444-555555555555','11111111-2222-4333-8444-555555555555','p-mine','S-MINE','Mine Item','Black','M',1,100);

  insert into public.orders (id, customer_name, customer_email, user_id, subtotal_cents, total_cents)
  values ('31111111-2222-4333-8444-555555555555','Theirs','items-other@example.com','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',100,100);
  insert into public.order_items (id, order_id, product_slug, variant_sku, product_name, color, size, quantity, price_cents)
  values ('41111111-2222-4333-8444-555555555555','31111111-2222-4333-8444-555555555555','p-theirs','S-THEIRS','Their Item','Black','M',1,100);

  set local role authenticated;
  set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  \echo 'items visible (expect exactly 1, S-MINE):'
  select variant_sku from public.order_items;
rollback;
