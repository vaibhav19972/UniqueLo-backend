/**
 * Razorpay — shared server logic for the Edge Functions.
 *
 * CONSTRAINT THAT SHAPES THIS FILE: it must run unmodified under Deno
 * (production) AND under Node (the signature proof in
 * `scripts/verify-razorpay-signature.mjs`). So it uses only globals that exist in
 * both — `fetch`, `crypto.subtle`, `TextEncoder`, `btoa` — and imports nothing.
 * One implementation of the HMAC, proven by execution rather than by reading.
 *
 * The KEY SECRET never leaves the caller's env. Nothing here is imported by the
 * web bundle.
 */

/** Razorpay wants Basic auth: base64("key_id:key_secret"). */
export function authHeader(keyId: string, keySecret: string): string {
  return `Basic ${btoa(`${keyId}:${keySecret}`)}`;
}

function toHex(buf: ArrayBuffer): string {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * The signature Razorpay should have sent:
 *   HMAC-SHA256(order_id + "|" + payment_id, key_secret)
 * rendered lowercase hex.
 */
export async function expectedSignature(
  orderId: string,
  paymentId: string,
  keySecret: string
): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(keySecret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );
  const mac = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(`${orderId}|${paymentId}`)
  );
  return toHex(mac);
}

/**
 * Constant-time comparison.
 *
 * `===` on two hex strings leaks how many leading characters matched, which over
 * enough attempts is a signature oracle. The XOR accumulation below always walks
 * the full string, so it cannot short-circuit at the first differing byte.
 */
export function timingSafeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** True only when `signature` is the exact HMAC of this order/payment pair. */
export async function verifySignature(
  orderId: string,
  paymentId: string,
  signature: string,
  keySecret: string
): Promise<boolean> {
  if (!orderId || !paymentId || !signature) return false;
  const expected = await expectedSignature(orderId, paymentId, keySecret);
  return timingSafeEqualHex(expected, signature);
}

export class RazorpayApiError extends Error {
  constructor(
    message: string,
    readonly status: number
  ) {
    super(message);
    this.name = 'RazorpayApiError';
  }
}

export interface RazorpayPayment {
  id: string;
  order_id: string;
  amount: number;
  currency: string;
  status: string;
  error_description?: string;
}

/**
 * A signature proves the PAIR, not the AMOUNT. Razorpay's docs are explicit that
 * a valid signature only means "these ids belong together", so a payment of ₹1
 * against an order created for ₹3,898 would still verify. Callers must also check
 * `amount` and `status`. That read lives here so a call site cannot skip it.
 */
export async function fetchPayment(
  paymentId: string,
  keyId: string,
  keySecret: string
): Promise<RazorpayPayment> {
  const res = await fetch(
    `https://api.razorpay.com/v1/payments/${encodeURIComponent(paymentId)}`,
    { headers: { Authorization: authHeader(keyId, keySecret) } }
  );
  const body = await res.json();
  if (!res.ok) {
    throw new RazorpayApiError(
      body?.error?.description ?? `Could not read payment ${paymentId} (${res.status}).`,
      res.status
    );
  }
  return body as RazorpayPayment;
}

/**
 * Capture an authorised payment.
 *
 * Needed because `payment_capture: 1` on the order is a REQUEST, not a guarantee:
 * accounts with auto-capture configured server-side may already capture, and
 * accounts without it leave the payment `authorized`. An authorisation is not
 * money — it expires unpaid — so `verify` must not treat one as settled. This is
 * the difference between telling a customer "paid" and being paid.
 */
export async function capturePayment(
  paymentId: string,
  amount: number,
  currency: string,
  keyId: string,
  keySecret: string
): Promise<RazorpayPayment> {
  const res = await fetch(
    `https://api.razorpay.com/v1/payments/${encodeURIComponent(paymentId)}/capture`,
    {
      method: 'POST',
      headers: {
        Authorization: authHeader(keyId, keySecret),
        'Content-Type': 'application/json',
      },
      // amount/currency are required by the capture endpoint; passing the
      // gateway's own figures back avoids any client influence on the sum.
      body: JSON.stringify({ amount, currency }),
    }
  );
  const body = await res.json();
  if (!res.ok) {
    throw new RazorpayApiError(
      body?.error?.description ?? `Could not capture payment ${paymentId} (${res.status}).`,
      res.status
    );
  }
  return body as RazorpayPayment;
}

export interface CreateOrderResult {
  id: string;
  amount: number;
  currency: string;
  status: string;
}

/**
 * Create a Razorpay order.
 *
 * `payment_capture: 1` AUTO-CAPTURES on success. That is deliberate: with 0 the
 * payment lands `authorized` and a valid signature would only prove
 * authorisation, not settlement — the customer would be told "paid" for money
 * that can still expire. Auto-capture keeps "signature valid ⇒ paid" true and
 * needs no separate capture call or webhook. The tradeoff is that refunds are
 * the only reversal, which is the correct default for a small atelier.
 *
 * `receipt` is capped at 40 chars by Razorpay; a dashed UUID is 36.
 */
export async function createRazorpayOrder(
  opts: { amountCents: number; receipt: string; notes?: Record<string, string> },
  keyId: string,
  keySecret: string
): Promise<CreateOrderResult> {
  if (!Number.isInteger(opts.amountCents) || opts.amountCents < 100) {
    throw new RazorpayApiError(
      `Amount must be an integer number of paise and at least 100 (got ${opts.amountCents}).`,
      400
    );
  }

  const res = await fetch('https://api.razorpay.com/v1/orders', {
    method: 'POST',
    headers: {
      Authorization: authHeader(keyId, keySecret),
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      amount: opts.amountCents,
      currency: 'INR',
      receipt: opts.receipt,
      payment_capture: 1,
      notes: opts.notes ?? {},
    }),
  });

  const body = await res.json();
  if (!res.ok) {
    // 401 means the key pair is wrong or revoked — the caller must surface that
    // as an operator problem, not a declined card.
    throw new RazorpayApiError(
      body?.error?.description ?? `Razorpay order creation failed (${res.status})`,
      res.status
    );
  }
  return body as CreateOrderResult;
}

export const CORS_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}
