#!/bin/bash
# Functional proof for 20261105_order_payment_identity.sql.
#
# `verify-chain.sh` proves the chain APPLIES. It does not prove the new column
# records the right thing. This does: real place_order calls on a throwaway
# cluster, reading back what was actually written.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

PGDATA="$(mktemp -d "${TMPDIR:-/tmp}/pg-payment.XXXXXX")/data"
case "$PGDATA" in
  */pg-payment.*/data) ;;
  *) echo "refusing: PGDATA is not a mktemp cluster dir"; exit 1 ;;
esac
SOCK="$PGDATA/sock"
PORT=55433
LOG=/tmp/pg-payment.log
: > "$LOG"

export PATH="/opt/homebrew/bin:$PATH"
export LC_ALL=C
export LANG=C

cleanup() { pg_ctl -D "$PGDATA" -s -m immediate stop >/dev/null 2>&1 || true; }
trap cleanup EXIT

pg_ctl -D "$PGDATA" -s stop >/dev/null 2>&1 || true
rm -rf "$PGDATA"

initdb -D "$PGDATA" -U postgres --encoding=UTF8 --locale=C > "$LOG" 2>&1 \
  || { tail -20 "$LOG"; exit 1; }
mkdir -p "$SOCK"
pg_ctl -D "$PGDATA" -o "-p $PORT -k $SOCK -c listen_addresses=" \
  -l /tmp/pg-payment-server.log start >> "$LOG" 2>&1 \
  || { tail -20 /tmp/pg-payment-server.log; exit 1; }
sleep 2

PSQL="psql -X -q -v ON_ERROR_STOP=1 -h $SOCK -p $PORT -U postgres -d uniquelo"
psql -X -q -h "$SOCK" -p "$PORT" -U postgres -d postgres -c "create database uniquelo;" >> "$LOG" 2>&1

$PSQL -f "$REPO/scripts/local-bootstrap.sql" >> "$LOG" 2>&1 || { echo "FAIL bootstrap"; grep -i error "$LOG"|tail -5; exit 1; }
$PSQL -f "$REPO/schema.sql" >> "$LOG" 2>&1 || { echo "FAIL schema"; grep -i error "$LOG"|tail -5; exit 1; }
for f in $(ls "$REPO"/migrations/*.sql | sort); do
  $PSQL -f "$f" >> "$LOG" 2>&1 || { echo "FAIL $(basename $f)"; grep -iE 'error:|violates' "$LOG"|tail -8; exit 1; }
done
$PSQL -f "$REPO/production-seed.sql" >> "$LOG" 2>&1 || { echo "FAIL seed"; grep -iE 'error:|violates' "$LOG"|tail -8; exit 1; }

FAIL=0
chk() { # chk <label> <expected> <actual>
  if [ "$2" = "$3" ]; then printf "  PASS  %-52s %s\n" "$1" "$3"
  else printf "  FAIL  %-52s expected=%s actual=%s\n" "$1" "$2" "$3"; FAIL=1; fi
}

SKU=$($PSQL -At -c "select sku from public.variants where quantity > 10 limit 1")
PRE_ID=$(uuidgen | tr 'A-Z' 'a-z')
COD_ID=$(uuidgen | tr 'A-Z' 'a-z')

echo "=== place_order writes payment_method ==="

# --- prepaid ---
$PSQL -At -c "
select public.place_order(
  jsonb_build_object(
    'id', '$PRE_ID',
    'customer_name', 'Prepaid Probe',
    'customer_email', 'prepaid@uniquelo.test',
    'shipping_address', jsonb_build_object('address','x','payment_method','prepaid')
  ),
  jsonb_build_array(jsonb_build_object(
    'id', gen_random_uuid()::text,
    'product_slug','probe','variant_sku','$SKU','product_name','Probe',
    'color','Cream','size','M','quantity',1
  ))
);" > /dev/null 2>>"$LOG" || { echo "place_order prepaid FAILED"; tail -5 "$LOG"; exit 1; }

chk "prepaid order stores payment_method" "prepaid" \
  "$($PSQL -At -c "select payment_method from public.orders where id='$PRE_ID'")"
chk "prepaid order has NULL payment_ref" "NULL" \
  "$($PSQL -At -c "select coalesce(payment_ref,'NULL') from public.orders where id='$PRE_ID'")"
chk "prepaid order status" "confirmed" \
  "$($PSQL -At -c "select status from public.orders where id='$PRE_ID'")"

# --- cod ---
$PSQL -At -c "
select public.place_order(
  jsonb_build_object(
    'id', '$COD_ID',
    'customer_name', 'COD Probe',
    'customer_email', 'cod@uniquelo.test',
    'shipping_address', jsonb_build_object('address','x','payment_method','cod')
  ),
  jsonb_build_array(jsonb_build_object(
    'id', gen_random_uuid()::text,
    'product_slug','probe','variant_sku','$SKU','product_name','Probe',
    'color','Cream','size','M','quantity',1
  ))
);" > /dev/null 2>>"$LOG" || { echo "place_order cod FAILED"; tail -5 "$LOG"; exit 1; }

chk "COD order stores payment_method" "cod" \
  "$($PSQL -At -c "select payment_method from public.orders where id='$COD_ID'")"
chk "COD order status" "confirmed-cod" \
  "$($PSQL -At -c "select status from public.orders where id='$COD_ID'")"

echo
echo "=== the two rows are now DISTINGUISHABLE (was the whole point) ==="
chk "distinct payment_method values in table" "2" \
  "$($PSQL -At -c "select count(distinct payment_method) from public.orders")"

echo
echo "=== a junk method collapses to prepaid, it does NOT abort the sale ==="
JUNK_ID=$(uuidgen | tr 'A-Z' 'a-z')
$PSQL -At -c "
select public.place_order(
  jsonb_build_object('id','$JUNK_ID','customer_name','Junk','customer_email','junk@uniquelo.test',
    'shipping_address', jsonb_build_object('address','x','payment_method','UPI-NONSENSE')),
  jsonb_build_array(jsonb_build_object('id',gen_random_uuid()::text,'product_slug','probe',
    'variant_sku','$SKU','product_name','Probe','color','Cream','size','M','quantity',1))
);" > /dev/null 2>>"$LOG" || { echo "junk method ABORTED the order (regression)"; tail -5 "$LOG"; exit 1; }
chk "junk method normalised to prepaid" "prepaid" \
  "$($PSQL -At -c "select payment_method from public.orders where id='$JUNK_ID'")"

echo
echo "=== the CHECK actually rejects a bad value (positive control) ==="
BAD=$($PSQL -At -c "insert into public.orders (id,customer_name,customer_email,subtotal_cents,total_cents,payment_method)
  values (gen_random_uuid(),'x','x@y.z',100,100,'bitcoin') returning 1;" 2>&1)
case "$BAD" in
  *orders_payment_method_valid*) echo "  PASS  constraint rejected 'bitcoin'" ;;
  *) echo "  FAIL  expected orders_payment_method_valid, got: $BAD"; FAIL=1 ;;
esac

echo
echo "=== one payment_ref cannot settle two orders ==="
$PSQL -q -c "update public.orders set payment_ref='pay_PROBE123' where id='$PRE_ID';" 2>>"$LOG"
DUP=$(psql -X -q -v ON_ERROR_STOP=1 -h "$SOCK" -p "$PORT" -U postgres -d uniquelo -At \
  -c "update public.orders set payment_ref='pay_PROBE123' where id='$COD_ID';" 2>&1)
case "$DUP" in
  *idx_orders_payment_ref*|*duplicate*) echo "  PASS  duplicate payment_ref rejected" ;;
  *) echo "  FAIL  duplicate payment_ref was ALLOWED"; FAIL=1 ;;
esac
chk "the original keeps its payment_ref" "pay_PROBE123" \
  "$($PSQL -At -c "select payment_ref from public.orders where id='$PRE_ID'")"

echo
echo "=== NULL payment_ref is not treated as a duplicate (COD path) ==="
# The point is that SEVERAL orders may carry NULL (every COD order does). A plain
# unique index would still allow that, but a wrong predicate here would not — so
# assert the count of NULL rows is >1 and that all of them were accepted.
NULL_COUNT=$($PSQL -At -c "select count(*) from public.orders where payment_ref is null")
if [ "$NULL_COUNT" -gt 1 ]; then
  echo "  PASS  multiple NULL payment_ref rows coexist            $NULL_COUNT"
else
  echo "  FAIL  expected >1 NULL payment_ref rows, got $NULL_COUNT"; FAIL=1
fi
chk "exactly one row holds the stamped ref" "1" \
  "$($PSQL -At -c "select count(*) from public.orders where payment_ref='pay_PROBE123'")"

echo
if [ "$FAIL" -eq 0 ]; then echo "ALL PAYMENT-IDENTITY PROOFS PASSED"; else echo "SOME PROOFS FAILED"; fi
exit $FAIL
