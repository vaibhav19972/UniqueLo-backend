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