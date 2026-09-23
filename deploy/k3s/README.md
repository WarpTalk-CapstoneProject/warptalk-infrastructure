# WarpTalk multi-node K3s deployment

This directory is the provider-neutral, multi-node HA target. Application
images, add-ons and data images are immutable and digest-pinned. Provider
credentials never belong in Git.

## Production on the three Vietnix VMs

Everything in this section is what `deploy_target=k8s` in
`.github/workflows/release.yml` does. The generic HA target described further down is
still valid for a larger cluster; production is the smaller shape below. Compose remains
the production path until the cutover (see "Cutover").

### Release path

| Job | Identity | What it does |
| --- | --- | --- |
| `build-scan-sign` | release env | Builds, SBOMs, Trivy HIGH/CRITICAL gate, Cosign signing, uploads `release-manifest.json`. Unchanged. |
| `k8s-bootstrap` (opt-in `k8s_bootstrap=true`) | `K8S_BOOTSTRAP_KUBECONFIG` (cluster-admin) | Applies `deploy/k3s/cluster/deployer-rbac.yaml`, materializes secrets, labels/taints nodes, installs the locked add-ons (`install-k3s-addons.sh`). Idempotent. |
| `production-k8s` | `K8S_KUBECONFIG` (the `warptalk-deployer` ServiceAccount; the job refuses a cluster-admin credential) | Materializes secrets from GitHub `production`, labels/taints nodes, `deploy-k3s-data.sh`, `deploy-k3s-release.sh` (image refs and `releaseId` from the signed manifest; migrations as the pre-upgrade hook; `accept-k3s-release.sh`; automatic `helm rollback` on failed acceptance), `smoke-production.sh`, then a Kubernetes-mode health inspection into the run summary. |

`k8s_dry_run=true` runs every `production-k8s` step server-side (`kubectl apply
--dry-run=server`, `helm upgrade --dry-run=server`) plus all contract checks and changes
nothing. The bootstrap is not affected by it: it only installs add-ons, RBAC, node labels and
secrets, none of which touch compose or public traffic (unless `k8s_public_ingress`), and a
server-side dry run of the release needs the add-on CRDs to exist.

Every Helm call goes through `scripts/helm-locked.sh`, i.e. `HELM_IMAGE` from
`addons.lock.env` (3.18.6), never the runner's `helm`. Every script requires an explicit
`KUBECONFIG`; none falls back to `~/.kube/config`.

### Secrets: one source

The GitHub `production` environment is the only source. `K8S_RUNTIME_ENV` is a KEY=VALUE
file (template: `runtime-env.template`); the job overlays the individual secrets the compose
release already uses (Stripe, LiveKit, Google, Cartesia) and
`scripts/materialize-k8s-runtime-secrets.sh` writes, with server-side apply:
`warptalk/warptalk-runtime` (validated against `runtime-secret-contract.json` before
anything is applied), the four data-namespace secrets, `monitoring/warptalk-alertmanager`
and `monitoring/warptalk-grafana-admin`, and `warptalk/warptalk-ghcr` when
`GHCR_PULL_TOKEN` is set. External Secrets is kept, optional, behind
`secret.externalSecret.enabled` / `externalSecrets.enabled` and `K3S_SECRET_SOURCE`; production
turns it off and `install-k3s-addons.sh` no longer installs the operator unless
`INSTALL_EXTERNAL_SECRETS=true`.

### Placement

| Node | Label | Taint | Runs |
| --- | --- | --- | --- |
| Infra VM (control plane, 2 vCPU / 4 GiB) | `node.warptalk.io/role=infra` | kubeadm `control-plane:NoSchedule` | Prometheus, Alertmanager, Grafana, operator, kube-state-metrics (as compose runs them on Infra) |
| App VM (8 vCPU / 16 GiB) | `node.warptalk.io/role=app` | none | every WarpTalk workload, Seq, Traefik, operators |
| Data VM (2 vCPU / 8 GiB, 35 GB at /srv/warptalk) | `node.warptalk.io/role=data` | `node.warptalk.io/role=data:NoSchedule` | Postgres, PgBouncer, Redis, Qdrant, RabbitMQ |

`scripts/label-k8s-nodes.sh` applies labels and taints on every release. Without explicit
`K8S_*_NODES` variables it resolves roles from the addresses the workflow already knows
(`PRODUCTION_DATA_HOST` / `PRODUCTION_INFRA_HOST` against node InternalIPs; the rest is App).

### Capacity plan

Allocatable after the kubelet reservations set by `k8s-cluster-bootstrap.sh`
(system 200m/512Mi, kube 200m/512Mi, eviction 200Mi): App ~7.6 CPU / ~14.8 GiB, Data
~1.6 CPU / ~6.8 GiB, Infra ~1.6 CPU / ~2.8 GiB.

App node, WarpTalk requests at minimum replicas (`k8s-app-values.yaml`; limits are the
compose ceilings, ~2x the request):

| Workload | Replicas (min-max) | Request CPU / mem | Limit CPU / mem | At minimum |
| --- | --- | --- | --- | --- |
| gateway | 2-4 | 250m / 256Mi | 500m / 512Mi | 500m / 512Mi |
| frontend | 2-3 | 100m / 256Mi | 200m / 512Mi | 200m / 512Mi |
| auth-service | 2-3 | 100m / 256Mi | 200m / 512Mi | 200m / 512Mi |
| translation-room-service | 2-3 | 150m / 320Mi | 300m / 640Mi | 300m / 640Mi |
| transcript-service | 2-3 | 150m / 320Mi | 300m / 640Mi | 300m / 640Mi |
| notification-service | 2-3 | 100m / 192Mi | 200m / 384Mi | 200m / 384Mi |
| meeting-service | 2-3 | 200m / 384Mi | 400m / 768Mi | 400m / 768Mi |
| workspace-service | 2-3 | 150m / 320Mi | 300m / 640Mi | 300m / 640Mi |
| billing-service | 2-3 | 150m / 320Mi | 300m / 640Mi | 300m / 640Mi |
| assistant-service | 1 (RWO key ring) | 150m / 320Mi | 300m / 640Mi | 150m / 320Mi |
| stt-worker (KEDA) | 1-3 | 300m / 1Gi | 600m / 2Gi | 300m / 1024Mi |
| translation-worker (KEDA) | 1-3 | 150m / 384Mi | 300m / 768Mi | 150m / 384Mi |
| tts-worker (KEDA) | 1-3 | 250m / 768Mi | 500m / 1536Mi | 250m / 768Mi |
| livekit-ingress-worker | 1-3 | 250m / 768Mi | 500m / 1536Mi | 250m / 768Mi |
| assistant-worker | 1-3 | 150m / 384Mi | 300m / 768Mi | 150m / 384Mi |
| embedding-worker | 1 | 150m / 512Mi | 300m / 1Gi | 150m / 512Mi |
| suggestion-worker (singleton) | 1 | 100m / 256Mi | 200m / 512Mi | 100m / 256Mi |
| security-worker | 1 | 100m / 192Mi | 200m / 384Mi | 100m / 192Mi |
| billing-worker | 1 | 100m / 192Mi | 200m / 384Mi | 100m / 192Mi |
| metrics-exporter (singleton) | 1 | 50m / 96Mi | 100m / 192Mi | 50m / 96Mi |
| otel collector | 1 | 100m / 256Mi | 200m / 384Mi | 100m / 256Mi |
| seq | 1 | 100m / 384Mi | 200m / 640Mi | 100m / 384Mi |
| gotenberg | 1 | 100m / 128Mi | 1 / 512Mi | 100m / 128Mi |
| 3 cost exporters | 1 each | 25m / 48Mi | 200m / 128Mi | 75m / 144Mi |
| **WarpTalk total** | | | | **4825m / 11056Mi (10.8 GiB)** |

Add-ons on the App node (Traefik 2x100m/128Mi, KEDA, cert-manager, CNPG/Barman/RabbitMQ
operators, metrics-server, Calico, node-exporter) request roughly 0.9 CPU / 1.4 GiB, for
~5.7 CPU (75%) / ~12.2 GiB (82%) at rest. The remainder (~1.9 CPU / ~2.6 GiB) is HPA/KEDA
headroom: every scale-out step is at most 300m / 1 GiB, so roughly four simultaneous
scale-outs fit; beyond that pods stay Pending and `WarpTalkDeploymentReplicasUnavailable`
fires. `check-k3s-deployment.sh` fails the build if the WarpTalk total exceeds
5000m / 11 GiB.

HPA targets are a share of the request (80% for .NET/Python, 70% gateway, 75% LiveKit
ingress). With the previous 30m requests a 75% target meant "scale above 22 millicores".

Data node requests: Postgres 2 x 300m/1Gi (limit 600m/2Gi, `shared_buffers` 512MB),
PgBouncer 50m/64Mi, Redis 3 x (75m/704Mi + sentinel 25m/64Mi + exporter 10m/32Mi),
Qdrant 100m/768Mi, RabbitMQ 200m/512Mi, node-exporter 25m/32Mi: ~1.3 CPU (81%) /
~5.8 GiB (85%).

Infra node: control plane ~0.65 CPU, monitoring 350m / ~1.1 GiB requests.

Data volume (35 GB at /srv/warptalk; point the local-path provisioner's `nodePathMap` for
the Data node at it): Postgres 2 x 10Gi, Redis 3 x 1Gi, Qdrant 5Gi, RabbitMQ 2Gi = 30 GiB,
leaving ~14% for the filesystem and WAL bursts. local-path does not enforce these sizes;
`WarpTalkPersistentVolumeFilling` alerts at 15% free. A production database that outgrows
10Gi needs a larger volume, not a larger claim.

### Data layer on one VM

Postgres runs 2 instances with `synchronous.dataDurability: preferred`: a third instance on
the same VM adds no protection against losing the VM, and with `required` a restarting
standby would stop all writes. Losing the VM is covered by the WAL archive (RPO ~5 min) and
the nightly base backup. Redis runs 3 nodes because each carries a sentinel and quorum is 2.
Redis `maxmemory 640mb` + `noeviction` under an 896Mi limit: a full Redis now refuses writes
loudly instead of silently evicting live meeting state (compose's `allkeys-lru`). Qdrant runs
one node with a nightly full snapshot uploaded to the same object store as the Postgres
backups (`warptalk-qdrant-snapshot` CronJob). `pg_stat_statements` is preloaded through
CloudNativePG's managed `pg_stat_statements.*` parameters.

### Ingress path

Public traffic is NATed by Vietnix to the App VM's VPC address. MetalLB L2 cannot receive it
(the cloud SDN only delivers to addresses it assigned), a Tailscale address is not on that
network, and host ports would allow one Traefik pod per node. So Traefik is a 2-replica
Deployment whose `NodePort` Service carries the App VM's VPC address as an `externalIP` with
`externalTrafficPolicy: Local`: kube-proxy delivers :80/:443 straight to the local Traefik
pods without SNAT, and the gateway sees the client address (it trusts `X-Forwarded-For` only
from the pod CIDR, `network.podCidrs`). That is why the compose rate limits (login 5/min) are
restored. HTTP redirects to HTTPS except ACME HTTP-01 challenges; access logs drop every
header and every query parameter (SignalR sends `?access_token=` on the WebSocket upgrade);
log level INFO. MetalLB stays available in `k8s-install-cni-metallb.sh` for BGP (or L2 on a
flat network you control), off by default, addresses parameterized.

The externalIP rule takes :80/:443 on the App VM away from compose's Caddy the moment it
exists, which is why it is only set when the bootstrap runs with `k8s_public_ingress=true`.

### Hosts and URLs

Exactly as compose: `app.warptalk.io.vn` serves the frontend, `api.warptalk.io.vn` the
gateway, and every URL compose builds from `${API_DOMAIN}` (MCP redirect/metadata/JWKS,
Google Workspace redirect URIs) is built from `global.apiDomain`.
`scripts/check-k3s-compose-url-parity.sh` fails CI if any domain-derived URL differs from
compose. No DNS, Google, Stripe or MCP console change is needed. `ingress.apexDomain` is
optional and off (compose never served the apex); it gets its own Certificate.

TLS is issued and renewed by cert-manager (Let's Encrypt HTTP-01, `ClusterIssuer` from the
chart); nobody owns a manual renewal.

### SignalR and singleton workers

Hubs are hosted by the gateway (`/hubs/*`), meeting-service (`MeetingChatHub`),
assistant-service (`AssistantHub`) and billing-service (`BillingHub`). All four get
`SignalR__Redis` (the key the gateway already reads). Stickiness is on the gateway Service
only (`warptalk_gateway_affinity`); the backend PR `fix/multi-replica-safety` adds the
backplane wiring in the three services and de-duplicates the gateway's Redis subscribers.

Workloads that must be single-instance set `singleton: true` (one replica, `Recreate`, no
HPA/PDB): suggestion-worker, metrics-exporter. Services that must stay multi-replica but host
background loops that must not run twice list them in `singletonWorkers`, rendered as the
`warptalk.io/singleton-workers` annotation; the guard is the backend PR's distributed lock.

### Monitoring

Alertmanager uses the compose receiver (`observability/alertmanager.yml.example` rendered by
`render-alertmanager-config.sh`: Resend SMTP to `ALERT_EMAIL_TO`, dead-letter mute). Logs and
traces go to Seq (same image as compose); the collector's `memory_limiter` (300 MiB) sits
~20% under its 384Mi limit. The chart's alert rules begin with the compose rules verbatim and
add Kubernetes rules (crash loops, OOM kills, unavailable replicas, filling volumes, and
stream-group coverage so a regression to a hard-coded exporter list is visible).
`Monitoring__PrometheusUrl` points at the `monitoring` namespace.

### Supply chain at admission

Images are signed with Cosign in `build-scan-sign`, and the cluster only ever runs the
`@sha256` digests from that manifest (the chart refuses anything else in production). An
admission-time signature check (sigstore policy-controller or Kyverno `verifyImages`) is
NOT installed: it is another webhook + controller (~200Mi) on an App node that is already at
82% memory, and a webhook outage would block every rollout. Add it when the App node grows.

### Cutover

1. `k8s-cluster-bootstrap.sh` / `k8s-install-cni-metallb.sh` on the VMs (once).
2. Dispatch `deploy_target=k8s`, `k8s_bootstrap=true`, `k8s_dry_run=true`: the bootstrap
   installs add-ons/RBAC/labels/secrets (no public traffic), and the whole release is then
   validated server-side without changing anything. This is the staging dry run.
3. Dispatch `deploy_target=k8s` (`k8s_public_ingress=false`): the cluster runs the release
   next to compose. Acceptance runs every in-cluster check, skips the public probes (the
   domain still points at Caddy) and insists Traefik has no public address yet. Inspect it
   with the Kubernetes-mode health inspector and `kubectl port-forward`.
4. Stop compose's Caddy, then dispatch `deploy_target=k8s`, `k8s_bootstrap=true`,
   `k8s_public_ingress=true`. From then on releases use `deploy_target=k8s` and
   `k8s_public_ingress=true` (acceptance fails if the flag and the cluster disagree).
5. Roll back by starting Caddy again and deleting the Traefik Service's externalIP
   (re-run the bootstrap with `k8s_public_ingress=false`).

## Topology and prerequisites

- Kubernetes/K3s `>= 1.29.0`.
- At least three failure-domain-separated nodes for quorum workloads.
- A replicated NVMe `StorageClass`.
- A `ReadWriteMany` `StorageClass` for the assistant service's data protection key
  ring, named in `workloads.assistant-service.persistence.storageClass` in the
  provider values file. Both replicas read one ring, so `pvcs.yaml` refuses to render
  the ReadWriteOnce-with-more-than-one-pod combination that would hand each pod its own
  keys, and refuses an empty class in production rather than letting the claim land on
  whatever the cluster calls default. Choose it before the first install: a PVC spec is
  immutable, `helm.sh/resource-policy: keep` means Helm will not replace it, and
  deleting the claim to change the class discards the ring - which orphans every plugin
  secret and user OAuth token encrypted with it.
- A provider LoadBalancer implementation for Traefik.
- A production `ClusterSecretStore`.
- DNS for the application domain.
- S3-compatible object storage for PostgreSQL backup and workspace documents.

Create K3s without its bundled Traefik (`--disable=traefik`). WarpTalk installs
the checksum-locked HA Traefik chart into the `traefik` namespace; the add-on
installer rejects a conflicting bundled release.

The exact chart/operator versions, container digests and SHA-256 package
checksums are in `addons.lock.env`. `check-k3s-addons.sh` downloads and verifies
the locked packages before installation. Never replace a lock with `latest`.
The application chart additionally runs one locked OpenTelemetry image and three
locked SQL cost-exporter instances.

CloudNativePG uses three PostgreSQL instances, synchronous replication, a
three-instance PgBouncer `Pooler`, continuous WAL archive, daily base backups
and the Barman Cloud CNPG-I plugin. Applications connect to
`warptalk-postgres-pooler-rw`; only the migration Job connects directly to
`warptalk-postgres-rw`.

## Provider inputs

Copy both examples outside the repository and replace every `CHANGE_ME`:

```sh
cp deploy/k3s/data-provider-values.example.yaml /secure/warptalk-data.yaml
cp deploy/k3s/provider-values.example.yaml /secure/warptalk-app.yaml
chmod 600 /secure/warptalk-data.yaml /secure/warptalk-app.yaml
```

Create the `ClusterSecretStore` named in both files, then create these remote
records:

| Remote record | Required properties |
|---|---|
| PostgreSQL superuser | `username`, `password` |
| PostgreSQL backup | `ACCESS_KEY_ID`, `SECRET_ACCESS_KEY` |
| Redis | `password`, `dotnet-connection-string` |
| Qdrant | `api-key` |
| Runtime | Every property in `runtime-secret-contract.json` |

Use this Sentinel value for `dotnet-connection-string`:

```text
warptalk-redis.warptalk-data.svc.cluster.local:26379,serviceName=mymaster,password=<secret>,abortConnect=false
```

Every service database connection string and `BILLING_DB_DSN` must target:

```text
warptalk-postgres-pooler-rw.warptalk-data.svc.cluster.local:5432
```

The runtime record also needs `BILLING_MONITOR_DSN`, `LIVEKIT_MONITOR_DSN` and
`WORKSPACE_MONITOR_DSN`: URL-encoded PostgreSQL DSNs for `warptalk_monitor`
targeting `warptalk_billing`, `warptalk_translation_room` and
`warptalk_workspace` respectively on that same Pooler. Keeping the complete
DSNs in the secret store avoids unsafe password interpolation in Kubernetes
manifests.

The chart maps normalized runtime properties to only the workloads that need
them. The frontend receives no backend/provider secret. Notification and
Meeting receive different values for their identically named
`ConnectionStrings__DefaultConnection` setting. RabbitMQ's operator-generated
credentials are mounted only into Workspace, Notification and Billing.

`JWT_PREVIOUS_SECRETS` must exist in the runtime record, but may be empty when
there is no active rotation window. The runtime contract rejects missing,
empty, weak, placeholder and non-PgBouncer values without printing secrets.

Set every `costObservability` rate from the signed AI/LiveKit contracts and set
positive monthly budgets in the App values file. Production rendering rejects
missing, malformed or zero budgets. These values feed Prometheus/Grafana
estimates only and never customer billing.

## Deployment order

1. Verify the K3s nodes, replicated StorageClass and external LoadBalancer.
2. Install the locked cluster add-ons:

   ```sh
   K3S_STORAGE_CLASS=replicated-nvme \
   INSTALL_TRAEFIK=true \
   INSTALL_METRICS_SERVER=false \
   ./scripts/install-k3s-addons.sh
   ```

   Set `INSTALL_METRICS_SERVER=true` only when K3s does not already provide it.

3. Create and verify the provider-specific `ClusterSecretStore` and remote
   records described above.
4. Deploy the data platform:

   ```sh
   K3S_DATA_VALUES_FILE=/secure/warptalk-data.yaml \
   K3S_SECRET_STORE_NAME=warptalk-production \
   K3S_STORAGE_CLASS=replicated-nvme \
   ./scripts/deploy-k3s-data.sh
   ```

   This installs PostgreSQL/PgBouncer, Redis/Sentinel, RabbitMQ and Qdrant, then
   waits for the database cluster, pooler, RabbitMQ quorum and generated
   credentials.

5. Build and push the 21 release images, including the on-demand health
   inspector, migration, and Redis
   stream metrics images:

   ```sh
   IMAGE_REGISTRY=ghcr.io/<owner>/warptalk \
   IMAGE_TAG=<immutable-git-release-id> \
   RELEASE_MANIFEST_OUTPUT=/secure/warptalk-release.json \
   NEXT_PUBLIC_API_URL=https://<domain>/api \
   NEXT_PUBLIC_SIGNALR_URL=https://<domain> \
   NEXT_PUBLIC_LIVEKIT_URL=wss://<livekit-host> \
   NEXT_PUBLIC_GOOGLE_CLIENT_ID=<client-id> \
   ./scripts/build-release.sh
   ```

6. Deploy the immutable application release:

   ```sh
   RELEASE_MANIFEST=/secure/warptalk-release.json \
   K3S_VALUES_FILE=/secure/warptalk-app.yaml \
   K3S_SECRET_STORE_NAME=warptalk-production \
   K3S_STORAGE_CLASS=replicated-nvme \
   K3S_TLS_SECRET_NAME=warptalk-tls \
   K3S_MANAGED_TLS=true \
   ./scripts/deploy-k3s-release.sh
   ```

   The release is rejected unless all 21 release images have registry digests;
   20 are rendered into K3s while the host-only health inspector is excluded
   and all four platform image occurrences match their locked digests. The
   pre-upgrade Job applies the shared migration history, provisions service
   roles, extracts the eight logical databases when needed, applies
   service-owned migrations and enables PostgreSQL observability before any
   workload rolls.

7. Run the production smoke, security, migration-boundary and performance
   gates from outside the cluster. First record the read-only cluster
   acceptance:

   ```sh
   RELEASE_MANIFEST=/secure/warptalk-release.json \
   K3S_DOMAIN=<domain> \
   K3S_TLS_SECRET_NAME=warptalk-tls \
   K3S_REQUIRE_DISTINCT_ZONES=true \
   K3S_ACCEPTANCE_REPORT=/secure/k3s-acceptance.json \
   ./scripts/accept-k3s-release.sh
   ```

   This verifies three Ready failure domains, data quorum, exact running image
   digests, retained migration evidence, KEDA, External Secrets, telemetry,
   LoadBalancer, TLS and public security headers without mutating the cluster.
   Execute every drill in
   `FAILOVER-RUNBOOK.md` before calling the deployment HA-accepted.

## Offline and CI gates

These checks do not need provider credentials:

```sh
./scripts/check-k3s-deployment.sh
./scripts/check-k3s-addons.sh
./scripts/test-k3s-release-contract.sh
./scripts/test-k3s-runtime-secret-contract.sh

K3S_DATA_VALUES_FILE=deploy/k3s/data-provider-values.contract.yaml \
K3S_SECRET_STORE_NAME=contract-secret-store \
K3S_STORAGE_CLASS=replicated-nvme \
OFFLINE_RENDER_ONLY=true \
./scripts/deploy-k3s-data.sh
```

Offline rendering proves schema, immutability and configuration contracts. It
does not prove provider storage replication, LoadBalancer behavior, DNS/TLS,
real Stripe/LiveKit/provider writes or node-failure recovery.
