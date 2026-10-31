# Parity gaps — web vs mobile

Every known divergence between the two clients' view of the backend. Each entry is a
real inconsistency found in the code, not a wishlist. Close them or accept them
explicitly; do not let them drift unrecorded.

| # | Gap | Web | Mobile | Impact | Status |
|---|---|---|---|---|---|
| 0 | `is_mock`/`vibes`/`moods` in DDL | — | — | — | **closed 2026-10-25** — `is_mock` retired (no mock flag in DB); `vibes`/`moods` were legacy taxonomy, never in the schema |
| 1 | `is_mock` filter absent | — | — | — | **closed 2026-10-25** — no column and no `isMock` field remains in either client |
| 2 | `intensity` derivation | derived from `expression_score` when the column is absent | derived from `expressionScore` in Mappers.kt | consistent | **closed 2026-10-29** |
| 3 | `characterIds` normalisation | `[motifId]` fallback for single-motif | absent from `ProductDto` | mobile multi-character membership unsupported | open (forward-compat) — `character_ids` dropped by `20261024`; derived on web only |
| 4 | `artStyleSlug` | present on `Product` | absent from `ProductDto` | art-style facet unavailable on mobile | open |
| 5 | `editorialImages` | optional field on `Product` | absent | editorial rail cannot render on mobile | open |
| 6 | Price authority | server re-read via `place_order` | same RPC | consistent | closed |
| 7 | Trust/logistics (`cod_available`, `return_window_days`, `country_of_origin`, `style_code`, `manufacturer_*`) | mapped | mapped in `ProductDto`, `Product`, and `Mappers.kt` | mobile PDP now has access to COD / returns / origin / style / maker metadata (raw `attributes` jsonb remains web-only) | **closed 2026-10-29** |
| 8 | **Display pricing authority** — `quote_order` is never called | bag and `/checkout` price every number from `rpc/quote_order` (`web/src/lib/pricing.ts`) | `RootStore.submitOrder` records `bag.subtotalCents` as the order total; **zero** references to `quote_order` in `commonMain` | **Customer-visible money bug.** A ₹899 tee + ₹99 shipping = ₹998 on web, ₹899 on mobile. No COD fee, no coupons, no free-shipping threshold. `OrdersStore.recordOrder` persists the subtotal as `totalCents`, so mobile order history is wrong for every COD or coupon order. Gap #6 covered *charge* authority (both call `place_order`); it never covered *display*. | **open — 2026-10-31** |
| 9 | `identity_checked` / per-user coupon limits | shows limits as advisory; server enforces at `place_order` | n/a until #8 lands | `quote_order` passes `p_check_identity=false` for anonymous callers, so `per_user_limit` cannot be verified at quote time. Mobile must not promise "one per customer" in coupon copy. Enforcement is at `place_order` against the typed email. | open (by design — see CONTRACT §6) |

## How to close one

1. Decide which client is wrong, or that the column is genuinely optional.
2. Change `backend/CONTRACT.md` §3 first — the contract, then the client.
3. Change both adapters in the same change set: `web/src/lib/data.ts` and
   `mobile/.../data/SupabaseDtos.kt` + `Mappers.kt`.
4. Add a row here with `closed` and the date. Do not delete rows — the log is the value.
