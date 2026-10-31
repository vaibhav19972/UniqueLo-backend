-- ====================================================================
-- local-bootstrap.sql — stub for PLAIN POSTGRES ONLY
--
-- *** NEVER RUN THIS ON SUPABASE. ***
-- Supabase already provides `auth`, `auth.users`, `auth.uid()`, `storage.*`
-- and the anon/authenticated/service_role roles. This file creates *fake*
-- versions so that schema.sql and the migration chain can be executed against
-- a throwaway local PostgreSQL for verification. Running it against Supabase
-- would either fail (objects exist) or, worse, shadow real auth with a stub
-- whose auth.uid() always returns null.
--
-- ORDER (plain Postgres only):
--   psql -f scripts/local-bootstrap.sql
--   psql -f schema.sql
--   psql -f production-seed.sql
--   psql -f migrations/<each, sorted>
--
-- WHY IT EXISTS
-- -------------
-- schema.sql is Supabase-targeted by design (it also creates storage buckets
-- and storage policies). That makes it unrunnable on bare Postgres, which is
-- why every schema claim up to 2026-10-31 was a text comparison and not a
-- build. This stub removes that excuse. If the chain cannot be applied here,
-- the baseline is wrong.
--
-- The shape mirrors what scripts/verify-customer-accounts.sql already assumes.
-- ====================================================================

-- Extensions FIRST: schema.sql's defaults call gen_random_uuid() and
-- uuid_generate_v4(). They are core in PG13+, but relying on that is a trap for
-- anyone building on an older image.
create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto;

-- Roles Supabase grants by default. NOLOGIN: they exist to be SET ROLE'd into.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- auth — identity. Only the columns our FKs and RLS predicates actually touch.
-- ---------------------------------------------------------------------------
create schema if not exists auth;

create table if not exists auth.users (
  id         uuid primary key default gen_random_uuid(),
  email      text unique,
  created_at timestamptz not null default now()
);

-- Supabase reads the caller's identity from the request JWT. A plain-Postgres
-- run has no JWT, so this returns NULL — which is exactly the anonymous
-- posture. Verification scripts that need a signed-in user SET ROLE and
-- override this function, or insert into auth.users and swap the body.
-- Reads a session GUC so a test can simulate a signed-in caller:
--   set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
-- Returning a bare NULL would make verify-customer-accounts.sql T7
-- ("signed-in checkout -> user_id = auth.uid()") exercise the ANONYMOUS path
-- and pass for the wrong reason — the exact trap that file already documents
-- for storage.objects RLS.
create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create or replace function auth.role() returns text
language sql stable as $$ select 'anon'::text $$;

-- ---------------------------------------------------------------------------
-- storage — buckets + objects. schema.sql inserts a bucket and creates
-- policies on storage.objects, so both must exist before it runs.
-- ---------------------------------------------------------------------------
create schema if not exists storage;

create table if not exists storage.buckets (
  id         text primary key,
  name       text not null,
  public     boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists storage.objects (
  id         uuid primary key default gen_random_uuid(),
  bucket_id  text references storage.buckets(id),
  name       text not null,
  owner      uuid,
  created_at timestamptz not null default now()
);

-- RLS on storage.objects, matching Supabase. Without this the storage policies
-- are inert and any "anon cannot upload" assertion passes for the wrong reason
-- (measured 2026-10-29 in verify-customer-accounts.sql).
alter table storage.objects enable row level security;

-- ---------------------------------------------------------------------------
-- Baseline privileges — Supabase grants these, RLS is what actually gates.
-- ---------------------------------------------------------------------------
grant usage on schema public to anon, authenticated, service_role;
grant usage on schema auth   to anon, authenticated, service_role;
grant usage on schema storage to anon, authenticated, service_role;

grant select on auth.users to authenticated, service_role;

grant select, insert, update, delete on storage.objects to anon, authenticated;
grant select on storage.buckets to anon, authenticated;

