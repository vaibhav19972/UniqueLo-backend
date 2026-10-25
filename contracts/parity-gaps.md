# Parity gaps — web vs mobile

Every known divergence between the two clients' view of the backend. Each entry is a
real inconsistency found in the code, not a wishlist. Close them or accept them
explicitly; do not let them drift unrecorded.

| # | Gap | Web | Mobile | Impact | Status |
|---|---|---|---|---|---|
| 0 | `is_mock`/`vibes`/`moods` in DDL | — | — | — | **closed 2026-10-25** — `is_mock` retired (no mock flag in DB); `vibes`/`moods` were legacy taxonomy, never in the schema |
| 1 | `is_mock` filter absent | — | — | — | **closed 2026-10-25** — no column and no `isMock` field remains in either client |
| 2 | `intensity` derivation | derived from `expression_score` when the column is absent | not derived at all | mobile cannot render the intensity facet; PDP accents differ | open — hosted lacks the column (`01_web` unapplied), so web runs its fallback |
| 3 | `characterIds` normalisation | `[motifId]` fallback for single-motif | absent from `ProductDto` | mobile multi-character membership unsupported | open (forward-compat) — `character_ids` dropped by `20261024`; derived on web only |
| 4 | `artStyleSlug` | present on `Product` | absent from `ProductDto` | art-style facet unavailable on mobile | open |
| 5 | `editorialImages` | optional field on `Product` | absent | editorial rail cannot render on mobile | open |
| 6 | Price authority | server re-read via `place_order` | same RPC | consistent | closed |
| 7 | Trust/logistics (`cod_available`, `return_window_days`, `country_of_origin`, `style_code`, `attributes`) | mapped | not mapped in `ProductDto` | mobile PDP cannot show COD / returns / origin | **open** — added by `20261024` |

## How to close one

1. Decide which client is wrong, or that the column is genuinely optional.
2. Change `backend/CONTRACT.md` §3 first — the contract, then the client.
3. Change both adapters in the same change set: `web/src/lib/data.ts` and
   `mobile/.../data/SupabaseDtos.kt` + `Mappers.kt`.
4. Add a row here with `closed` and the date. Do not delete rows — the log is the value.
