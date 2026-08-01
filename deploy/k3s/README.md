# WarpTalk multi-node K3s deployment

This directory is the provider-neutral, multi-node HA target. Application
images, add-ons and data images are immutable and digest-pinned. Provider
credentials never belong in Git.

## Topology and prerequisites

- Kubernetes/K3s `>= 1.29.0`.
- At least three failure-domain-separated nodes for quorum workloads.
- A replicated NVMe `StorageClass`.
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
