-- Migration: 052-06-08-2026-drop-translation-contents-confidence
-- Ticket: WT-278
-- Created At: 2026-08-06
-- Description:
--   CONTRACT HALF of the pair opened by 051-06-08-2026-quarantine-translation-stt-confidence.sql.
--   Drops transcript.translation_contents.confidence, which 051 kept alive so the expand phase
--   could be applied against a backend that still read the old name.
--
--   ── THIS FILE IS NOT RUNNABLE YET. IT IS NOT IN THE MIGRATION PATH. ───────────────────────────
--   It lives in scripts/migrations/pending/, not scripts/migrations/. scripts/run-migrations.sh
--   iterates `for path in "$MIGRATIONS_DIR"/*.sql` — a plain, non-recursive glob — so nothing in
--   this subdirectory is ever collected, ordered or recorded in public.schema_migrations. Both
--   production paths funnel through that same script (deploy/production/app.compose.yml mounts
--   ../../scripts:/scripts and runs it; deploy/k3s/migrator.Dockerfile does `COPY scripts /scripts`
--   with scripts/run-k3s-migrations.sh as the entrypoint, which calls it), so the file ships with
--   every release image and still cannot fire on its own.
--   This repo has no per-migration gate, skip flag or manifest to express "not yet" — the ordering
--   is derived from the filename and applicability is all-or-nothing. Not descending into a
--   subdirectory is therefore the only mechanism the runner actually offers.
--
--   ── PRECONDITION FOR PROMOTING IT ─────────────────────────────────────────────────────────────
--   Move this file up into scripts/migrations/ ONLY in a release whose backend ref already contains
--   WT-277/WT-278 (warptalk-backend PR #106, merged to development on 2026-08-05; the production
--   backend as of 2026-08-06 is 36224d3671f594e07de6cf145e8e7b817bb4ea47, which does NOT contain
--   it), AND only once that backend is the version actually RUNNING in production.
--   The ordering matters twice over, because deploy-release.sh runs the migrator before
--   `compose up -d`:
--     * promote too early -> the migrator drops `confidence` while the old TranscriptService is
--       still serving; every transcript translation read becomes a 42703 undefined_column.
--     * promote in the same release that first deploys the new backend -> also fine, because the
--       new build never touches `confidence`. The unsafe case is only "old backend still up".
--   Renumber to the next free NNN if migrations have been added in the meantime; the date in the
--   filename is what run-migrations.sh sorts on, so refresh it to the promotion date.
--
--   Nothing reads this column. Verified at the time of writing: TranscriptQueryService and
--   TranscriptGrpcService both move to source_stt_confidence in backend PR #106; warptalk-web binds
--   no translation confidence; and warptalk-infrastructure contains no observability query,
--   rendered config or script that references transcript.translation_contents at all. 051 already
--   copied every non-NULL value across, so this drop loses nothing that source_stt_confidence does
--   not already hold.
--
--   IRREVERSIBLE. There is no down migration. Take the normal pre-release logical backup
--   (scripts/backup-production.sh) before promoting.

BEGIN;

ALTER TABLE transcript.translation_contents
    DROP COLUMN IF EXISTS confidence;

COMMIT;
