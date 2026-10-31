# migrations/_archive — NOT part of the chain

Files here are **retired**. Do not apply them to any database. They are kept
only as the record of what was written and why it was abandoned.

Two consequences of them moving here:

1. **Both gates ignore this directory.** `check-contract.mjs` and
   `check-schema-completeness.mjs` read `migrations/*.sql` non-recursively on
   purpose, so an archived file cannot influence a drift check.
2. **`psql -f migrations/*.sql` still works**, because a shell glob only expands
   the top level and this directory is not matched. Do not "tidy" this folder
   into a flat `migrations/` listing — a human following the load order would
   start applying retired DDL.

## Contents

| File | Retired | Why |
|---|---|---|
| `01_web_20261013_taxonomy_columns.sql` | 2026-10-31 | Adds `products.intensity`, which is not in the live 44-column shape and which neither client reads as a column — both derive `intensity` from `expression_score` (`contracts/parity-gaps.md` #2). `craft_techniques` and `edits` already exist in `schema.sql`. Applying it would flip `check-schema-parity.mjs` red. |

Reviving anything from this folder requires a `CONTRACT.md` change first, then a
new dated migration — never a move back into `migrations/`.
