-- RETIRED 2026-10-31 — kept for history, DO NOT APPLY.
--
-- This was authored for the web client on 2026-10-13 and never applied to the
-- hosted project. By 2026-10-31 it was obsolete in every respect:
--   * `intensity` is NOT in contracts/live-columns.txt (44 columns) and neither
--     client reads it as a column — both DERIVE it from expression_score
--     (backend/contracts/parity-gaps.md #2, closed 2026-10-29).
--     Applying it would flip check-schema-parity.mjs red.
--   * `craft_techniques` and `edits` already exist in schema.sql.
--   * The `moods` column mentioned below was never created by any DDL.
--
-- Moved to _archive/ so both gates ignore it (they scan migrations/*.sql
-- non-recursively). Resurrecting it requires a CONTRACT.md change first.
-- ---------------------------------------------------------------------------
-- 20261013_taxonomy_columns.sql
-- Taxonomy re-architecture: intensity axis + craft techniques + edits.
--
-- The adapter (src/lib/data.ts) feature-detects: rows written before this
-- migration simply lack the columns — the mapper defaults intensity to
-- 'balanced' and craft_techniques/edits to empty arrays, so applying this
-- is safe on a live catalog. seed.sql parity is a follow-up (tracked in
-- audit.md, 2026-10-13 entry).
--
-- Note: buyer-intent edits are stored in the existing `moods text[]` column
-- for now (same slug strings, presentation-only rename) — the Admin SQL
-- generator writes them there. A later migration may rename that column.

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS intensity text NOT NULL DEFAULT 'balanced',
  ADD COLUMN IF NOT EXISTS craft_techniques text[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS edits text[] DEFAULT '{}';