# WarpTalk production deployment

The Vietnix resource pool is deployed as three independently managed VMs:

| VM | Capacity | Storage | Workload |
|---|---:|---:|---|
| App | 8 vCPU / 16 GiB | 60 GiB root | Caddy, web, gateway, .NET services, AI workers |
| Data | 2 vCPU / 8 GiB | 20 GiB root + 35 GiB durable | PostgreSQL, PgBouncer, MinIO, Qdrant |
| Infra | 2 vCPU / 4 GiB | 20 GiB root + 15 GiB durable | Redis, RabbitMQ, telemetry and dashboards |

Only App has the Floating IP. Data and Infra are reached through App as the
SSH jump host. Docker state on Data and Infra lives under
`/srv/warptalk/docker` on their durable volumes.

## Network contract

- Public inbound to App: TCP 80, TCP/UDP 443.
- SSH to App: the current operator `/32` only.
- Data ingress from App: TCP 22, 5432, 6432, 9000, 9001, 6333 and 6334.
- Data ingress from Infra: TCP 5432, 9000, 6333 and 6334.
- Infra ingress from App: TCP 22, 6379, 5672, 15672, 15692, 4317, 4318,
  5341, 9090, 9093 and 3001.
- No Data or Infra port is public.

Provider security groups and UFW enforce the same boundary.

## Host preparation

Bootstrap a clean Ubuntu 24.04 host before deploying containers:

```sh
sudo ROLE=app \
  ADMIN_CIDR=203.0.113.10/32 \
  DEPLOY_USER=cloud-user \
  ./scripts/bootstrap-production-host.sh

sudo ROLE=data \
  ADMIN_CIDR=203.0.113.10/32 \
  APP_PRIVATE_IP=10.20.0.200 \
  INFRA_PRIVATE_IP=10.20.0.30 \
  DEPLOY_USER=cloud-user \
  ./scripts/bootstrap-production-host.sh

sudo ROLE=infra \
  ADMIN_CIDR=203.0.113.10/32 \
  APP_PRIVATE_IP=10.20.0.200 \
  DATA_PRIVATE_IP=10.20.0.20 \
  DEPLOY_USER=cloud-user \
  ./scripts/bootstrap-production-host.sh
```

On Data and Infra, format a newly attached empty durable disk only after
confirming its size and device mapping:

```sh
sudo ROLE=data DEVICE=/dev/vdb ./scripts/mount-production-data-volume.sh
sudo ROLE=infra DEVICE=/dev/vdb ./scripts/mount-production-data-volume.sh

sudo ROLE=data ./scripts/configure-production-docker-root.sh
sudo ROLE=infra ./scripts/configure-production-docker-root.sh
```

Both scripts are fail-closed and idempotent. The mount script rejects an
unexpected device size, partition table, filesystem, label or conflicting
`fstab` entry.

## Prepare a release

1. Build and push every image in `image-matrix.json` with one immutable Git SHA
   tag.
2. Copy `.env.example` to `.env.production` on all three VMs.
3. Replace every `CHANGE_ME` value and set mode `0600`.
4. Keep `APP_PRIVATE_IP`, `DATA_PRIVATE_IP` and `INFRA_PRIVATE_IP` identical on
   all hosts.
5. Validate locally:

   ```sh
   ./scripts/test-three-host-compose-contract.sh
   ./scripts/check-production-deployment.sh
   ```

6. Package the non-secret deployment tree and verify its checksum before
   extracting it under `/opt/warptalk/releases/<release-id>`:

   ```sh
   OUTPUT=/absolute/path/warptalk-deployment.tar.gz \
     ./scripts/package-production-deployment.sh
   ```

`NEXT_PUBLIC_*` frontend values must be present during image build; changing
them only in `.env.production` does not alter an already-built Next.js bundle.

## Deploy Data

From `deploy/production` on Data:

```sh
docker compose --env-file .env.production -f data.compose.yml pull
docker compose --env-file .env.production -f data.compose.yml up -d
```

For an immutable image manifest, the equivalent guarded command is:

```sh
DEPLOY_ROLE=data \
RELEASE_MANIFEST=/etc/warptalk/release-manifest.json \
PRODUCTION_ENV_FILE=/etc/warptalk/.env.production \
  /opt/warptalk/current/scripts/deploy-release.sh
```

Wait for PostgreSQL, PgBouncer and MinIO health. `minio-init` is a successful
one-shot container that creates the private buckets.

## Deploy Infra

Render the alert and cost files first:

```sh
set -a
. ./.env.production
set +a

sudo ALERT_EMAIL_TO="$ALERT_EMAIL_TO" \
  RESEND_API_KEY="$RESEND_API_KEY" \
  RESEND_FROM_EMAIL="$RESEND_FROM_EMAIL" \
  ALERTMANAGER_CONFIG_PATH=/etc/warptalk/alertmanager.yml \
  ../../scripts/render-alertmanager-config.sh

../../scripts/render-cost-observability.sh

docker compose --env-file .env.production -f infra.compose.yml pull
docker compose --env-file .env.production -f infra.compose.yml up -d
```

Use `DEPLOY_ROLE=infra` with `deploy-release.sh` for the immutable release.

Prometheus reaches MinIO and Qdrant through the private `data-host` mapping and
reaches PostgreSQL through the least-privilege monitor account.

## Deploy App

The migration is a blocking release gate:

```sh
docker compose --env-file .env.production -f app.compose.yml pull
docker compose --env-file .env.production -f app.compose.yml run --rm migrator
docker compose --env-file .env.production -f app.compose.yml up -d
```

Use `DEPLOY_ROLE=app` with `deploy-release.sh`; only the App role executes the
migration gate. Release overrides are filtered to services that exist on the
selected host, so the Infra metrics image cannot be accidentally started on
App.

The migration runner uses `ON_ERROR_STOP` and a PostgreSQL advisory lock.
Application services use Data for PostgreSQL/MinIO/Qdrant and Infra for
Redis/RabbitMQ/OTLP.

## DNS, acceptance and rollback

Point `APP_DOMAIN` and `API_DOMAIN` to `45.115.16.201`, then verify DNS and
public TLS before executing functional, billing, media and load acceptance.
A healthy container or HTTP health endpoint alone is not production
acceptance.

Rollback application code by setting `IMAGE_TAG` to the previous immutable
release and re-running `pull` plus `up -d`. Database rollback is
restore-forward: take a verified backup before destructive migrations, then
use a compensating migration or restore. Never automate down migrations.

Provider backup storage is not purchased. Before production data is accepted,
install verified AWS CLI v2 tooling and enable the encrypted offsite backup
timer from `systemd/`; otherwise the deployment has no acceptable database
recovery path.
