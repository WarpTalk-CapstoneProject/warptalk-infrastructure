# Service-owned logical database migrations

This directory is the release-artifact staging area. Source migrations live
under `<service>/database/migrations` in `warptalk-backend`; CI copies their
`.sql` files here before producing a deployment bundle.

| Directory | Database | Schema |
|---|---|---|
| `auth/` | `warptalk_auth` | `auth`, `voice` |
| `workspace/` | `warptalk_workspace` | `workspace` |
| `translation-room/` | `warptalk_translation_room` | `translation_room` |
| `transcript/` | `warptalk_transcript` | `transcript` |
| `notification/` | `warptalk_notification` | `notification` |
| `meeting/` | `warptalk_meeting` | `meeting` |
| `assistant/` | `warptalk_assistant` | `assistant` |
| `billing/` | `warptalk_billing` | `subscription` |

The migrator applies each file in a transaction under a per-service PostgreSQL
advisory lock. It records the SHA-256 checksum, execution time, release,
applied-by identity and timestamp in `public.service_schema_migrations`.
Changing an already-applied file is a hard deployment failure.

## These directories are the deployment artifact, not a convenience copy

`deploy/production/app.compose.yml` mounts `../../scripts` as `/scripts` and
`run-logical-database-migrations.sh` reads `/scripts/service-migrations`. What is
committed here is therefore *exactly* what production applies. A migration that
exists in `warptalk-backend` but was never staged here never runs anywhere. Three
of them had drifted that way before WT-294.

A service with no migrations yet still gets a directory containing a `.gitkeep`.
Git cannot track an empty directory, and without the marker the path is absent
from the release bundle, so the migrator's `[ -d "$dir" ]` guard skips the service
in silence — which is how `warptalk_transcript` reached 2026-08 having received
nothing at all since extraction.

## The rule WT-294 exists to enforce

`scripts/migrations/` is applied to the **legacy monolith database `warptalk`**,
which no service has connected to since the extraction. Any schema change a
running service needs must be a file in
`warptalk-backend/<service>/database/migrations/`, staged here by
`collect-service-migrations.sh`. `scripts/check-service-migration-coverage.sh`
fails CI when that is not true.
