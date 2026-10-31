#!/bin/bash
# Prove the schema chain applies on plain Postgres.
# Every schema claim up to 2026-10-31 was a text comparison. This is the build.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

# Cluster lives in a throwaway dir, never in the repo and never in a path that
# another project may already be using.
PGDATA="$(mktemp -d "${TMPDIR:-/tmp}/pg-uniquelo.XXXXXX")/data"
# Guard the rm -rf: only ever delete inside the scratch tree.
case "$PGDATA" in
  */pg-uniquelo.*/data) ;;
  *) echo "refusing: PGDATA is not a mktemp cluster dir"; exit 1 ;;
esac

SOCK="$PGDATA/sock"
PORT=55432
LOG=/tmp/pg-build.log
: > "$LOG"

export PATH="/opt/homebrew/bin:$PATH"

# Postgres 16 refuses to start when LANG/LC_ALL are unset but LC_CTYPE is set:
# "FATAL: postmaster became multithreaded during startup. HINT: Set the LC_ALL
# environment variable to a valid locale." That is what killed the first run.
export LC_ALL=C
export LANG=C

cleanup() {
  pg_ctl -D "$PGDATA" -s -m immediate stop >/dev/null 2>&1 || true
}
# Without this an early exit leaves a postmaster holding the port — which is
# exactly how the stale cluster that blocked attempt #1 was created.
trap cleanup EXIT

pg_ctl -D "$PGDATA" -s stop >/dev/null 2>&1 || true
rm -rf "$PGDATA"

echo "=== initdb ===" | tee -a "$LOG"
initdb -D "$PGDATA" -U postgres --encoding=UTF8 --locale=C > "$LOG" 2>&1 \
  || { tail -30 "$LOG"; exit 1; }

mkdir -p "$SOCK"

echo "=== start on :$PORT (socket in $SOCK) ===" | tee -a "$LOG"
# -k keeps the socket out of /tmp, so the user's own cluster on 5432 and the
# /tmp/.s.PGSQL.<port> lock can never collide with this one.
pg_ctl -D "$PGDATA" \
  -o "-p $PORT -k $SOCK -c listen_addresses=" \
  -l /tmp/pg-server.log start >> "$LOG" 2>&1 \
  || { tail -30 /tmp/pg-server.log; exit 1; }
sleep 2

PSQL="psql -X -q -v ON_ERROR_STOP=1 -h $SOCK -p $PORT -U postgres"

$PSQL -d postgres -c "create database uniquelo;" >> "$LOG" 2>&1 \
  || { echo "createdb FAILED" | tee -a "$LOG"; tail -20 "$LOG"; exit 1; }
PSQL_D="psql -X -q -v ON_ERROR_STOP=1 -h $SOCK -p $PORT -U postgres -d uniquelo"

step() { echo "=== $* ===" | tee -a "$LOG"; }

step "[1/4] local-bootstrap.sql"
$PSQL_D -f "$REPO/scripts/local-bootstrap.sql" >> "$LOG" 2>&1 \
  && echo "  OK bootstrap" | tee -a "$LOG" \
  || { echo "  FAIL bootstrap" | tee -a "$LOG"; grep -iE "error|fatal" "$LOG" | tail -10; exit 1; }

step "[2/4] schema.sql"
$PSQL_D -f "$REPO/schema.sql" >> "$LOG" 2>&1 \
  && echo "  OK schema.sql" | tee -a "$LOG" \
  || { echo "  FAIL schema.sql" | tee -a "$LOG"; grep -iE "error|fatal" "$LOG" | tail -15; exit 1; }

step "[3/4] migrations (sorted)"
for f in $(ls "$REPO"/migrations/*.sql | sort); do
  n=$(basename "$f")
  if $PSQL_D -f "$f" >> "$LOG" 2>&1; then
    echo "  OK   $n" | tee -a "$LOG"
  else
    echo "  FAIL $n" | tee -a "$LOG"
    echo "  --- error ---" | tee -a "$LOG"
    grep -iE "error:|violates|does not exist" "$LOG" | tail -6 | tee -a "$LOG"
    exit 1
  fi
done

step "[4/4] production-seed.sql"
$PSQL_D -f "$REPO/production-seed.sql" >> "$LOG" 2>&1 \
  && echo "  OK production-seed.sql" | tee -a "$LOG" \
  || { echo "  FAIL production-seed.sql" | tee -a "$LOG"; grep -iE "error:|violates" "$LOG" | tail -15; exit 1; }

echo | tee -a "$LOG"
step "CHAIN APPLIED — functional proofs"
$PSQL_D -At -c "
select 'products       = ' || count(*) from public.products
union all select 'variants       = ' || count(*) from public.variants
union all select 'product_images = ' || count(*) from public.product_images
union all select 'coupons        = ' || count(*) from public.coupons
union all select 'shipping_rules = ' || count(*) from public.shipping_rules;
" 2>&1 | tee -a "$LOG"

echo "--- quote_order on the seeded catalogue --------------------------------" | tee -a "$LOG"
echo "--- (a pre-fix fresh build could not even make this call) --------------" | tee -a "$LOG"
$PSQL_D -At -c "
select public.quote_order(
  jsonb_build_array(jsonb_build_object(
    'variant_sku', (select sku from public.variants where quantity > 0 limit 1),
    'quantity', 1))
);" 2>&1 | tee -a "$LOG"

echo "--- RLS posture on the restored + gateway tables -----------------------" | tee -a "$LOG"
$PSQL_D -At -c "
select c.relname || '  rls=' || c.relrowsecurity || '  policies=' || count(p.polname)
from pg_class c join pg_namespace n on n.oid=c.relnamespace
left join pg_policy p on p.polrelid=c.oid
where n.nspname='public'
  and c.relname in ('admins','coupons','shipping_rules','coupon_redemptions',
                    'customer_addresses','customer_wishlists','attribute_definitions',
                    'payment_intents')
group by c.relname, c.relrowsecurity order by c.relname;" 2>&1 | tee -a "$LOG"

# The ledger must be unreachable from a publishable key. A grant here would mean
# any browser could read or rewrite payments, so prove it rather than assume it.
echo "--- anon/authenticated grants on payment_intents (expect none) ---------" | tee -a "$LOG"
$PSQL_D -At -c "
select coalesce(string_agg(grantee, ', '), 'none')
from information_schema.table_privileges
where table_schema='public' and table_name='payment_intents'
  and grantee in ('anon','authenticated');" 2>&1 | tee -a "$LOG"

step "DONE"
