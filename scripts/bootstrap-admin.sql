-- ============================================================================
-- bootstrap-admin.sql
-- ============================================================================
-- Run AFTER 20261025_admin_write_policies.sql and BEFORE 20261031.
--
-- 20261025 grants catalogue writes only to rows in public.admins. A brand-new
-- admins table is empty, so running 20261025 alone leaves EVERY write refused —
-- including the Admin Studio's. This promotes the existing Admin Studio
-- sign-in account so the panel keeps working.
--
-- STEP 0 — confirm the account exists first. If this returns 0 rows, sign in to
-- /admin once (or create the user in Dashboard > Authentication > Users) and
-- re-run. Do not invent a uuid.
--
--   select id, email, created_at from auth.users order by created_at;
--
-- ============================================================================

-- 1. Promote. EDIT THE EMAIL if your Admin Studio account is not this one.
insert into public.admins (user_id, email, note)
select u.id, u.email, 'bootstrap owner'
from auth.users u
where lower(u.email) = lower('admin@uniquelo.com')
on conflict (user_id) do nothing;

-- 2. Prove it landed. Expect exactly the row(s) you intended — no more.
select a.user_id, a.email, a.note, u.last_sign_in_at
from public.admins a
join auth.users u on u.id = a.user_id
order by a.created_at;

-- 3. Expect exactly 1 row. If 0, step 1 matched nothing (wrong email) and the
--    Admin Studio will be read-only until you fix it.
select count(*) as admin_count from public.admins;
