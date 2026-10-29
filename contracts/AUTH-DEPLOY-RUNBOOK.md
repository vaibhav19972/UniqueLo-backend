# Deploy runbook — customer auth (run in this order)

Paste each block into **Supabase Dashboard → SQL Editor**. Run them one at a
time and check the stated result before moving on. Every block is idempotent, so
a re-run is safe.

Project: `heimnfjuwmmmejqcjbbd`

---

## Step 1 — Admin gate (`20261025`)

Paste the whole of `backend/migrations/20261025_admin_write_policies.sql`.

**Check:** no error. (Expect `NOTICE: policy ... does not exist, skipping` — that
is normal on a first run.)

> This creates `public.admins` and `public.is_admin()`. It does **not** close the
> write path on its own — see Step 3.

---

## Step 2 — Bootstrap the admin

Paste `backend/scripts/bootstrap-admin.sql`.

**Check before running:** the file starts with a `select` of `auth.users`. Run
that first and confirm your Admin Studio account appears. If the email is not
`admin@uniquelo.com`, edit line 1 of the insert.

**Check after:** the final `select count(*) as admin_count` returns **1**. If it
returns 0, the email matched nothing and `/admin` will be read-only until fixed.

> **Skipping this leaves the Admin Studio unable to write.** `20261025` gates
> writes on `public.admins`; an empty table means every write is refused,
> including yours.

---

## Step 3 — Customer accounts (`20261031`)

Paste the whole of `backend/migrations/20261031_customer_accounts.sql`.

This one does five things:

| § | Effect |
|---|---|
| 0 | Refuses to run if `is_admin()` is missing (i.e. Step 1 was skipped) |
| 1 | `orders.user_id` + index + "users view own orders" policy |
| 2 | `customer_addresses` + RLS + one-default-per-user index + pincode check |
| 3 | `customer_wishlists` + RLS (no FK to products — see D-18) |
| 4 | `place_order` rewritten: `user_id` derived from `auth.uid()`, never trusted from the payload |
| 5 | storage uploads re-gated on `is_admin()` |
| **5b** | **drops the legacy `Authenticated admin write` policies — this is what actually locks the catalogue** |
| 5c | revokes anon INSERT on `orders`/`order_items` |
| 6 | `attribute_definitions` added to the admin-gated set |

**Check:** no error.

---

## Step 4 — Prove it

Run these from a terminal with your publishable key (`K`) and URL (`U`).

### 4a. Anon cannot write the catalogue

```bash
# EXPECT: 401 / 42501 / "violates row-level security policy"
# If you get 23502 (not-null violation) the hole is STILL OPEN.
curl -s -X POST "$U/rest/v1/garments" \
  -H "apikey: $K" -H "Authorization: Bearer $K" \
  -H "Content-Type: application/json" -H "Prefer: return=minimal" \
  -d '{"name":null,"slug":null}' -w '\nHTTP %{http_code}\n'
```

> **Why the error code matters:** `23502` means Postgres reached the table's
> not-null constraint, which can only happen *after* privilege + RLS passed.
> `42501` means RLS refused. Only `42501` proves the lock.

### 4b. Signed-in non-admin cannot write the catalogue

This is the OA-6 test. It needs a real customer session — do it after Step 6.

### 4c. Guest checkout still works

```bash
# EXPECT: {"id": "...", "user_id": null, ...} — NULL is the point
SKU=$(curl -s "$U/rest/v1/variants?select=sku&limit=1" -H "apikey: $K" -H "Authorization: Bearer $K" | python3 -c 'import json,sys;print(json.load(sys.stdin)[0]["sku"])')

curl -s -X POST "$U/rest/v1/rpc/place_order" \
  -H "apikey: $K" -H "Authorization: Bearer $K" \
  -H "Content-Type: application/json" \
  -d "{\"p_order\":{\"customer_name\":\"Runbook Probe\",\"customer_email\":\"runbook@example.com\"},\"p_items\":[{\"variant_sku\":\"$SKU\",\"quantity\":1}]}"
```

**This writes a real order.** Delete it afterwards in the dashboard
(`orders where customer_email = 'runbook@example.com'` + its `order_items`).
There is no anon delete path by design.

---

## Step 5 — Enable phone OTP

Dashboard → **Authentication → Providers → Phone**.

1. Enable **Phone**.
2. Add an SMS provider. Twilio is native but expensive for India (~₹11/OTP via
   Verify); MSG91 (~₹0.15) needs the **Send SMS Hook** + an Edge Function.
   For dev, enable Twilio with placeholder creds and use **test phone numbers**
   instead — see Step 5a.
3. Set **OTP expiry** to 300s (default 60s is too short for real users on 4G).

### 5a. Test numbers (works without any SMS spend)

Authentication → Providers → Phone → **Test phone numbers**.
Add `91` + your number, e.g. `919876543210`, with a fixed OTP like `123456`.
The fixed code is accepted repeatedly and no SMS is sent.

> A provider still has to be *configured* for test numbers to work — Supabase
> requires one even though it sends nothing.

### 5b. India-specific blocker (real users)

Indian SMS needs **DLT registration**: entity (PE) ID, sender ID, and a
registered template. Without it, domestic sends are filtered.
- Twilio **international** route needs no DLT, but costs ~₹0.45–11/OTP and
  delivery is less reliable.
- MSG91 / Fast2SMS / Gupshup need DLT and cost ~₹0.15/OTP.

**This blocks real users, not development.** Start the DLT registration now if
launch is near — it takes days, not minutes.

---

## Step 6 — Verify the admin gate end-to-end

```bash
# 1. Sign in as the admin (Admin Studio account)
TOKEN=$(curl -s -X POST "$U/auth/v1/token?grant_type=password" \
  -H "apikey: $K" -H "Content-Type: application/json" \
  -d '{"email":"admin@uniquelo.com","password":"..."}' | python3 -c 'import json,sys;print(json.load(sys.stdin)["access_token"])')

# 2. is_admin() must be true
curl -s -X POST "$U/rest/v1/rpc/is_admin" \
  -H "apikey: $K" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{}'

# 3. Create ONE throwaway customer (Dashboard → Authentication → Users → Add user)
#    then repeat steps 1-2 with that account's credentials.
#    EXPECT: is_admin() -> false
```

**Pass condition:** admin `true`, customer `false`, catalogue write succeeds for
admin and returns `42501` for the customer.

---

## Rollback

Each block is additive and idempotent. To undo `20261031` only:

```sql
-- Re-open the write path (NOT recommended while customers can sign up)
drop policy if exists "Users view own orders" on public.orders;
drop table if exists public.customer_addresses;
drop table if exists public.customer_wishlists;
alter table public.orders drop column if exists user_id;
-- storage + place_order need their prior definitions from 20260104 / 20261030
```

There is no automatic rollback for the `place_order` rewrite — restore it from
`backend/migrations/20261030_harden_place_order.sql` if needed.
