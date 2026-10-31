/**
 * razorpay-verify — proves a payment is real, then places the order.
 *
 * ORDER OF OPERATIONS: price → charge → VERIFY → place_order. The order is only
 * written once money is proven settled. The alternative (reserve stock first with
 * status 'pending') was rejected because nothing in this repo sweeps abandoned
 * reservations — `20261102` reserved 'pending' but no writer and no cron exist —
 * so a closed tab would silently hold stock until someone noticed.
 *
 * The cost of this ordering is real and is recorded as KD-8: a settled payment
 * whose place_order call fails leaves money with no order. That row is the refund
 * queue, and the response says so honestly instead of claiming success.
 *
 * THREE CHECKS, NOT ONE. A valid signature only proves `order_id|payment_id` were
 * produced by Razorpay for our key. It says NOTHING about the amount, so a ₹1
 * payment against a ₹3,898 order would verify. This function therefore also:
 *   a) compares the payment's `amount` to the intent's `amount_cents`,
 *   b) requires the payment to be SETTLED (capturing it if it is only
 *      authorised — an authorisation can expire unpaid), and
 *   c) compares the paid amount to what place_order actually charged.
 * All three must agree or no order is written.
 */

import { createClient } from 'npm:@supabase/supabase-js@2';
import {
  capturePayment,
  CORS_HEADERS,
  fetchPayment,
  json,
  RazorpayApiError,
  verifySignature,
} from '../_shared/razorpay.ts';

interface RequestBody {
  razorpay_order_id: string;
  razorpay_payment_id: string;
  razorpay_signature: string;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const keyId = Deno.env.get('RAZORPAY_KEY_ID');
  const keySecret = Deno.env.get('RAZORPAY_KEY_SECRET');
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');

  if (!keyId || !keySecret) {
    return json({ error: 'Payment gateway is not configured.' }, 503);
  }
  if (!supabaseUrl || !serviceKey || !anonKey) {
    // anonKey is REQUIRED, not a fallback: it is what carries the customer's JWT
    // into place_order. Without it orders would be written with user_id = NULL
    // and a signed-in customer would lose their own order history.
    return json({ error: 'Server is misconfigured.' }, 503);
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid JSON body.' }, 400);
  }

  const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = body;

  // ── Check 0: all three fields present ─────────────────────────────────
  if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
    return json(
      { error: 'Missing razorpay_order_id, razorpay_payment_id or razorpay_signature.' },
      400
    );
  }

  // ── Check 1: the signature ────────────────────────────────────────────
  const valid = await verifySignature(
    razorpay_order_id,
    razorpay_payment_id,
    razorpay_signature,
    keySecret
  );

  if (!valid) {
    // Signature mismatch means someone is asserting a payment Razorpay did not
    // sign for this order. Nothing is written, nothing is marked paid.
    return json({ error: 'Payment signature verification failed.' }, 400);
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // ── Load the intent we created for this Razorpay order ────────────────
  const { data: intent, error: intentError } = await admin
    .from('payment_intents')
    .select('*')
    .eq('provider_order_id', razorpay_order_id)
    .maybeSingle();

  if (intentError) return json({ error: 'Could not read the payment record.' }, 500);
  if (!intent) {
    // A valid signature for an order we never created is either a replay from a
    // different environment (test/live key mixup) or an attack.
    return json({ error: 'No payment intent matches this Razorpay order.' }, 404);
  }

  // ── Idempotency: a retried verify must not double-place an order ──────
  // Covers the case where place_order succeeded but the intent update did not.
  // Checking the intent first is cheaper than provoking a duplicate-key error and
  // then having to decide whether 23505 means "already done" or "broken".
  if (intent.placed_order_id) {
    return json({ success: true, order_id: intent.placed_order_id, already_verified: true });
  }
  if (intent.status === 'expired' || intent.status === 'failed') {
    return json({ error: 'This payment attempt is closed. Please start a new one.' }, 409);
  }

  // ── Check 2: the amount actually paid ─────────────────────────────────
  let payment;
  try {
    payment = await fetchPayment(razorpay_payment_id, keyId, keySecret);
  } catch {
    return json({ error: 'Could not confirm this payment with the gateway.' }, 502);
  }

  if (payment.order_id !== razorpay_order_id) {
    return json({ error: 'Payment belongs to a different order.' }, 400);
  }
  if (payment.amount !== intent.amount_cents) {
    await admin
      .from('payment_intents')
      .update({
        status: 'captured',
        provider_payment_id: razorpay_payment_id,
        captured_at: new Date().toISOString(),
        failure_reason: `amount mismatch: paid ${payment.amount}, expected ${intent.amount_cents}`,
      })
      .eq('id', intent.id);
    return json(
      { error: 'The amount paid does not match this order. Our team will reconcile it.' },
      409
    );
  }

  // ── Settle: an authorisation is not money until it is captured ────────
  if (payment.status === 'authorized') {
    try {
      payment = await capturePayment(razorpay_payment_id, payment.amount, payment.currency, keyId, keySecret);
    } catch (err) {
      const detail = err instanceof RazorpayApiError ? err.message : 'capture failed';
      await admin
        .from('payment_intents')
        .update({
          status: 'authorized',
          provider_payment_id: razorpay_payment_id,
          failure_reason: `capture failed: ${detail}`,
        })
        .eq('id', intent.id);
      return json({ error: 'Payment could not be settled. No order was created.' }, 402);
    }
  }

  if (payment.status !== 'captured') {
    await admin
      .from('payment_intents')
      .update({
        status: payment.status === 'failed' ? 'failed' : 'created',
        provider_payment_id: razorpay_payment_id,
        failure_reason: payment.error_description ?? `payment status ${payment.status}`,
      })
      .eq('id', intent.id);
    return json({ error: `Payment is ${payment.status}, not captured.` }, 402);
  }

  // ── Place the order AS THE CUSTOMER ───────────────────────────────────
  // The caller's JWT is forwarded so place_order's `auth.uid()` populates
  // orders.user_id. Service role here would silently null ownership.
  const authHeader = req.headers.get('Authorization') ?? '';
  const asUser = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: authHeader ? { Authorization: authHeader } : {} },
  });

  // intent.items is the FULL line shape captured at create time. It is passed
  // through untouched: verification must never trust a cart the browser could
  // re-submit after the charge.
  const { data: placed, error: placeError } = await asUser.rpc('place_order', {
    p_order: {
      id: intent.client_order_id,
      customer_name: intent.customer_name ?? 'Valued Collector',
      customer_email: intent.customer_email,
      // No `status`: it is derived server-side. Supplying one is KD-6's sharp edge.
      coupon_code: intent.coupon_code,
      shipping_address: {
        ...(typeof intent.shipping_address === 'object' && intent.shipping_address
          ? intent.shipping_address
          : {}),
        payment_method: 'prepaid',
      },
    },
    p_items: intent.items,
  });

  if (placeError) {
    const isDuplicate = placeError.code === '23505' || /duplicate key/i.test(placeError.message);

    if (isDuplicate) {
      // place_order already ran for this client_order_id — a retry after a lost
      // response. The order exists; adopt it rather than telling a paid customer
      // their order failed.
      await admin
        .from('payment_intents')
        .update({
          status: 'captured',
          provider_payment_id: razorpay_payment_id,
          captured_at: intent.captured_at ?? new Date().toISOString(),
          placed_order_id: intent.client_order_id,
          failure_reason: null,
        })
        .eq('id', intent.id);
      return json({ success: true, order_id: intent.client_order_id, already_verified: true });
    }

    // Money is settled and the order could not be written: stock moved, or a
    // coupon expired between quote and pay. Mark the row and say so plainly —
    // this is the KD-8 refund queue.
    await admin
      .from('payment_intents')
      .update({
        status: 'captured',
        provider_payment_id: razorpay_payment_id,
        captured_at: new Date().toISOString(),
        failure_reason: `place_order failed: ${placeError.message}`,
      })
      .eq('id', intent.id);
    return json(
      {
        error:
          'Payment received but the order could not be completed — your bag changed while you paid. Our team will contact you to complete or refund it.',
        payment_id: razorpay_payment_id,
        retryable: false,
      },
      502
    );
  }

  // ── Check 3: did the server charge what was paid? ─────────────────────
  const placedTotal = Number(placed?.total_cents ?? NaN);
  if (!Number.isFinite(placedTotal) || placedTotal !== intent.amount_cents) {
    await admin
      .from('payment_intents')
      .update({
        status: 'captured',
        provider_payment_id: razorpay_payment_id,
        captured_at: new Date().toISOString(),
        placed_order_id: placed?.id ?? null,
        failure_reason: `totals disagree: paid ${intent.amount_cents}, order ${placedTotal}`,
      })
      .eq('id', intent.id);
    return json(
      {
        error: 'Your order total changed while you paid. Our team will reconcile the difference.',
        order_id: placed?.id ?? null,
        paid: intent.amount_cents,
        owed: placedTotal,
      },
      409
    );
  }

  const orderId = placed?.id ?? intent.client_order_id;

  // Guarded so two concurrent verifies cannot both win the write.
  await admin
    .from('payment_intents')
    .update({
      status: 'captured',
      provider_payment_id: razorpay_payment_id,
      captured_at: intent.captured_at ?? new Date().toISOString(),
      placed_order_id: orderId,
      failure_reason: null,
    })
    .eq('id', intent.id)
    .is('placed_order_id', null);

  return json({ success: true, order_id: orderId, payment_id: razorpay_payment_id });
});
