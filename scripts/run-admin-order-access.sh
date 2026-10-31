#!/bin/bash
# Run verify-admin-order-access.sql against a throwaway cluster.
#
# The battery mirrors Supabase's posture (table-wide grants to anon/authenticated)
# BEFORE asserting, because plain Postgres does not grant those by default — that
# is the only way 20261103's revoke is observable locally.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

BASE="$(mktemp -d "${TMPDIR:-/tmp}/pg-admin.XXXXXX")"
PGDATA="$BASE/data"
SOCK="$BASE/sock"
PORT=55437
LOG=/tmp/pg-admin-access.log
: > "$LOG"

export PATH="/opt/homebrew/bin:$PATH"
# PG16 refuses to start with LANG/LC_ALL unset while LC_CTYPE is set.
export LC_ALL=C LANG=C

cleanup() { pg_ctl -D "$PGDATA" -s -m immediate stop >/dev/null 2>&1 || true; rm -rf "$BASE"; }
trap cleanup EXIT

initdb -D "$PGDATA" -U postgres --encoding=UTF8 --locale=C >"$LOG" 2>&1 || { tail -20 "$LOG"; exit 1; }
mkdir -p "$SOCK"
pg_ctl -D "$PGDATA" -o "-p $PORT -k $SOCK -c listen_addresses=" -l "$BASE/srv.log" start >>"$LOG" 2>&1 || { tail -20 "$BASE/srv.log"; exit 1; }
sleep 2

P="psql -X -q -h $SOCK -p $PORT -U postgres"
$P -d postgres -c "create database t" >>"$LOG" 2>&1 || exit 1
D="psql -X -q -v ON_ERROR_STOP=1 -h $SOCK -p $PORT -U postgres -d t"

$D -f "$REPO/scripts/local-bootstrap.sql" >>"$LOG" 2>&1 || { echo "bootstrap FAILED"; tail -10 "$LOG"; exit 1; }
$D -f "$REPO/schema.sql"                 >>"$LOG" 2>&1 || { echo "schema FAILED";   tail -10 "$LOG"; exit 1; }
for f in $(ls "$REPO"/migrations/*.sql | sort); do
  $D -f "$f" >>"$LOG" 2>&1 || { echo "migration FAILED: $(basename "$f")"; tail -10 "$LOG"; exit 1; }
done
$D -f "$REPO/production-seed.sql" >>"$LOG" 2>&1 || { echo "seed FAILED"; tail -10 "$LOG"; exit 1; }

echo "############ battery output ############"
psql -X -q -h "$SOCK" -p "$PORT" -U postgres -d t \
  -f "$REPO/scripts/verify-admin-order-access.sql" 2>&1
