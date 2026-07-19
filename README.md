# WarpTalk Infrastructure

DevOps, deployment configs, and operational tooling for the WarpTalk platform.

## Quick Start

```bash
# 1. Copy environment template
cp .env.example .env

# 2. Initialize database schemas & users
./scripts/init-db.sh

# 3. Apply migrations. init-db.sql is a historical snapshot — it does NOT
#    include fixes/changes added by scripts/migrations/*.sql since then
#    (e.g. it still has the pre-018 backwards users/user_settings FK).
#    Apply every file below IN THIS EXACT ORDER — do not `for f in
#    scripts/migrations/*.sql` or `ls | sort`: several files share the
#    same leading number, and plain alphabetical sort gets 007/008 backwards
#    (007-03-06-2026-*.sql would sort before 007-16-05-2026-*.sql even
#    though it was written three weeks later). Order below is verified
#    against each file's own header date; note 010-*-add-chat-mentions.sql
#    and 010-*-add-can-create-meetings-*.sql share the same filename date
#    (2026-06-12) with no other ordering signal — verify against git log
#    if that pair's relative order ever matters for your change.
MIGRATIONS_DIR="scripts/migrations"
for f in \
  000-init-migrations.sql \
  001-14-04-2026-rename-meeting.sql \
  002-16-04-2026-rename-meeting-columns.sql \
  003-17-04-2026-uppercase-type.sql \
  004-01-05-2026-add-notification-message-table.sql \
  005-09-05-2026-add-admin-notifications-table.sql \
  006-14-05-2026-convert-transcript-status-to-enum.sql \
  006-15-05-2026-rename-participant-is-translation-audio-enabled.sql \
  007-16-05-2026-add-meeting-schema.sql \
  008-20-05-2026-add-translation-room-views.sql \
  007-03-06-2026-separate-workspace-schema-from-auth.sql \
  008-03-06-2026-add-workspace-documents-and-glossary.sql \
  009-04-06-2026-add-meeting-chat.sql \
  009-05-06-2026-rename-role-key-to-subject-key.sql \
  010-12-06-2026-add-chat-mentions.sql \
  010-12-06-2026-add-can-create-meetings-to-workspace-members.sql \
  011-12-06-2026-convert-enums-to-varchar.sql \
  012-14-06-2026-add-meeting-invitation.sql \
  013-14-06-2026-add-meeting-active-host.sql \
  014-15-06-2026-convert-translation-and-transcript-enums-to-varchar.sql \
  015-16-06-2026-add-translation-room-invitations.sql \
  016-03-07-2026-enforce-single-active-subscription.sql \
  017-15-07-2026-translation-cluster-finalize.sql \
  018-16-07-2026-fix-users-user-settings-fk-direction.sql \
  019-16-07-2026-billing-schema-mismatch-and-idempotency.sql \
  020-17-07-2026-refresh-token-family-reuse-detection.sql \
; do
  psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -f "$MIGRATIONS_DIR/$f"
done

# 4. Start full stack (development)
docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build

# 5. Start full stack (production)
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

## Structure

```
├── docker-compose.yml          # Base: all services
├── docker-compose.dev.yml      # Dev overrides (ports, debug)
├── docker-compose.prod.yml     # Production (replicas, resource limits)
├── pgbouncer/
│   └── pgbouncer.ini           # Connection pooling config
├── coturn/
│   └── turnserver.conf         # TURN/STUN for WebRTC audio
├── observability/
│   ├── otel-collector.yml      # OpenTelemetry pipeline
│   ├── prometheus.yml          # Metrics scraping
│   └── dashboards/             # Grafana dashboard JSON
├── backup/
│   ├── pg-backup.sh            # Daily PostgreSQL → S3/MinIO
│   └── qdrant-backup.sh        # Vector DB snapshot
└── scripts/
    ├── init-db.sh              # Create schemas & DB users
    ├── seed-data.sh            # Insert sample/test data
    ├── start-all.sh            # Full stack startup
    └── stop-all.sh             # Graceful shutdown
```

## Services

| Service | Dev Port | Description |
|---------|----------|-------------|
| PostgreSQL | 5432 | Primary database |
| PgBouncer | 6432 | Connection pooling |
| Redis | 6379 | Cache + Streams |
| Auth Service | 5101 | Authentication & users |
| Meeting Service | 5102 | Meeting management |
| Transcript Service | 5103 | Transcription |
| Notification Service | 5104 | Push/email notifications |
| API Gateway | 5200 | YARP + SignalR hubs |
| COTURN Primary | 3478 | TURN/STUN server |
| COTURN Backup | 3479 | TURN/STUN failover |
| Prometheus | 9090 | Metrics |
| Grafana | 3000 | Dashboards |
| Seq | 5341 | Centralized logging |
