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
