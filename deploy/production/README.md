# WarpTalk production deployment

This directory is the provider-neutral deployment target for the agreed
Enterprise Cloud resource pool:

| VM | Capacity | Workload | Declared memory limits |
|---|---:|---|---:|
| App VM | 8 vCPU, 17 GB RAM, 60 GB NVMe | Caddy, frontend, gateway, .NET services, AI workers | 15.25 GB |
| Data VM | 4 vCPU, 13 GB RAM, 90 GB NVMe | PostgreSQL, PgBouncer, Redis, RabbitMQ, MinIO, Qdrant | 9.75 GB |

CPU limits are contention ceilings, not reservations, so their sum may exceed
the VM's physical CPU count. Memory limits deliberately leave capacity for the
host OS and Docker.

## Network contract

- Only the App VM receives the floating/public IP.
- Public inbound: TCP 80 and TCP/UDP 443 to the App VM.
- SSH is restricted to the operator's fixed IP or provider VPN.
- Data VM ports `5432`, `6432`, `6379`, `5672`, `15672`, `9000`, `9001`,
  `6333`, and `6334` bind only to `DATA_PRIVATE_IP`.
- The provider firewall must allow those Data VM ports only from
  `APP_PRIVATE_IP`. They must never be opened to `0.0.0.0/0`.

## Prepare a release

Bootstrap each clean Ubuntu host before copying release artifacts:

```sh
sudo ROLE=app \
  ADMIN_CIDR=203.0.113.10/32 \
  ./scripts/bootstrap-production-host.sh

sudo ROLE=data \
  ADMIN_CIDR=203.0.113.10/32 \
  APP_PRIVATE_IP=10.20.0.10 \
  ./scripts/bootstrap-production-host.sh
```

Use `DRY_RUN=true` first. The script rejects a world-open SSH CIDR, installs
Docker from its signed apt repository, enables security updates and fail2ban,
sets bounded daemon logging, and applies the role-specific UFW policy. Keep the
provider firewall in front of UFW with the same allow-list.

1. Build and push every image named in `app.compose.yml` with one immutable
   Git SHA tag.
2. Copy `.env.example` to `.env.production` on both VMs and replace all
   `CHANGE_ME` values.
3. Set file permissions:

   ```sh
   chmod 600 .env.production
   ```

4. Point the `APP_DOMAIN` and `API_DOMAIN` DNS records to the floating IP.
5. Validate the release artifacts from the infrastructure repository:

   ```sh
   ./scripts/check-production-deployment.sh
   ```

For a single-host demo deployment, set `APP_PRIVATE_IP` and `DATA_PRIVATE_IP`
to the same private interface and compose all three manifests:

```sh
docker compose \
  --env-file .env.production \
  -f data.compose.yml \
  -f app.compose.yml \
  -f single-host.compose.yml \
  config --quiet
```

The split-host deployment uses the same app/data manifests and only changes
the two inventory addresses. Templates are under `inventory/`.

## Deploy Data VM

From `deploy/production`:

```sh
sudo ALERT_WEBHOOK_URL="$ALERT_WEBHOOK_URL" \
  ALERTMANAGER_CONFIG_PATH=/etc/warptalk/alertmanager.yml \
  ../../scripts/render-alertmanager-config.sh

set -a
. ./.env.production
set +a
../../scripts/render-cost-observability.sh

docker compose \
  --env-file .env.production \
  -f data.compose.yml \
  pull

docker compose \
  --env-file .env.production \
  -f data.compose.yml \
  up -d
```

Confirm PostgreSQL, Redis, RabbitMQ and MinIO are healthy before deploying the
App VM. `minio-init` is a successful one-shot container and creates the private
workspace document bucket. Prometheus forwards SLO, queue, worker-heartbeat,
dead-letter, dependency and cost-budget alerts through the rendered
Alertmanager webhook. The dedicated `metrics-exporter` reads Redis Streams and
heartbeat keys directly; it is an immutable release image and remains private
on the Data network. Contract rates, metric definitions and monthly review
steps are documented in `observability/COST-GOVERNANCE.md`.

## Deploy App VM

Run the migration as a one-shot release gate before changing long-running
containers:

```sh
docker compose \
  --env-file .env.production \
  -f app.compose.yml \
  pull

docker compose \
  --env-file .env.production \
  -f app.compose.yml \
  run --rm migrator

docker compose \
  --env-file .env.production \
  -f app.compose.yml \
  up -d --no-deps \
  auth-service workspace-service translation-room-service \
  transcript-service notification-service meeting-service \
  assistant-service billing-service gateway frontend \
  stt-worker translation-worker tts-worker assistant-worker \
  embedding-worker billing-worker livekit-ingress-worker \
  security-worker caddy
```

The migration runner uses `ON_ERROR_STOP` and a PostgreSQL advisory lock, so a
failed migration stops the release and concurrent deploys cannot race.

## Backups and restore drills

Install `age`, PostgreSQL client tools, `curl`, `jq` and AWS CLI on the Data VM.
Copy `backup.env.example` to `/etc/warptalk/backup.env`, install the two units
from `systemd/`, then enable `warptalk-backup.timer`. Backups are encrypted
before offsite upload and the job refuses an offsite bucket without versioning.

Run a restore drill after setup and at least monthly:

```sh
BACKUP_SET=/var/backups/warptalk/daily/<timestamp> \
AGE_IDENTITY_FILE=/run/secrets/warptalk-backup.agekey \
./scripts/restore-drill.sh
```

The full incident procedure and recovery completion checklist are in
`DR-RUNBOOK.md`.

## Rollback

Images are immutable by `IMAGE_TAG`. To roll back application code, set
`IMAGE_TAG` to the previous known-good Git SHA and run the App VM `pull` and
`up -d` commands again. Database rollback is restore-forward: take a verified
backup before a destructive migration and apply a compensating migration or
restore that backup. Do not automatically run down migrations in production.
