-- ============================================================================
-- verify-admin-order-access.sql
--
-- Asserts the authorisation boundary 20261103 creates. EXITS NON-ZERO on any
-- failure — a battery that prints and always succeeds is a false-green
-- generator, the same defect as the schema gate that computed drift and
-- discarded it.
--
-- THREE THINGS THIS DOES DIFFERENTLY FROM A HAND-RUN TRANSCRIPT
--
-- 1. It APPLIES THE MIGRATION ITSELF (`\ir`), it does not retype its grants.
--    A hand-copied revoke proves nothing about the file that ships. Re-applying
--    also proves the migration is idempotent, which the deploy doc claims.
--
-- 2. The mechanism is asserted with has_column_privilege / has_table_privilege,
--    not inferred from an error string. Postgres reports column-ACL failures as
--    "permission denied for table", so a transcript cannot distinguish the two.
--
-- 3. place_order is re-tested AFTER the revoke. It is SECURITY DEFINER and
--    should bypass the grant, but "should" is what produced seven missing
--    tables. If it ever stops being definer, checkout dies and the failure looks
--    like an RLS denial deep inside the order flow.
--
-- EXPECT DIRECTION, stated so nobody misreads it:
--   * DENY BY GRANT / CONSTRAINT  -> raises an ERROR
--   * DENY BY RLS on UPDATE       -> affects 0 rows, RAISES NOTHING
-- The two are not interchangeable and are labelled separately below.
-- ============================================================================
\set ON_ERROR_STOP on
\pset pager off

-- ===========================================================================
-- SAFETY: THIS FILE MUTATES DATA AND MUST NEVER TOUCH HOSTED.
-- It inserts fixtures, calls place_order — which DECREMENTS REAL INVENTORY —
-- and deletes rows. A unix-socket connection reports inet_server_addr() = NULL,
-- which is how run-admin-order-access.sh connects. Anything with a non-loopback
-- server address is refused before a single statement runs.
-- ===========================================================================
do $$
begin
  if inet_server_addr() is not null
     and not (inet_server_addr() << inet '127.0.0.0/8') then
    raise exception
      'REFUSING TO RUN: this battery decrements real stock and deletes rows. '
      'It is for a throwaway local cluster only. inet_server_addr() = %',
      inet_server_addr() using errcode = '42501';
  end if;
  raise notice 'local cluster confirmed — running battery';
end $$;

-- ---------------------------------------------------------------------------
-- 0. Mirror Supabase: roles hold table-wide privileges, RLS is the only gate.
--    Without this the revoke below is a no-op locally and proves nothing.
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['orders','order_items','products','variants',
                           'admins','attribute_definitions','coupons'] loop
    execute format('grant select, insert, update, delete on public.%I to anon, authenticated', t);
  end loop;
end $$;
grant usage on schema public to anon, authenticated;
grant execute on all functions in schema public to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1. Apply the migration under test (idempotent, so re-application is fine)
-- ---------------------------------------------------------------------------
\echo '--- applying migrations/20261103_admin_order_access.sql ---'
\ir ../migrations/20261103_admin_order_access.sql

-- ---------------------------------------------------------------------------
-- 2. Fixtures
-- ---------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'cust-a@example.com'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'cust-b@example.com'),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'admin@uniquelo.com'),
  -- NOT in public.admins: reaches admin only via the app_metadata.role claim
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'svc@example.com')
on conflict do nothing;

insert into public.admins (user_id, email, note)
values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'admin@uniquelo.com', 'verify admin')
on conflict (user_id) do nothing;

delete from public.order_items where order_id in
  ('dddddddd-0000-4000-8000-000000000001','dddddddd-0000-4000-8000-000000000002',
   'dddddddd-0000-4000-8000-000000000003');
delete from public.orders where id in
  ('dddddddd-0000-4000-8000-000000000001','dddddddd-0000-4000-8000-000000000002',
   'dddddddd-0000-4000-8000-000000000003');

insert into public.orders
  (id, customer_name, customer_email, user_id, status,
   subtotal_cents, discount_cents, shipping_cents, cod_fee_cents, total_cents)
values
  ('dddddddd-0000-4000-8000-000000000001','Cust A','cust-a@example.com',
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','confirmed', 10000,0,9900,0,19900),
  ('dddddddd-0000-4000-8000-000000000002','Cust B','cust-b@example.com',
   'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','confirmed', 20000,0,   0,0,20000),
  ('dddddddd-0000-4000-8000-000000000003','Guest','guest@example.com',
   NULL,'confirmed',  5000,0,9900,0,14900);

insert into public.order_items
  (order_id, product_slug, variant_sku, product_name, color, size, quantity, price_cents)
values
  ('dddddddd-0000-4000-8000-000000000001','p1','SKU-1','P1','Ecru','S',1,10000),
  ('dddddddd-0000-4000-8000-000000000002','p2','SKU-2','P2','Ink','M',1,20000);

-- ---------------------------------------------------------------------------
-- 3. HARD ASSERTIONS — the grant posture itself. These raise on failure.
-- ---------------------------------------------------------------------------
\echo '--- static privilege assertions ---'
do $$
declare
  v_fail text[] := '{}';
  function_missing text;
begin
  -- admin may update exactly the three fulfilment columns
  if not has_column_privilege('authenticated','public.orders','status','UPDATE') then
    v_fail := v_fail || 'status NOT updatable by authenticated'::text;
  end if;
  if not has_column_privilege('authenticated','public.orders','tracking_number','UPDATE') then
    v_fail := v_fail || 'tracking_number NOT updatable'::text;
  end if;
  if not has_column_privilege('authenticated','public.orders','carrier','UPDATE') then
    v_fail := v_fail || 'carrier NOT updatable'::text;
  end if;

  -- ...and nothing else. This is the whole point of the column grant.
  if has_column_privilege('authenticated','public.orders','total_cents','UPDATE') then
    v_fail := v_fail || 'SECURITY: total_cents is updatable'::text;
  end if;
  if has_column_privilege('authenticated','public.orders','customer_email','UPDATE') then
    v_fail := v_fail || 'SECURITY: customer_email is updatable'::text;
  end if;
  if has_column_privilege('authenticated','public.orders','user_id','UPDATE') then
    v_fail := v_fail || 'SECURITY: user_id is updatable'::text;
  end if;
  if has_column_privilege('authenticated','public.orders','coupon_code','UPDATE') then
    v_fail := v_fail || 'SECURITY: coupon_code is updatable'::text;
  end if;

  -- no minting, no deleting
  if has_table_privilege('authenticated','public.orders','INSERT') then
    v_fail := v_fail || 'SECURITY: authenticated can INSERT orders'::text;
  end if;
  if has_table_privilege('authenticated','public.orders','DELETE') then
    v_fail := v_fail || 'SECURITY: authenticated can DELETE orders'::text;
  end if;
  if has_table_privilege('anon','public.orders','INSERT') then
    v_fail := v_fail || 'SECURITY: anon can INSERT orders'::text;
  end if;
  if has_table_privilege('anon','public.orders','SELECT') then
    v_fail := v_fail || 'anon still holds SELECT on orders'::text;
  end if;

  -- line items are read-only for everyone but the definer functions
  if has_table_privilege('authenticated','public.order_items','UPDATE') then
    v_fail := v_fail || 'SECURITY: order_items is updatable'::text;
  end if;

  if array_length(v_fail, 1) is not null then
    raise exception 'PRIVILEGE ASSERTIONS FAILED: %', array_to_string(v_fail, '; ');
  end if;
  raise notice 'privilege posture OK — 3 updatable columns, no INSERT/DELETE, anon blind';
end $$;

-- ---------------------------------------------------------------------------
-- 4. HARD ASSERTION — checkout still works after the revoke
-- ---------------------------------------------------------------------------
\echo '--- place_order regression (SECURITY DEFINER must survive the revoke) ---'
do $$
declare
  v_sku  text;
  v_slug text;
  v_res  jsonb;
  v_id   uuid;
  v_own  uuid;
begin
  -- Derive slug and sku from the SAME row. Hardcoding 'ascendant-cream-tee'
  -- against a dynamically chosen sku fails for the wrong reason if the seed
  -- changes, and a confusing failure is worse than no test.
  select sku, product_slug into v_sku, v_slug
    from public.variants where quantity > 0 limit 1;

  set local role anon;
  v_res := public.place_order(
    jsonb_build_object(
      'customer_name',  'Verify Anon',
      'customer_email', 'verify-anon@example.com',
      'status',         'confirmed',
      'shipping_address', jsonb_build_object('line1','x','city','y',
                                             'postal_code','110001','country','India',
                                             'payment_method','prepaid')),
    jsonb_build_array(jsonb_build_object(
      'product_slug',v_slug,'variant_sku',v_sku,
      'product_name','P','color','Ecru','size','S','quantity',1,'price_cents',89900))
  );
  reset role;

  v_id := (v_res->>'id')::uuid;

  if v_id is null then
    raise exception 'REGRESSION: place_order returned no id as anon after the revoke';
  end if;
  if not (v_res->'success')::boolean then
    raise exception 'REGRESSION: place_order reported success=false after the revoke';
  end if;

  raise notice 'place_order OK as anon — order % total %', v_id, v_res->>'total_cents';

  -- get_order_details must also be definer, since anon can no longer read orders
  declare v_det jsonb;
  begin
    set local role anon;
    v_det := public.get_order_details(v_id, 'verify-anon@example.com');
    reset role;
    if v_det is null then
      raise exception 'REGRESSION: get_order_details returned null after the revoke';
    end if;
    raise notice 'get_order_details OK as anon — % items', jsonb_array_length(v_det->'items');
  end;

  delete from public.order_items where order_id = v_id;
  delete from public.orders where id = v_id;
end $$;

-- Signed-in checkout: the revoke dropped INSERT from `authenticated`, so this
-- path must still work through the definer function — and it is the path that
-- sets orders.user_id, the entire basis of 20261031's "Users view own orders".
-- If the revoke ever interferes with the definer path, it shows up here.
do $$
declare
  v_sku  text;
  v_slug text;
  v_res  jsonb;
  v_id   uuid;
  v_own  uuid;
begin
  select sku, product_slug into v_sku, v_slug
    from public.variants where quantity > 0 limit 1;

  set local role authenticated;
  perform set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true);

  v_res := public.place_order(
    jsonb_build_object(
      'customer_name',  'Verify Signed In',
      'customer_email', 'cust-a@example.com',
      'status',         'confirmed',
      'shipping_address', jsonb_build_object('line1','x','city','y',
                                             'postal_code','110001','country','India',
                                             'payment_method','prepaid')),
    jsonb_build_array(jsonb_build_object(
      'product_slug',v_slug,'variant_sku',v_sku,
      'product_name','P','color','Ecru','size','S','quantity',1,'price_cents',89900))
  );
  v_id := (v_res->>'id')::uuid;

  if v_id is null then
    raise exception 'REGRESSION: signed-in place_order returned no id after the revoke';
  end if;

  select user_id into v_own from public.orders where id = v_id;
  reset role;

  if v_own is null then
    raise exception 'REGRESSION: signed-in order has user_id NULL — ownership not derived';
  end if;
  if v_own <> 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid then
    raise exception 'REGRESSION: signed-in order owned by %, expected customer A', v_own;
  end if;
  raise notice 'signed-in place_order OK — user_id derived from auth.uid()';

  delete from public.order_items where order_id = v_id;
  delete from public.orders where id = v_id;
end $$;

-- ---------------------------------------------------------------------------
-- 5. BEHAVIOURAL — counts are echoed so a wrong number is visible, and the
--    three read-boundary cases raise on a mismatch.
-- ---------------------------------------------------------------------------
\echo '--- read boundary ---'
-- anon is denied at the GRANT level since 20261103 (SELECT revoked), so this
-- RAISES rather than returning 0 rows. Both outcomes are a correct denial; they
-- are different mechanisms and the message says which one fired. Accepting only
-- "0 rows" would make this case fail on the hardening it is meant to prove.
begin;
  set local role anon;
  do $$ declare n int; begin
    begin
      select count(*) into n from public.orders;
      if n <> 0 then
        raise exception 'anon sees % orders, expected 0 or a grant denial', n;
      end if;
      raise notice 'anon read orders -> 0 rows (RLS-filtered) — OK';
    exception when insufficient_privilege then
      raise notice 'anon read orders -> denied by GRANT — OK (stronger than RLS)';
    end;
  end $$;
rollback;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  do $$ declare n int; begin
    select count(*) into n from public.orders;
    if n <> 1 then raise exception 'customer A sees % orders, expected 1', n; end if;
    raise notice 'customer A sees 1 order — OK';
  end $$;
rollback;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  do $$ declare n int; begin
    select count(*) into n from public.orders;
    if n <> 3 then raise exception 'admin sees % orders, expected 3', n; end if;
    raise notice 'admin sees 3 orders — OK';
  end $$;
rollback;

-- admin via app_metadata.role claim, NOT a row in public.admins
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  do $$ declare n int; begin
    perform set_config('request.jwt.claims',
      '{"app_metadata":{"role":"admin"}}', true);
    select count(*) into n from public.orders;
    if n <> 3 then
      raise exception 'app_metadata admin sees % orders, expected 3 — is_admin() jwt branch broken', n;
    end if;
    raise notice 'app_metadata admin sees 3 orders — is_admin() jwt branch OK';
  end $$;
rollback;

-- ---------------------------------------------------------------------------
-- 6. BEHAVIOURAL — write boundary. Row counts echoed: RLS denial is SILENT.
-- ---------------------------------------------------------------------------
\echo '--- write boundary (RLS denial affects 0 rows and raises nothing) ---'

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  do $$ declare n int; begin
    update public.orders set status = 'cancelled'
     where id = 'dddddddd-0000-4000-8000-000000000001';
    get diagnostics n = row_count;
    if n <> 0 then raise exception 'customer A updated their own order (% rows)', n; end if;
    raise notice 'customer A update OWN order -> % rows (RLS silent, expected 0)', n;
  end $$;
rollback;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  do $$ declare n int; begin
    update public.orders set status = 'processing'
     where id = 'dddddddd-0000-4000-8000-000000000002';
    get diagnostics n = row_count;
    if n <> 1 then raise exception 'admin update affected % rows, expected 1', n; end if;
    raise notice 'admin update status -> % row — OK', n;
  end $$;
rollback;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  do $$ declare n int; begin
    update public.orders
       set status = 'shipped', tracking_number = 'AWB123', carrier = 'Delhivery'
     where id = 'dddddddd-0000-4000-8000-000000000002';
    get diagnostics n = row_count;
    if n <> 1 then raise exception 'admin ship affected % rows, expected 1', n; end if;
    raise notice 'admin ship+track+carrier -> % row — OK', n;
  end $$;
rollback;

-- ---------------------------------------------------------------------------
-- 7. Constraint cases: must RAISE, and must name the constraint.
-- ---------------------------------------------------------------------------
\echo '--- constraint enforcement (these raise by design) ---'

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  do $$ begin
    begin
      update public.orders set status = 'shipped'
       where id = 'dddddddd-0000-4000-8000-000000000002';
      raise exception 'shipped with no tracking was ACCEPTED — constraint missing';
    exception when check_violation then
      raise notice 'shipped without tracking refused — OK';
    end;
  end $$;
rollback;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  do $$ begin
    begin
      update public.orders set tracking_number = 'AWB999'
       where id = 'dddddddd-0000-4000-8000-000000000002';
      raise exception 'tracking without carrier was ACCEPTED — constraint missing';
    exception when check_violation then
      raise notice 'tracking without carrier refused — OK';
    end;
  end $$;
rollback;

\echo ''
\echo '=============== ALL ASSERTIONS PASSED ==============='
