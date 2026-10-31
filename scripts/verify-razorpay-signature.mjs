#!/usr/bin/env node
/**
 * Prove the signature algorithm by execution, not by reading.
 *
 * WHY: `razorpay-verify` refuses a payment when this HMAC disagrees with
 * Razorpay's. If the implementation is wrong the failure mode is "every genuine
 * payment is rejected" — a hard outage that no typecheck catches. So the
 * PRODUCTION module is imported here directly and cross-checked against
 * `node:crypto`, which is an independent implementation of the same primitive.
 *
 * The `.ts` import works because Node 26 strips type annotations natively. That
 * is also the portability proof: the same file must run under Deno in
 * production, so anything Deno-only would fail here.
 *
 * WHAT THIS DOES NOT PROVE: that Razorpay computes it the same way. Only a real
 * modal payment settles that. This proves the code is correct against the
 * documented algorithm and self-consistent across two implementations.
 *
 * Usage: node backend/scripts/verify-razorpay-signature.mjs
 * Exit 0 = pass. No network. No real credentials (a fake secret is enough —
 * the algorithm does not care whether the key is live).
 */

import { createHmac, timingSafeEqual } from 'node:crypto';
import {
  expectedSignature,
  timingSafeEqualHex,
  verifySignature,
} from '../supabase/functions/_shared/razorpay.ts';

const RED = '\x1b[31m';
const GREEN = '\x1b[32m';
const OFF = '\x1b[0m';
const DIM = '\x1b[2m';

let failures = 0;

function check(name, cond, detail = '') {
  if (cond) {
    console.log(`  ${GREEN}ok${OFF}    ${name}`);
  } else {
    failures++;
    console.log(`  ${RED}FAIL${OFF}  ${name}${detail ? `\n        ${detail}` : ''}`);
  }
}

// A fixed vector. A fake secret is deliberate: committing a real one to prove an
// HMAC would be a worse bug than the one this guards against.
const SECRET = 'test_secret_not_a_real_key';
const ORDER = 'order_TuXE5nBYOJBU9K';
const PAYMENT = 'pay_TestPaymentId12345';

console.log('razorpay signature proof');
console.log(`${DIM}  algorithm: HMAC-SHA256(order_id|payment_id, key_secret), lowercase hex${OFF}\n`);

// ── 1. Agreement with node:crypto ──────────────────────────────────────────
const ours = await expectedSignature(ORDER, PAYMENT, SECRET);
const theirs = createHmac('sha256', SECRET).update(`${ORDER}|${PAYMENT}`).digest('hex');

check('crypto.subtle matches node:crypto for order|payment', ours === theirs, `ours=${ours} theirs=${theirs}`);

// ── 2. The separator is load-bearing ──────────────────────────────────────
// "a" + "bc" must not hash the same as "ab" + "c". If the pipe were dropped, an
// attacker could shift characters between the two ids.
const shifted = await expectedSignature(`${ORDER}|`, PAYMENT.slice(1), SECRET);
check('separator prevents id-boundary shifting', ours !== shifted);

// ── 3. verifySignature accepts the true signature ─────────────────────────
check('verifySignature accepts a genuine signature', await verifySignature(ORDER, PAYMENT, ours, SECRET));

// ── 4. …and rejects everything else ───────────────────────────────────────
check('rejects a wrong secret', !(await verifySignature(ORDER, PAYMENT, ours, 'other_secret')));
check('rejects a different payment id', !(await verifySignature(ORDER, 'pay_other', ours, SECRET)));
check('rejects a different order id', !(await verifySignature('order_other', PAYMENT, ours, SECRET)));
check('rejects an empty signature', !(await verifySignature(ORDER, PAYMENT, '', SECRET)));
check('rejects a truncated signature', !(await verifySignature(ORDER, PAYMENT, ours.slice(0, 32), SECRET)));
check('rejects an uppercase (non-hex-normalised) signature', !(await verifySignature(ORDER, PAYMENT, ours.toUpperCase(), SECRET)));

// ── 5. Constant-time comparison still returns the right answer ────────────
// The point of timingSafeEqualHex is side-channel resistance, which cannot be
// asserted in a unit test. What CAN be asserted is that it did not break the
// truth table — a "secure" comparator that returns false always is worse.
check('timingSafeEqualHex true on equal', timingSafeEqualHex('abcd', 'abcd'));
check('timingSafeEqualHex false on differing same-length', !timingSafeEqualHex('abcd', 'abce'));
check('timingSafeEqualHex false on length mismatch', !timingSafeEqualHex('abcd', 'abc'));

// Cross-check that the hex digest is well-formed lowercase hex of 64 chars.
check('signature is 64 lowercase hex chars', /^[0-9a-f]{64}$/.test(ours), `got ${ours}`);

// Confirm node:crypto would agree byte-for-byte, not just as strings.
check(
  'byte-level agreement with node:crypto',
  timingSafeEqual(Buffer.from(ours, 'hex'), Buffer.from(theirs, 'hex'))
);

console.log();
if (failures > 0) {
  console.log(`${RED}${failures} check(s) failed — do not deploy razorpay-verify.${OFF}`);
  process.exit(1);
}
console.log(`${GREEN}all checks passed${OFF} — the HMAC in _shared/razorpay.ts is correct per the documented algorithm.`);
console.log(`${DIM}Reminder: only a real modal payment proves Razorpay agrees.${OFF}`);
