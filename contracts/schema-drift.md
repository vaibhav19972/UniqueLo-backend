# Schema drift — `schema.sql` vs `seed.sql`

Found 2026-10-24 during the restructure, by parsing both files and diffing column lists.
Not reported anywhere else in the repo. Verify with the command at the bottom before
acting on it.

## The defect

`seed.sql` inserts three columns on `public.products` that `schema.sql` never creates:

| Column | Used by | Defined in schema.sql? |
|---|---|---|
| `is_mock` | all 13 seed product rows | **no** |
| `vibes` | all 13 seed product rows | **no** |
| `moods` | all 13 seed product rows | **no** |

Result: a database built by running `schema.sql` then `seed.sql` fails on the first
product insert with `column "is_mock" of relation "products" does not exist`.
`production-seed.sql` is clean — its 2 inserts use only defined columns.

## Why it went unnoticed

The hosted Supabase project already had the columns (added out-of-band, likely by hand
in the SQL editor). Every client reads the hosted DB, so nothing ever exercised the
fresh-build path. `production-seed.sql` is also clean, so the production bootstrap would
have appeared to work — the failure only hits local/staging rebuilds from `seed.sql`.

## Consequence for the rest of the workspace

`CONTRACT.md` §5 (the mock/real catalogue boundary) is written against `is_mock`. That
section is currently aspirational — the column it depends on isn't in the DDL. Same for
the T1.4 test fix in `web/docs/10-testing`.

`vibes` and `moods` are **legacy** taxonomy: they were superseded by
`craft_techniques text[]` and `edits text[]` (migration `01_web_20261013`). A migration
that adds `vibes`/`moods` back to make the seed pass would re-import dead concepts.
Preferred fix is to strip them from `seed.sql` and add only `is_mock`.

## Recommended fix — in this order

1. **Add the column that's actually needed** (`backend/migrations/`, next in chain):

   ```sql
   alter table public.products
     add column if not exists is_mock boolean not null default false;
   ```

2. **Strip the dead columns from `seed.sql`** — remove `is_mock`, `vibes`, `moods` from
   the column list and the matching values from all 13 rows, then re-add `is_mock`
   only. Keep the `is_mock = EXCLUDED.is_mock` clauses in the upsert — those are
   correct.
   Note the seed currently labels its rows `is_mock = false` while the comment calls
   them "handcrafted products"; decide which they are before rewriting.
3. **Add `is_mock` to `schema.sql`** so a fresh build matches. `schema.sql` is the
   bootstrap DDL, so it must carry everything the migrations produce.
4. **Add a build check** — `scripts/verify-schema-parity.sh` should run
   `schema.sql` + `seed.sql` against a throwaway Postgres and fail on error. That is
   the only thing that stops this recurring.

## Verify it yourself

```bash
cd backend
python3 - <<'PY'
import re
schema = open('schema.sql').read()
cols = {l.strip().split()[0] for l in
        re.search(r'public\.products \((.*?)\n\);', schema, re.S).group(1).split('\n')
        if l.strip() and not l.strip().startswith(('--','constraint','primary'))}
seed = open('seed.sql').read()
used = set()
for ins in re.findall(r'INSERT INTO public\.products \((.*?)\) VALUES', seed, re.S):
    used |= {c.strip() for c in ins.replace('\n',' ').split(',') if c.strip()}
print('seed uses, schema lacks:', sorted(used - cols))
PY
```

Expected output right now: `['is_mock', 'moods', 'vibes']`. After the fix: `[]`.
