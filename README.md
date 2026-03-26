# WarpTalk Infrastructure

DevOps, deployment configs, and operational tooling for the WarpTalk platform.

## Quick Start

```bash
# 1. Copy environment template
cp .env.example .env

# 2. Initialize database schemas & users
./scripts/init-db.sh

# 3. Start full stack (development)
docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build

# 4. Start full stack (production)
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
