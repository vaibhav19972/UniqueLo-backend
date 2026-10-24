# Parity gaps — web vs mobile

Every known divergence between the two clients' view of the backend. Each entry is a
real inconsistency found in the code, not a wishlist. Close them or accept them
explicitly; do not let them drift unrecorded.

| # | Gap | Web | Mobile | Impact | Status |
|---|---|---|---|---|---|
| 0 | `is_mock`/`vibes`/`moods` missing from `schema.sql` | reads `is_mock` from hosted | reads `is_mock` from hosted | **fresh build from seed.sql fails outright** | **blocker** — see `schema-drift.md` |
| 1 | `is_mock` filter absent | `getProducts()` returns all rows, hardcodes `isMock: false` | filters on real responses only | mock rows can leak to storefront | **open defect** |
| 2 | `intensity` derivation | derived from `expression_score` when column absent | not derived at all | mobile cannot render the intensity facet; PDP accents differ | open |
| 3 | `characterIds` normalisation | `[motifId]` fallback for single-motif | absent from `ProductDto` | mobile multi-character membership unsupported | open (forward-compat) |
| 4 | `artStyleSlug` | present on `Product` | absent from `ProductDto` | art-style facet unavailable on mobile | open |
| 5 | `editorialImages` | optional field on `Product` | absent | editorial rail cannot render on mobile | open |
| 6 | `is_mock` default | reads column | reads column | consistent | closed |
| 7 | Price authority | server re-read via `place_order` | same RPC | consistent | closed |

## How to close one

1. Decide which client is wrong, or that the column is genuinely optional.
2. Change `backend/CONTRACT.md` §3 first — the contract, then the client.
3. Change both adapters in the same change set: `web/src/lib/data.ts` and
   `mobile/.../data/SupabaseDtos.kt` + `Mappers.kt`.
4. Add a row here with `closed` and the date. Do not delete rows — the log is the value.
