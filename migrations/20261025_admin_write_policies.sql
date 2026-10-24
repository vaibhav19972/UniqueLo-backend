-- ============================================================================
-- HARDEN: lock catalog writes to administrators
-- ============================================================================
--
-- Problem: schema.sql grants product/variant/image/collection/embroidery writes
-- with `using (true)` / `with check (true)`. The anon key ships in the frontend
-- bundle, so "public" means "anyone with a browser console". Measured: a
-- logged-in non-admin deleted all 3 catalog rows.
--
-- The storefront's admin panel signs in with the ANON key + a real user session
-- (Admin.tsx AdminAuthGate -> supabase.auth.signInWithPassword), NOT service_role.
-- So a service_role-only policy would break the admin UI. The correct predicate
-- is "this is a real signed-in user whose role is admin", carried by Supabase's
-- `app_metadata` (which users cannot edit themselves) or by an admins table.
--
-- Idempotent: safe to run more than once.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Admin identities
-- ---------------------------------------------------------------------------
-- Deliberately a table rather than a hardcoded email. app_metadata is the
-- tamper-proof carrier, but promoting a second admin should not require a
-- migration.

create table if not exists public.admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  email      text,
  note       text,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 2. The predicate
-- ---------------------------------------------------------------------------
-- SECURITY DEFINER so the check itself is not subject to RLS on public.admins
-- (which would recurse). STABLE so Postgres caches it per statement.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from public.admins a
    where a.user_id = auth.uid()
  )
  or coalesce(
       (auth.jwt() -> 'app_metadata' ->> 'role') in ('admin', 'service_role'),
       false
     );
$$;

comment on function public.is_admin() is
  'True for rows in public.admins, or a JWT whose app_metadata.role is admin/service_role. app_metadata is server-set and cannot be edited by the user, unlike user_metadata.';

alter table public.admins enable row level security;

drop policy if exists "Admins can read admins" on public.admins;
create policy "Admins can read admins" on public.admins
  for select using (public.is_admin());

-- No write policy at all: admins are granted by service_role / SQL only.
-- Adding an admin is a deliberate act, never something the anon key can do.

-- ---------------------------------------------------------------------------
-- 3. Replace the permissive write policies
-- ---------------------------------------------------------------------------
-- service_role bypasses RLS entirely, so the seed and any migration keep working
-- without a policy of their own.

do $$
declare
  t text;
begin
  foreach t in array array['products','variants','product_images','collections',
                           'embroidery_details','categories','garments','motifs','universes']
  loop
    -- only touch tables that exist
    if exists (select 1 from pg_tables where schemaname='public' and tablename=t) then
      execute format('drop policy if exists "Allow admin insert %1$s" on public.%1$I', t);
      execute format('drop policy if exists "Allow admin update %1$s" on public.%1$I', t);
      execute format('drop policy if exists "Allow admin delete %1$s" on public.%1$I', t);
      -- singular/plural naming drift in the original schema
      execute format('drop policy if exists "Allow admin insert product images" on public.%1$I', t);
      execute format('drop policy if exists "Allow admin delete product images" on public.%1$I', t);
      execute format('drop policy if exists "Allow admin insert embroidery details" on public.%1$I', t);
      execute format('drop policy if exists "Allow admin update embroidery details" on public.%1$I', t);
      execute format('drop policy if exists "Allow admin delete embroidery details" on public.%1$I', t);

      execute format('drop policy if exists "Admins write %1$s" on public.%1$I', t);
      execute format(
        'create policy "Admins write %1$s" on public.%1$I for all
           using (public.is_admin()) with check (public.is_admin())', t);
    end if;
  end loop;
end $$;

commit;
