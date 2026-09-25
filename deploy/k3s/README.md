# WarpTalk multi-node K3s deployment

This directory is the provider-neutral, multi-node HA target. Application
images, add-ons and data images are immutable and digest-pinned. Provider
credentials never belong in Git.

## Production on the three Vietnix VMs

Everything in this section is what `.github/workflows/release.yml` does; Kubernetes is its only
deploy target. The generic HA target described further down is
still valid for a larger cluster; production is the smaller shape below.

**Production already runs here** (verified read-only on 2026-09-23): kubeadm v1.31.14 on
`warptalk-infra-master` (control plane), `warptalk-app-worker` and `warptalk-data-node`, all
three addressed on the tailnet (100.70.83.108 / 100.72.255.18 / 100.122.196.85; API server
`https://100.70.83.108:6443`), Calico pool 192.168.0.0/16, every workload in `warptalk`,
Traefik holding :80/:443 on the App VM with host ports. The workflow no longer has a compose
(SSH + `docker compose`) job or a staging job; `scripts/deploy-release.sh` and the compose files
stay in the repo for manual recovery of a rebuilt Docker host only.

### Release path

| Job | Identity | What it does |
| --- | --- | --- |
| `build-scan-sign` | release env | Builds, SBOMs, Trivy HIGH/CRITICAL gate, Cosign signing, uploads `release-manifest.json`. Unchanged. |
| `production-k8s` | `K8S_KUBECONFIG` (the `warptalk-deployer` ServiceAccount; the job refuses a cluster-admin credential) | Materializes secrets from GitHub `production`, labels/taints nodes, `deploy-k3s-data.sh`, `deploy-k3s-release.sh` (image refs and `releaseId` from the signed manifest; migrations as a gated Job BEFORE the upgrade; `helm upgrade --wait`, surge or in-place by measured headroom; `accept-k3s-release.sh`; on any failure `helm rollback` to the last DEPLOYED revision), `smoke-production.sh`, then a Kubernetes-mode health inspection into the run summary. |

`k8s_dry_run=true` runs every `production-k8s` step server-side (`kubectl apply
--dry-run=server`, `helm upgrade --dry-run=server`) plus all contract checks and changes
nothing. A server-side dry run of the release needs the add-on CRDs to exist, so the cluster
must have been bootstrapped first (see "Cluster bootstrap by hand" below). A release never
touches the `traefik` or `monitoring` namespaces; only the bootstrap applies their locked values.

`deploy-k3s-release.sh` runs in this order, and each step is a gate for the next
(`scripts/test-k3s-release-gate.sh` pins it with kubectl and Helm stubbed):

1. **Rollback target.** The last revision Helm marked `deployed`, read before anything changes.
   A release whose latest revision is `pending-*` (an interrupted run) is refused, with the
   rollback command in the message. Never "the previous revision": after a failed upgrade that is
   a failed one, which is what `--atomic` rolled back to on 24 Sep (and hit PDBs that revision
   had never created).
2. **Migrations.** The chart renders the migrator ServiceAccount and a
   `warptalk-migrations-<release>` Job (`migrations.mode=job`); the script applies it and waits.
   If it fails, the release stops with nothing rolled and the running pods keep the schema they
   were built for. The runner skips already-applied files, so a re-run is harmless. The release
   itself carries no migration hook (`migrations.mode: external`).
3. **Rollout shape.** Surge (`maxSurge 1 / maxUnavailable 0`) when the App node can fit one more
   pod of the release's largest workload, measured from live requests; otherwise this one
   release replaces pods in place (surge 0 / unavailable 1) and says so with a `::warning::`.
   `K3S_ROLLOUT_MODE=surge|in-place` forces either.
4. **Upgrade.** `helm upgrade --wait --timeout 15m`, no `--atomic`. On failure, and on failed
   acceptance afterwards, `helm rollback <last deployed> --wait`. Migrations stay applied: they
   are additive, and the previous images run against the new schema.

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

Right-sized on 2026-09-24 from Prometheus on the production cluster
(`container_memory_working_set_bytes` and `rate(container_cpu_usage_seconds_total[5m])`, `[7d]`
range, which is the cluster's whole 4.8-day life including the first releases and live meetings).
Rule: request ~= p95 x 1.3, rounded up to 16Mi / 10m, floors 128Mi / 50m; HPA-managed workloads
get CPU >= 100m and high enough that p95 sits below the HPA target (at 150m/200m requests
assistant-worker and livekit-ingress-worker sat at 3/3 replicas for days). Limits keep compose's
headroom (>= ~1.5x the request).

The App node's allocatable is **15892Mi / 8 CPU** (kubelet reports 16273348Ki; the cluster was
built without kubelet reservations). On 24 Sep its requests were at 99% (15872Mi) while pods used
~8.6 GiB.

| Workload | Min replicas | Observed p95 / max memory | Observed p95 CPU | Memory request old -> new | CPU request old -> new |
| --- | --- | --- | --- | --- | --- |
| frontend | 2 | 121 / 154Mi | 25m | 256 -> 160Mi | 100 -> 100m |
| gateway | 2 | 148 / 160Mi | 60m | 256 -> 208Mi | 250 -> 100m |
| auth-service | 2 | 233 / 241Mi | 38m | 256 -> 304Mi | 100 -> 100m |
| translation-room-service | 2 | 215 / 219Mi | 44m | 320 -> 288Mi | 150 -> 100m |
| transcript-service | 2 | 182 / 192Mi | 42m | 320 -> 240Mi | 150 -> 100m |
| notification-service | 2 | 169 / 182Mi | 29m | 192 -> 224Mi | 100 -> 100m |
| meeting-service | 2 | 184 / 193Mi | 29m | 384 -> 240Mi | 200 -> 100m |
| workspace-service | 2 | 253 / 265Mi | 48m | 320 -> 336Mi | 150 -> 100m |
| billing-service | 2 | 223 / 229Mi | 48m | 320 -> 304Mi | 150 -> 100m |
| assistant-service | 1 -> **2** | 193 / 196Mi | 31m | 320 -> 256Mi | 150 -> 50m |
| stt-worker (KEDA) | 1 | 122 / 160Mi | 93m | 384 -> 160Mi | 150 -> 130m |
| translation-worker (KEDA) | 1 | 124 / 132Mi | 73m | 384 -> 176Mi | 150 -> 100m |
| tts-worker (KEDA) | 1 | 112 / 157Mi | 65m | 384 -> 160Mi | 150 -> 90m |
| livekit-ingress-worker (HPA) | 1 | 629 / 649Mi | 205m | **512 -> 832Mi** | 200 -> 320m |
| assistant-worker (HPA) | 1 | 115 / 154Mi | 119m | 384 -> 160Mi | 150 -> 180m |
| embedding-worker | 1 | 116 / 152Mi | 93m | 512 -> 160Mi | 150 -> 130m |
| suggestion-worker (singleton) | 1 | 113 / 125Mi | 90m | 256 -> 160Mi | 100 -> 120m |
| transcript-clean-worker (singleton, WT-716, new) | 1 | not measured yet | - | 256 -> 192Mi | 100 -> 50m |
| security-worker | 1 | 112 / 115Mi | 86m | 192 -> 160Mi | 100 -> 120m |
| billing-worker | 1 | 90 / 92Mi | 91m | 192 -> 128Mi | 100 -> 120m |
| metrics-exporter (singleton) | 1 | 58 / 58Mi | 10m | 96 -> 80Mi | 50 -> 25m |
| gotenberg | 1 | 170 / 171Mi | 3m | **128 -> 224Mi** | 100 -> 100m |
| otel collector | 1 | 88 / 90Mi | 15m | 256 -> 128Mi | 100 -> 50m |
| seq | 1 | 132 / 146Mi | 13m | 384 -> 176Mi | 100 -> 50m |
| 3 cost exporters | 1 each | 14 / 14Mi | 1m | 48 -> 32Mi each | 25 -> 10m each |
| **WarpTalk chart at minimum replicas** | | | | **10352 -> 8112Mi** | **4775 -> 3515m** |
| Postgres x2 (data chart, App node) | 2 | 315 / 402Mi, 259 / 263Mi | 18m | 1Gi -> 512Mi each | 300 -> 100m each |

Everything else requesting memory on the App node, unchanged here: add-ons 1200Mi (KEDA 3 x
100Mi, metrics-server 200Mi, Alertmanager 200Mi, RabbitMQ operator 500Mi - its p95 is 23Mi, a
follow-up for `install-k3s-addons.sh`), redis-node-0 800Mi and RabbitMQ 512Mi (both changed only
in their runbook steps, because a change restarts them).

**App node at minimum replicas: 11456Mi of 15892Mi requested (72.1%), 4436Mi (27.9%) free** -
room for one surge pod of the largest workload (livekit-ingress-worker, 832Mi) plus
redis-node-0 (800Mi) with 2.8 GiB to spare. `check-k3s-deployment.sh` computes this from the
rendered chart and the data values and fails the build below 25% free or below that headroom.
After `DATA-PLACEMENT-RUNBOOK.md` moves Postgres, redis-node-0 and RabbitMQ to the Data node,
another ~2.3 GiB comes back.

Two things the requests do not cover: Prometheus and Grafana run on the App node with **no**
requests (~1.1 GiB and ~0.4 GiB working set), and a live meeting raises the workers' working
set. The limits, not the requests, are the ceiling for both; `WarpTalkDeploymentReplicasUnavailable`
fires if a scale-out cannot schedule.

HPA targets are a share of the request (80% for .NET/Python, 70% gateway, 75% LiveKit
ingress). With the previous 30m requests a 75% target meant "scale above 22 millicores".

Data node requests: Postgres 2 x 300m/1Gi (limit 600m/2Gi, `shared_buffers` 512MB),
PgBouncer 50m/64Mi, Redis 3 x (75m/704Mi + sentinel 25m/64Mi + exporter 10m/32Mi),
Qdrant 100m/768Mi, RabbitMQ 200m/512Mi, node-exporter 25m/32Mi: ~1.3 CPU (81%) /
~5.8 GiB (85%) - the plan for when everything is on it. Today it carries Qdrant, PgBouncer,
MinIO and redis-node-1 (15% requested).

Infra node: control plane ~0.65 CPU, monitoring 350m / ~1.1 GiB requests.

Data claims: the live claims were created at Postgres 2 x 25Gi, Redis 20Gi each, Qdrant 50Gi
and RabbitMQ 5Gi, and a claim cannot shrink (CloudNativePG rejects it; StatefulSet claim
templates are immutable), so the values keep those sizes and CI refuses anything smaller. On
paper that exceeds the Data VM's 35 GB volume, and **a bigger volume is required before the
claims could ever fill**: local-path does not enforce sizes, actual use on 2026-09-23 was under
1 GiB, and `WarpTalkPersistentVolumeFilling` alerts at 15% free.

### Zero-downtime rollouts

- Every Deployment surges (`maxSurge 1 / maxUnavailable 0`, chart default; production values do
  not override it). The deploy script falls back to in-place for one release only when the App
  node cannot fit the extra pod.
- Readiness gates traffic (5s period, 3s timeout); a startup probe (up to 3 min) keeps liveness
  from killing a slow start while two dozen pods start at once.
- Drain: `preStop` is the kubelet's own `sleep` action (10s, no binary needed in the image), so
  Traefik and kube-proxy stop routing before SIGTERM; `terminationGracePeriodSeconds: 45` covers
  that plus ASP.NET Core's 30s shutdown (gotenberg 75s for a conversion in flight).
- Every user-facing service keeps >= 2 replicas and a PDB with `maxUnavailable: 1`
  (assistant-service included: its RWO local-path key ring is node-local, so both pods mount it on
  the node that holds it; see `templates/pvcs.yaml`, `persistence.nodeLocal`).
- Replicas spread softly over `kubernetes.io/hostname` (and zone): `ScheduleAnyway`, so one App
  node still schedules everything, and a second App node gets one replica of each automatically.
- Data pods run under the `warptalk-data-critical` PriorityClass (data chart): a data pod that
  cannot schedule preempts application pods; application pods carry no class and can never
  preempt a data pod.

### Data layer on one VM

As found live: both Postgres instances, `warptalk-redis-node-0` and RabbitMQ run on the **App**
node, because their local-path volumes were first bound there. Placement is therefore soft
(prefer `node.warptalk.io/role=data`, tolerate its taint); a hard selector would leave those pods
Pending next to volumes they cannot leave. Moving them is deliberate work, step by step with
verification and rollback in [`DATA-PLACEMENT-RUNBOOK.md`](DATA-PLACEMENT-RUNBOOK.md): Postgres
via a third CloudNativePG instance on the Data node and a switchover; Redis by promoting
redis-node-1 (already on the Data node) and re-creating node-0's volume there; RabbitMQ in a short
maintenance window.

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

As production runs it: the public address is NATed to the App VM, where Traefik takes :80/:443
with host ports (the MetalLB address 10.20.0.100 on its LoadBalancer Service is only reachable
inside the VPC). Host-port traffic is DNATed by the CNI portmap plugin without SNAT, so Traefik
sees the client address, and the gateway trusts `X-Forwarded-For` only from the pod CIDR
(`network.podCidrs` = 192.168.0.0/16). The previous values made the gateway see every client as
the Traefik pod, which is why the per-IP limits had been raised; they are back at the compose
values (login 5/min). The locked values add the HTTP->HTTPS redirect (ACME HTTP-01 exempt),
drop every header and every query parameter from access logs (SignalR sends `?access_token=`
on the WebSocket upgrade), keep log level INFO and set `externalTrafficPolicy: Local` on the
in-VPC Service.

Replicas: a host port admits one Traefik pod per node and only the App VM receives public
traffic, so there is one Traefik pod (rolled with `maxSurge: 0`). A second replica needs a second
ingress-capable node (public address + `node.warptalk.io/role=app`); the required
anti-affinity then spreads them. MetalLB L2 across the VPC or the tailnet cannot carry public
traffic; `k8s-install-cni-metallb.sh` keeps MetalLB optional with BGP/L2 mode and addresses as
parameters.

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

**Grafana in the admin portal.** Grafana is published at `https://app.warptalk.io.vn/grafana/`
(same origin as the admin portal) and embedded by `/admin/health`. Every request passes a Traefik
ForwardAuth to the gateway's `/internal/grafana/auth`, which validates the WarpTalk JWT from the
`access_token` cookie and requires the system-admin role; Grafana runs `auth.proxy` and trusts
`X-WEBAUTH-USER` only from the pod CIDR, and a NetworkPolicy admits only Traefik and the
`monitoring` namespace. There is no anonymous access. Break-glass: `kubectl -n monitoring
port-forward svc/monitoring-grafana 3000:80`, then `http://localhost:3000/grafana/` with the
`warptalk-grafana-admin` password. The provisioned dashboards (`chart/files/dashboards`, uids
`warptalk-meetings`, `warptalk-platform`, `warptalk-pods`) ship with the app release; the
Grafana settings, the Middlewares and the platform alert rules ship with `monitoring-values.yaml`,
which is applied only by the add-on bootstrap (`k8s_bootstrap=true`), not by a normal release.

The kubeadm control plane (etcd, scheduler, controller-manager, kube-proxy) binds its metrics to
127.0.0.1, so those four components are disabled in `monitoring-values.yaml` rather than left as
permanently-down targets raising false critical alerts.

### Supply chain at admission

Images are signed with Cosign in `build-scan-sign`, and the cluster only ever runs the
`@sha256` digests from that manifest (the chart refuses anything else in production). An
admission-time signature check (sigstore policy-controller or Kyverno `verifyImages`) is
NOT installed: it is another webhook + controller (~200Mi) on an App node that is already at
82% memory, and a webhook outage would block every rollout. Add it when the App node grows.

### Before the next release

1. Deployer identity, with the admin kubeconfig you already have (again after any change to the
   file - it now also grants the `warptalk-data-critical` PriorityClass, without which
   `deploy-k3s-data.sh` stops in its preflight):
   `kubectl --kubeconfig ~/.kube/config-warptalk-prod apply --server-side -f deploy/k3s/cluster/deployer-rbac.yaml`
2. `K8S_KUBECONFIG` in the GitHub `production` environment, from that ServiceAccount:
   `KUBECONFIG=~/.kube/config-warptalk-prod K8S_API_SERVER=https://100.70.83.108:6443 scripts/render-k8s-deployer-kubeconfig.sh | gh secret set K8S_KUBECONFIG --env production --repo WarpTalk-CapstoneProject/warptalk-infrastructure`
3. Tailscale ACL: `tag:github-actions` must reach `100.70.83.108:6443` (today it reaches the App
   host for SSH).
4. Recommended before step 5: `K8S_RUNTIME_ENV` (template `runtime-env.template`), which moves
   the runtime secrets off the `fake` ClusterSecretStore - whose values sit in plain text in the
   store's own spec - onto GitHub `production`. Without it the release still runs, on the store,
   and warns.
5. Dispatch with `k8s_dry_run=true` (no changes), then for real. The locked Traefik and
   monitoring values come from the cluster bootstrap below; until it has run, acceptance reports
   Traefik as "not yet on locked values" instead of checking the redirect.

### Cluster bootstrap by hand

The release workflow used to carry an opt-in `k8s-bootstrap` job; it was removed because it was
always skipped. The cluster is already bootstrapped. If it is ever rebuilt, or the locked
Traefik/monitoring/add-on values change, run the same idempotent steps from a checkout of
`warptalk-infrastructure` with an **admin** kubeconfig (cluster-admin, never the deployer one),
over the tailnet, with Docker running (every Helm call goes through `scripts/helm-locked.sh`):

```sh
export KUBECONFIG=~/.kube/config-warptalk-prod    # admin; every script refuses an implicit one
export K3S_STORAGE_CLASS=local-path

# 1. Deployer identity and namespaces
kubectl apply --server-side -f deploy/k3s/cluster/deployer-rbac.yaml

# 2. Runtime secrets (Alertmanager and Grafana read them). The file is K8S_RUNTIME_ENV from the
#    GitHub `production` environment (template: runtime-env.template); delete it afterwards.
K8S_RUNTIME_ENV_FILE=/path/to/k8s-runtime.env ./scripts/materialize-k8s-runtime-secrets.sh

# 3. Node roles and taints (same addresses as vars.PRODUCTION_DATA_HOST / PRODUCTION_INFRA_HOST)
K8S_DATA_NODE_IP=<data node IP> K8S_INFRA_NODE_IP=<infra node IP> ./scripts/label-k8s-nodes.sh

# 4. Locked add-ons (Traefik, kube-prometheus-stack, metrics-server, external-secrets, ...)
INSTALL_METRICS_SERVER=true METRICS_SERVER_KUBELET_INSECURE_TLS=true \
  INSTALL_EXTERNAL_SECRETS=true ./scripts/install-k3s-addons.sh
```

Every step is `upgrade --install` or a server-side apply, so re-running is safe. Step 2 overlays
`STRIPE_*`, `LIVEKIT_*`, `GOOGLE_*`, `CARTESIA_*` and `GHCR_PULL_*` only when they are exported;
the next release overlays them from GitHub anyway. Follow with a `k8s_dry_run=true` dispatch.
For a brand-new cluster, `scripts/k8s-cluster-bootstrap.sh` covers the kubeadm steps before this.

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
   migration gate Job (run by the script before `helm upgrade`, not as a hook)
   applies the shared migration history, provisions service roles, extracts the
   eight logical databases when needed, applies service-owned migrations and
   enables PostgreSQL observability before any workload rolls.

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
