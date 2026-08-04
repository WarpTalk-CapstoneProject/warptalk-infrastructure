# Demo accounts for the meeting demo — production runbook

**Status: applied to production 2026-07-31 and verified end-to-end.** This file
documents what was run so it can be re-run, adapted, or rolled back.

5 accounts in one workspace, all able to host and join meetings together.
Password for all five: `Password123` (same as every other WarpTalk seed).

| Name | Email | Workspace role | Speak → Listen |
|---|---|---|---|
| Huỳnh Thái Tú (leader) | `thaitu.demo@warptalk.vn` | Owner | vi-VN → en-US |
| Trần Mạnh Tuấn | `manhtuan.demo@warptalk.vn` | Member | en-US → vi-VN |
| Huỳnh Ngọc Kỳ | `ngocky.demo@warptalk.vn` | Member | vi-VN → en-US |
| Ngô Xuân Hạnh Nhi | `hanhnhi.demo@warptalk.vn` | Member | en-US → vi-VN |
| Thân Thị Ngọc Vân (mentor) | `mentor.demo@warptalk.vn` | Admin | vi-VN → en-US |

Workspace: **WarpTalk Demo — SEP490** (`warptalk-demo-sep490`),
id `019f0d00-0de0-7000-9000-0000000000aa`.

The speak/listen split is deliberate — with everyone on the same language the
translation path in the demo has nothing to do.

## Why two scripts

Production has completed the logical-database cutover: `warptalk_auth`,
`warptalk_workspace`, `warptalk_translation_room`, … each own their schemas, and
the old shared `warptalk` database is empty. Cross-service FKs were dropped in
migrations 043/044. So `auth.*` and `workspace.*` cannot be written in one
transaction, and `scripts/seed-demo.sql` (which does exactly that) does **not**
work against prod.

## How it was run

Postgres lives on the Data host in `warptalk-postgres-1`, reachable only through
the App jump host. Superuser is `postgres`.

Dry run first — the scripts are wrapped in `BEGIN`/`COMMIT`, so rewriting the
commit to a rollback exercises the whole thing against the real schema without
writing:

```bash
sed 's/^COMMIT;$/ROLLBACK;/' scripts/seed-prod-demo-accounts-auth.sql | ssh warptalk-data 'docker exec -i -e PGCLIENTENCODING=UTF8 warptalk-postgres-1 psql -U postgres -d warptalk_auth -v ON_ERROR_STOP=1'
```

Then for real:

```bash
ssh warptalk-data 'docker exec -i -e PGCLIENTENCODING=UTF8 warptalk-postgres-1 psql -U postgres -d warptalk_auth -v ON_ERROR_STOP=1' < scripts/seed-prod-demo-accounts-auth.sql
```

```bash
ssh warptalk-data 'docker exec -i -e PGCLIENTENCODING=UTF8 warptalk-postgres-1 psql -U postgres -d warptalk_workspace -v ON_ERROR_STOP=1' < scripts/seed-prod-demo-accounts-workspace.sql
```

`PGCLIENTENCODING=UTF8` matters — the names carry Vietnamese diacritics.

Part 2 defaults to the live prod role ids and needs no arguments. To point it at
another environment, read the ids from that environment's `auth.roles` and pass
`-v owner_role_id=… -v admin_role_id=… -v member_role_id=…`.

To use a password other than `Password123`, generate a hash with
`python3 scripts/hash-demo-password.py` and pass `-v pw_hash='v2$SHA512$…'`.

## Environment facts these scripts depend on

Verified against prod on 2026-07-31. Re-check before running elsewhere:

- **Language codes are full locales** — `translation_room.supported_languages`
  holds `vi-VN, en-US, ja-JP, ko-KR, zh-CN, fr-FR, es-ES`, not bare `vi`/`en`.
  The local `seed-data.sh` seeds bare codes; do not copy those.
- **`workspace_members.status` is `'Active'`, capitalised**, matching
  `WorkspaceMemberStatus.Active.ToString()` and the existing prod rows — the
  local `seed-demo.sql` writes lowercase `'active'`.
- **`membership_type` is `'Internal'`**, likewise capitalised.
- `require_verified_domain_for_internal = false` on the demo workspace makes all
  five Internal without standing up DNS verification.

## Verification performed

Through the public API, not just the database:

1. All five accounts log in — `POST /api/v1/auth/login` → 200.
2. `GET /api/v1/workspaces` as Thái Tú returns the demo workspace with
   `"role": "Owner"`, `"membershipType": "Internal"` — proves the cross-database
   role lookup (workspace DB → auth DB over gRPC) resolves.
3. Created a room, joined it from a second account by code, host admitted, and
   the participant received a LiveKit token
   (`isWaitingRoom: false`, token issued).
4. Smoke-test room was ended afterwards; no demo rooms left behind.

## Known behaviour to expect during the demo

A newly created room is persisted with `requires_approval: true` regardless of
what the create request asks for, so **every joiner lands in the waiting room and
the host must admit them** (`PUT /api/v1/translation-rooms/{id}/participants/{participantId}/admit`
— note `PUT`, a `POST` returns 405). Plan for it, or change the room setting
before the demo. `GET /translation-rooms/{id}` reports
`"requiresApproval": false` for the same room, which contradicts the stored
value — worth a separate look, it is a read-path mapping bug, not a config
problem with these accounts.

## What is deliberately not seeded

- **No `admin` platform role.** These are meeting-demo logins; they should not
  reach `/api/v1/admin/*`.
- **No subscription or credit rows.** Room creation and joining have no billing
  gate — `CreateTranslationRoomAsync` validates languages only. If the demo also
  covers usage metering or the billing screens, that is a separate seed.
- **No verified domains.** See the policy flag above.
- **No rooms or meetings.** Create those live in the UI.

## Rollback

Both scripts only touch rows whose ids start with `019f0d00-0de0-7000-9000-`,
so cleanup is bounded. Run the workspace deletes first.

```sql
-- warptalk_workspace
DELETE FROM workspace.workspace_members WHERE workspace_id = '019f0d00-0de0-7000-9000-0000000000aa';
DELETE FROM workspace.workspaces        WHERE id           = '019f0d00-0de0-7000-9000-0000000000aa';
```

```sql
-- warptalk_auth
DELETE FROM auth.user_roles    WHERE user_id::text LIKE '019f0d00-0de0-7000-9000-%';
DELETE FROM auth.user_settings WHERE user_id::text LIKE '019f0d00-0de0-7000-9000-%';
DELETE FROM auth.users         WHERE id::text      LIKE '019f0d00-0de0-7000-9000-%';
```
