# WarpTalk production deployment

The Vietnix resource pool is deployed as three independently managed VMs:

| VM | Capacity | Storage | Workload |
|---|---:|---:|---|
| App | 8 vCPU / 16 GiB | 60 GiB root | Caddy, web, gateway, .NET services, AI workers, Gotenberg |
| Data | 2 vCPU / 8 GiB | 20 GiB root + 35 GiB durable | PostgreSQL, PgBouncer, MinIO, Qdrant |
| Infra | 2 vCPU / 4 GiB | 20 GiB root + 15 GiB durable | Redis, RabbitMQ, telemetry and dashboards |

Only App has the Floating IP. Data and Infra are reached through App as the
SSH jump host. Docker state on Data and Infra lives under
`/srv/warptalk/docker` on their durable volumes.

## Network contract

- Public inbound to App: TCP 80, TCP/UDP 443.
- SSH to App: any tailnet peer on `tailscale0`, plus the break-glass operator
  `/32`s listed in `ADMIN_CIDR` / `admin_cidrs`.
- Data ingress from App: TCP 22, 5432, 6432, 9000, 9001, 6333 and 6334.
- Data ingress from Infra: TCP 5432, 9000, 6333 and 6334.
- Infra ingress from App: TCP 22, 6379, 5672, 15672, 15692, 4317, 4318,
  5341, 9090, 9093 and 3001.
- No Data or Infra port is public.

Provider security groups and UFW enforce the same boundary.

## Host preparation

Bootstrap a clean Ubuntu 24.04 host before deploying containers.

`ADMIN_CIDR` accepts several CIDRs separated by spaces or commas, so each
operator gets an individual rule instead of the team sharing one `/32`. It is
the break-glass path: normal team and workflow access arrives over the tailnet.
`TAILSCALE_SSH` defaults to `true` and rebuilds the `tailscale0` SSH rule — set
it to `false` only on a host with no tailnet membership, because `ufw --force
reset` at the top of the firewall section would otherwise drop tailnet SSH and
break the release workflow's production job.

Each role must also be told **its own** private IP. The containers publish onto that exact
address, and the bootstrap installs a `docker.service` drop-in that blocks startup until the
address is actually assigned — see "Private addresses must be static" below.

```sh
sudo ROLE=app \
  ADMIN_CIDR="203.0.113.10/32 203.0.113.11/32" \
  APP_PRIVATE_IP=10.20.0.200 \
  DEPLOY_USER=cloud-user \
  ./scripts/bootstrap-production-host.sh

sudo ROLE=data \
  ADMIN_CIDR="203.0.113.10/32 203.0.113.11/32" \
  APP_PRIVATE_IP=10.20.0.200 \
  DATA_PRIVATE_IP=10.20.0.20 \
  INFRA_PRIVATE_IP=10.20.0.30 \
  DEPLOY_USER=cloud-user \
  ./scripts/bootstrap-production-host.sh

sudo ROLE=infra \
  ADMIN_CIDR="203.0.113.10/32 203.0.113.11/32" \
  APP_PRIVATE_IP=10.20.0.200 \
  DATA_PRIVATE_IP=10.20.0.20 \
  INFRA_PRIVATE_IP=10.20.0.30 \
  DEPLOY_USER=cloud-user \
  ./scripts/bootstrap-production-host.sh
```

### Private addresses must be static (WT-595)

Every Data and Infra container publishes onto an absolute private IP
(`10.20.0.20:5432`, `10.20.0.30:6379`, …) rather than `0.0.0.0`. That is deliberate and must
stay: Docker writes its own iptables rules ahead of UFW's chains, so publishing onto `0.0.0.0`
and relying on the UFW source rules would put Postgres and Redis on the public interface with
the firewall bypassed.

The consequence is that the address has to exist *before* Docker starts a container, because
publishing a port is a create-time operation. It is not retried: `restart: unless-stopped` covers
crashes, and a container that never came up did not crash. On 30/08/2026 all three VMs rebooted,
`eth0` was still waiting on its DHCP lease when `docker.service` came up, and eleven containers
went to `Exited (255)` and stayed there. Production was down 27 hours. Only the exporters
survived — they bind no private address — so every dashboard looked healthy.

Two things follow, and both are needed:

1. **Give each VM a static private address.** A lease is a promise about a moment, and every
   reboot re-opens the race. Pin `10.20.0.200` / `10.20.0.20` / `10.20.0.30` in netplan on the
   respective hosts rather than accepting them from DHCP.
2. **Keep the docker drop-in.** `bootstrap-production-host.sh` installs
   `/usr/local/sbin/warptalk-wait-for-bind-address` and an `ExecStartPre` that blocks docker until
   the address is assigned (bounded to 120s, then it proceeds and says so in the journal).
   `After=network-online.target` was already present and lost this race anyway — "the network is
   up" is not "this interface holds this address". Keep the drop-in after the addresses are
   static: it costs nothing when the address is already there.

**Recovering a host that booted without its address.** `docker start` on those containers
*succeeds* and reports healthy — the healthcheck runs inside the container over loopback — while
`Ports` and `Networks` come back empty and the host has no listener at all. The endpoint config is
gone from the container's state, and `docker stop && docker start` does not restore it. Only
`docker compose up -d` recreates it. Do that with the digest-pinned override regenerated (see
`scripts/deploy-release.sh`), from **each host's own release directory** — the roles can sit on
different release versions, and reaching for the newest one turns a recovery into an unplanned
deploy.

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

### WT-603: the meeting migration is not backward compatible

`scripts/service-migrations/meeting/20260903120000_remove_retired_collaboration_features.sql`
drops the retired Polls/Q&A/Breakouts tables **and renames**
`meeting.meeting_tracks.meeting_participant_id` to `rtc_stream_participant_id`,
with the matching index and foreign-key constraint renames.

There is no expand phase. The old and the new column name never coexist, so:

- the **previous** `meeting-service` image fails every write to `meeting_tracks`
  once the migration has been applied, and
- the **new** image fails every such write until it has.

That window is not idle. `MeetingWebhookService.HandleTrackPublished` inserts a
`meeting_tracks` row on every LiveKit `track_published` webhook, i.e. every time
anyone turns on a camera or a microphone in a live room. The default order in
`scripts/deploy-release.sh` runs `compose run --rm migrator` (line 214) *before*
`compose up -d` (lines 217-221), so between those two steps the old
`meeting-service` is still serving traffic against the renamed schema.

**Preflight, before migrating.** Run the row-count query from the migration
header through the approved database diagnostic path and export anything that
must be retained:

```sql
  SELECT 'poll_votes', count(*) FROM meeting.poll_votes
  UNION ALL SELECT 'poll_options', count(*) FROM meeting.poll_options
  UNION ALL SELECT 'polls', count(*) FROM meeting.polls
  UNION ALL SELECT 'question_votes', count(*) FROM meeting.question_votes
  UNION ALL SELECT 'questions', count(*) FROM meeting.questions
  UNION ALL SELECT 'breakout_assignments', count(*) FROM meeting.breakout_assignments
  UNION ALL SELECT 'breakout_sessions', count(*) FROM meeting.breakout_sessions;
```

The DROPs are irreversible. Also take the verified backup that the rollback
section below requires before any destructive migration.

**Mitigation.** Deploy in an off-peak window with no live meetings, and stop
`meeting-service` before the migrator so that no old build can write the renamed
schema. From `deploy/production` on App:

```sh
docker compose --env-file .env.production -f app.compose.yml pull
docker compose --env-file .env.production -f app.compose.yml stop meeting-service
docker compose --env-file .env.production -f app.compose.yml run --rm migrator
docker compose --env-file .env.production -f app.compose.yml up -d
```

The final `up -d` recreates `meeting-service` from the new image, so no explicit
`start` is needed.

With the guarded release script, stop the service first and then let the script
run its own migration gate:

```sh
docker compose --env-file /etc/warptalk/.env.production \
  -f /opt/warptalk/current/deploy/production/app.compose.yml \
  stop meeting-service

DEPLOY_ROLE=app \
RELEASE_MANIFEST=/etc/warptalk/release-manifest.json \
PRODUCTION_ENV_FILE=/etc/warptalk/.env.production \
  /opt/warptalk/current/scripts/deploy-release.sh
```

`stop` targets the running container, so it does not need the immutable image
override that `deploy-release.sh` generates internally (`$override`, a `mktemp`
file built from `RELEASE_MANIFEST`); the base compose file is enough. The script
then runs `migrator` while `meeting-service` is down and brings it back up on
the new image in the same run.

Meetings that are live when `meeting-service` stops lose their track bookkeeping
either way. Stopping it first only converts silent write failures into a short,
visible outage of one service, which is why the off-peak window matters more than
the command order.

Rollback is restore-forward. `ALTER TABLE ... RENAME COLUMN` can be reversed by
a compensating migration, but the seven `DROP TABLE` statements cannot; recover
those from the pre-migration backup.

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
