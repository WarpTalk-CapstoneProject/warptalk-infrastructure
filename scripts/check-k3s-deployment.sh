#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART_DIR="$ROOT_DIR/deploy/k3s/chart"
DATA_CHART_DIR="$ROOT_DIR/deploy/k3s/data-chart"
RENDERED_FILE="${TMPDIR:-/tmp}/warptalk-k3s-rendered.yaml"
DATA_RENDERED_FILE="${TMPDIR:-/tmp}/warptalk-k3s-data-rendered.yaml"

required_files=(
  "$CHART_DIR/Chart.yaml"
  "$CHART_DIR/values.yaml"
  "$CHART_DIR/templates/workloads.yaml"
  "$CHART_DIR/templates/services.yaml"
  "$CHART_DIR/templates/pdbs.yaml"
  "$CHART_DIR/templates/hpas.yaml"
  "$CHART_DIR/templates/ingress.yaml"
  "$CHART_DIR/templates/pvcs.yaml"
  "$CHART_DIR/templates/certificate.yaml"
  "$CHART_DIR/templates/security-headers.yaml"
  "$CHART_DIR/templates/telemetry.yaml"
  "$CHART_DIR/templates/gotenberg.yaml"
  "$CHART_DIR/templates/network-policy.yaml"
  "$CHART_DIR/templates/metrics-exporter-monitor.yaml"
  "$CHART_DIR/templates/observability-assets.yaml"
  "$CHART_DIR/templates/cost-observability.yaml"
  "$CHART_DIR/files/otel-collector.yaml"
  "$CHART_DIR/files/warptalk.rules.yml"
  "$CHART_DIR/files/warptalk-overview.json"
  "$DATA_CHART_DIR/Chart.yaml"
  "$DATA_CHART_DIR/values.yaml"
  "$DATA_CHART_DIR/templates/cloudnative-pg.yaml"
  "$DATA_CHART_DIR/templates/rabbitmq-cluster.yaml"
  "$DATA_CHART_DIR/templates/external-secrets.yaml"
  "$DATA_CHART_DIR/templates/network-policy.yaml"
  "$ROOT_DIR/deploy/k3s/data/redis-values.yaml"
  "$ROOT_DIR/deploy/k3s/data/qdrant-values.yaml"
  "$ROOT_DIR/deploy/k3s/addons.lock.env"
  "$ROOT_DIR/deploy/k3s/FAILOVER-RUNBOOK.md"
  "$ROOT_DIR/scripts/check-k3s-addons.sh"
  "$ROOT_DIR/scripts/install-k3s-addons.sh"
  "$ROOT_DIR/scripts/deploy-k3s-data.sh"
  "$ROOT_DIR/scripts/deploy-k3s-release.sh"
  "$ROOT_DIR/scripts/check-k3s-runtime-secret.sh"
  "$ROOT_DIR/scripts/accept-k3s-release.sh"
  "$ROOT_DIR/scripts/test-k3s-runtime-secret-contract.sh"
  "$ROOT_DIR/deploy/k3s/runtime-secret-contract.json"
  "$ROOT_DIR/scripts/test-k3s-release-contract.sh"
  "$ROOT_DIR/scripts/test-k3s-release-gate.sh"
  "$DATA_CHART_DIR/templates/priority-class.yaml"
  "$ROOT_DIR/deploy/k3s/DATA-PLACEMENT-RUNBOOK.md"
  "$ROOT_DIR/scripts/pin-qdrant-images.sh"
  "$ROOT_DIR/deploy/k3s/migrator.Dockerfile"
  "$ROOT_DIR/scripts/run-k3s-migrations.sh"
  "$ROOT_DIR/scripts/helm-locked.sh"
  "$ROOT_DIR/scripts/materialize-k8s-runtime-secrets.sh"
  "$ROOT_DIR/scripts/label-k8s-nodes.sh"
  "$ROOT_DIR/scripts/render-k8s-deployer-kubeconfig.sh"
  "$ROOT_DIR/scripts/check-k3s-compose-url-parity.sh"
  "$ROOT_DIR/scripts/test-k8s-runtime-secrets-contract.sh"
  "$ROOT_DIR/deploy/k3s/cluster/deployer-rbac.yaml"
  "$ROOT_DIR/deploy/k3s/monitoring-values.yaml"
  "$ROOT_DIR/deploy/k3s/runtime-env.template"
  "$ROOT_DIR/deploy/k3s/local/kind-local-cluster.yaml"
  "$CHART_DIR/templates/seq.yaml"
  "$DATA_CHART_DIR/templates/qdrant-snapshots.yaml"
)

for file in "${required_files[@]}"; do
  [[ -f "$file" ]] || {
    echo "missing K3s artifact: $file" >&2
    exit 1
  }
done

HELM="$ROOT_DIR/scripts/helm-locked.sh"
"$HELM" template warptalk "$CHART_DIR" --namespace warptalk >"$RENDERED_FILE"
"$HELM" template warptalk-data "$DATA_CHART_DIR" --namespace warptalk-data >"$DATA_RENDERED_FILE"

docker run --rm -i \
  ghcr.io/yannh/kubeconform:v0.7.0-alpine \
  -strict -summary -ignore-missing-schemas <"$RENDERED_FILE"
docker run --rm -i \
  ghcr.io/yannh/kubeconform:v0.7.0-alpine \
  -strict -summary -ignore-missing-schemas <"$DATA_RENDERED_FILE"

grep -Fq "kind: PodDisruptionBudget" "$RENDERED_FILE"
grep -Fq "kind: HorizontalPodAutoscaler" "$RENDERED_FILE"
grep -Fq "kind: ScaledObject" "$RENDERED_FILE"
grep -Fq "kind: TriggerAuthentication" "$RENDERED_FILE"
grep -Fq "type: redis-sentinel-streams" "$RENDERED_FILE"
grep -Fq "sentinelMaster: mymaster" "$RENDERED_FILE"
grep -Fq "stream: audio:chunks" "$RENDERED_FILE"
grep -Fq "consumerGroup: stt-workers" "$RENDERED_FILE"
grep -Fq "stream: stt:results" "$RENDERED_FILE"
grep -Fq "consumerGroup: translate-workers" "$RENDERED_FILE"
grep -Fq "stream: translate:results" "$RENDERED_FILE"
grep -Fq "consumerGroup: tts-workers" "$RENDERED_FILE"
if grep -Fq "type: prometheus" "$RENDERED_FILE"; then
  echo "KEDA must use the real Redis Sentinel stream lag, not an unevaluated Prometheus metric" >&2
  exit 1
fi
grep -Fq "shared.health_probe" "$RENDERED_FILE"
grep -Fq "REDIS_SENTINEL_URLS" "$RENDERED_FILE"
grep -Fq "REDIS_SENTINEL_SERVICE_NAME" "$RENDERED_FILE"
grep -Fq "warptalk-rabbitmq.warptalk.svc.cluster.local" "$RENDERED_FILE"
grep -Fq "warptalk-qdrant.warptalk-data.svc.cluster.local" "$RENDERED_FILE"
grep -Fq "VECTOR_DB_URL" "$RENDERED_FILE"
grep -Fq "OTEL_EXPORTER_OTLP_ENDPOINT" "$RENDERED_FILE"
grep -Fq "http://warptalk-otel-collector:4317" "$RENDERED_FILE"
grep -Fq "name: warptalk-otel-collector" "$RENDERED_FILE"
grep -Fq "kind: ServiceMonitor" "$RENDERED_FILE"
grep -Fq "name: metrics-exporter" "$RENDERED_FILE"
grep -Fq "path: /metrics" "$RENDERED_FILE"
grep -Fq "kind: PrometheusRule" "$RENDERED_FILE"
grep -Fq "name: warptalk-grafana-dashboard" "$RENDERED_FILE"
# The admin System Health page builds /grafana/d/<uid> from these uids (warptalk-web).
grep -Fq "name: warptalk-grafana-dashboards" "$RENDERED_FILE"
for dashboard_uid in warptalk-meetings warptalk-platform warptalk-pods; do
  grep -Fq "\"uid\": \"$dashboard_uid\"" "$RENDERED_FILE"
done
grep -Fq "warptalk_meeting_ended_total" "$RENDERED_FILE"
grep -Fq "warptalk_stage_messages_total" "$RENDERED_FILE"
grep -Fq "redis_stream_group_lag" "$RENDERED_FILE"
grep -Fq "redis_stream_group_messages_pending" "$RENDERED_FILE"
grep -Fq "redis_keys_count" "$RENDERED_FILE"
grep -Fq "name: billing-cost-exporter" "$RENDERED_FILE"
grep -Fq "name: livekit-cost-exporter" "$RENDERED_FILE"
grep -Fq "name: workspace-storage-exporter" "$RENDERED_FILE"
grep -Fq "warptalk_ai_cost_30d" "$RENDERED_FILE"
grep -Fq "warptalk_livekit_cost_30d" "$RENDERED_FILE"
grep -Fq "warptalk_object_storage_bytes" "$RENDERED_FILE"
grep -Fq "sha256:f2de0ba8061268bd980d206101846d461117439bb61a9b666a5ffc4f77ad1afa" "$RENDERED_FILE"
grep -Fq "kind: Middleware" "$RENDERED_FILE"
grep -Fq "name: warptalk-security-headers" "$RENDERED_FILE"
grep -Fq "customFrameOptionsValue: DENY" "$RENDERED_FILE"
grep -Fq "contentSecurityPolicy:" "$RENDERED_FILE"
grep -Fq "frame-ancestors 'none'" "$RENDERED_FILE"
grep -Fq "stsSeconds: 31536000" "$RENDERED_FILE"
grep -Fq "endpoint: 0.0.0.0:8889" "$RENDERED_FILE"
for grpc_port in 50051 50052 50053 50054 50055 50056 50057; do
  grep -Fq "port: $grpc_port" "$RENDERED_FILE"
  grep -Fq "containerPort: $grpc_port" "$RENDERED_FILE"
done
[[ "$(grep -Fc -- "- name: grpc" "$RENDERED_FILE")" -eq 14 ]] || {
  echo "expected exactly seven gRPC container ports and seven gRPC service ports" >&2
  exit 1
}
required_runtime_config=(
  "API_GATEWAY_URL"
  "AllowedOrigins__0"
  "ReverseProxy__Clusters__auth-cluster__Destinations__auth-service__Address"
  "ReverseProxy__Clusters__assistant-cluster__Destinations__assistant-service__Address"
  "GrpcSettings__AuthServiceUrl"
  "GrpcSettings__WorkspaceServiceUrl"
  "GrpcSettings__TranslationRoomServiceUrl"
  "GrpcSettings__TranscriptServiceUrl"
  "GrpcSettings__NotificationServiceUrl"
  "GrpcUrls__BillingServiceUrl"
  "GrpcUrls__TranslationRoomService"
  "GrpcUrls__BillingService"
  "ASSISTANT_CHAT_WORKSPACE_SERVICE_URL"
  "ASSISTANT_CHAT_TRANSCRIPT_SERVICE_URL"
  "ASSISTANT_CHAT_TRANSLATION_ROOM_SERVICE_URL"
  "ASSISTANT_CHAT_ASSISTANT_SERVICE_URL"
  "PGHOST"
  "PGPORT"
  "PGDATABASE"
)
for config_key in "${required_runtime_config[@]}"; do
  grep -Fq "$config_key" "$RENDERED_FILE"
done
grep -Fq "http://transcript-service:50053" "$RENDERED_FILE"
grep -Fq "https://app.example.com" "$RENDERED_FILE"
grep -Fq "secretKey: REDIS_PASSWORD" "$RENDERED_FILE"
grep -Fq "secretKey: Redis__ConnectionString" "$RENDERED_FILE"
grep -Fq "secretKey: ConnectionStrings__Redis" "$RENDERED_FILE"
grep -Fq "secretKey: VECTOR_DB_API_KEY" "$RENDERED_FILE"
grep -Fq "secretKey: PGUSER" "$RENDERED_FILE"
grep -Fq "secretKey: PGPASSWORD" "$RENDERED_FILE"
grep -Fq "warptalk-postgres-rw.warptalk-data.svc.cluster.local" "$RENDERED_FILE"
deployment_documents="$(mktemp "${TMPDIR:-/tmp}/warptalk-k3s-deployments.XXXXXX")"
trap 'rm -f "$deployment_documents"' EXIT
awk 'BEGIN { RS="---" } /kind: Deployment/ { print "---" $0 }' \
  "$RENDERED_FILE" >"$deployment_documents"
if grep -A1 -F "secretRef:" "$deployment_documents" |
  grep -Fq "name: warptalk-runtime"; then
  echo "workloads must select least-privilege secret keys, not import the full runtime secret" >&2
  exit 1
fi
frontend_document="$(awk 'BEGIN { RS="---" } /kind: Deployment/ && /name: frontend/ { print }' "$RENDERED_FILE")"
if printf '%s\n' "$frontend_document" | grep -Fq "secretKeyRef:"; then
  echo "frontend must not receive backend/provider secrets" >&2
  exit 1
fi
[[ "$(grep -Fc "name: RabbitMq__Username" "$deployment_documents")" -eq 3 ]] || {
  echo "RabbitMQ credentials must be scoped to the three RabbitMQ consumers" >&2
  exit 1
}

# The assistant plugin surface. Every key below was in deploy/production/app.compose.yml and in
# no k3s file: the chart would have started assistant-service with no plugin client identity and
# an in-memory key ring, which is the failure that does not announce itself.
assistant_document="$(awk 'BEGIN { RS="---" } /kind: Deployment/ && /name: assistant-service/ && !/HorizontalPodAutoscaler/ { print }' "$RENDERED_FILE")"
[[ -n "$assistant_document" ]] || {
  echo "could not find the assistant-service Deployment in the rendered chart" >&2
  exit 1
}
for assistant_key in \
  Plugins__Mcp__Client__RedirectUri \
  Plugins__Mcp__Client__ClientMetadataUrl \
  Plugins__Mcp__Client__JwksUrl \
  Plugins__Mcp__Client__ClientUri \
  Plugins__GoogleWorkspace__OAuth__RedirectUri \
  Plugins__GoogleWorkspace__OAuth__LegacyRedirectUri \
  Plugins__GoogleWorkspace__OAuth__ClientId \
  Plugins__GoogleWorkspace__OAuth__ClientSecret \
  DataProtection__KeyRingPath; do
  printf '%s\n' "$assistant_document" | grep -Fq "$assistant_key" || {
    echo "assistant-service must carry $assistant_key, as production compose does" >&2
    exit 1
  }
done
printf '%s\n' "$assistant_document" | grep -Fq "claimName: assistant-service-keyring" || {
  echo "the assistant key ring must outlive the pod, or a rollout orphans every plugin token written before it" >&2
  exit 1
}
printf '%s\n' "$assistant_document" | grep -Fq "fsGroup:" || {
  echo "a root-owned key ring volume is unwritable by a non-root container; the pod needs fsGroup" >&2
  exit 1
}
# The claim itself, not the template that writes it: assistant-service runs more than one pod, so
# anything short of RWX gives one of them a key ring the other is not reading.
keyring_claim="$(awk 'BEGIN { RS="---" } /kind: PersistentVolumeClaim/ && /assistant-service-keyring/ { print }' "$RENDERED_FILE")"
printf '%s\n' "$keyring_claim" | grep -Fq "accessModes: [ReadWriteMany]" || {
  echo "the assistant key ring claim must be ReadWriteMany while the workload runs more than one pod" >&2
  exit 1
}
printf '%s\n' "$keyring_claim" | grep -Fq "helm.sh/resource-policy: keep" || {
  echo "uninstalling the release must not take the key ring with it" >&2
  exit 1
}
printf '%s\n' "$assistant_document" | grep -Fq "mountPath: /var/lib/warptalk/keys"

# The minutes PDF converter, and the same shape of omission as the assistant keys above: an unset
# Gotenberg:Url is a SUPPORTED state in the backend, so the chart rendered, deployed and passed
# every probe while answering 503 to every PDF download. Only a comparison between the workload
# that converts and the workload that asks it to can see that.
translation_room_document="$(awk 'BEGIN { RS="---" } /kind: Deployment/ && /name: translation-room-service/ { print }' "$RENDERED_FILE")"
printf '%s\n' "$translation_room_document" | grep -Fq "http://gotenberg:3000" || {
  echo "translation-room-service must point at the internal gotenberg converter, or every PDF export answers 503" >&2
  exit 1
}
gotenberg_document="$(awk 'BEGIN { RS="---" } /kind: Deployment/ && /name: gotenberg/ { print }' "$RENDERED_FILE")"
[[ -n "$gotenberg_document" ]] || {
  echo "could not find the gotenberg Deployment in the rendered chart" >&2
  exit 1
}
printf '%s\n' "$gotenberg_document" | grep -Fq -- "--chromium-disable-javascript=true" || {
  echo "gotenberg must run with Chromium scripting disabled: a browser that fetches arbitrary URLs on request is an SSRF engine inside the cluster" >&2
  exit 1
}
printf '%s\n' "$gotenberg_document" | grep -Fq "readOnlyRootFilesystem: true"
grep -Fq "name: allow-gotenberg-from-translation-room" "$RENDERED_FILE"
# Internal only. The converter takes a document and returns a document; nothing outside the
# cluster has any business reaching it, and an Ingress path would be the way that happened.
if printf '%s\n' "$(awk 'BEGIN { RS="---" } /kind: Ingress/ { print }' "$RENDERED_FILE")" |
  grep -Fq "name: gotenberg"; then
  echo "gotenberg must not be routed through the ingress" >&2
  exit 1
fi

# The CIMD document has to reach the gateway, or an authorization server cannot resolve the client
# id the service advertises. Checking the path alone would pass with it routed to the frontend,
# which is exactly the bug.
ingress_document="$(awk 'BEGIN { RS="---" } /kind: Ingress/ { print }' "$RENDERED_FILE")"
printf '%s\n' "$ingress_document" |
  grep -A4 -F "path: /oauth/client-metadata" |
  grep -Fq "name: gateway" || {
  echo "/oauth/client-metadata must route to the gateway, not the frontend" >&2
  exit 1
}
for secret_key in \
  AUTH_CONNECTION_STRING \
  WORKSPACE_CONNECTION_STRING \
  TRANSLATION_ROOM_CONNECTION_STRING \
  TRANSCRIPT_CONNECTION_STRING \
  NOTIFICATION_CONNECTION_STRING \
  MEETING_CONNECTION_STRING \
  ASSISTANT_CONNECTION_STRING \
  BILLING_CONNECTION_STRING \
  BILLING_DB_DSN; do
  grep -Fq "key: $secret_key" "$deployment_documents"
done
if grep -Fq "Qdrant__Url" "$RENDERED_FILE"; then
  echo "K3s Qdrant configuration must use the AI worker VECTOR_DB_URL contract" >&2
  exit 1
fi
if grep -Fq "Redis__Url" "$RENDERED_FILE"; then
  echo "K3s must not route Redis writes through a non-Sentinel direct URL" >&2
  exit 1
fi
grep -Fq "app.kubernetes.io/name: traefik" "$RENDERED_FILE"
grep -Fq "kubernetes.io/metadata.name: traefik" "$RENDERED_FILE"
grep -Fq "mountPath: /app/.next/cache" "$RENDERED_FILE"
grep -Fq "mountPath: /app/.cache" "$RENDERED_FILE"
grep -Fq "topology.kubernetes.io/zone" "$RENDERED_FILE"
grep -Fq "maxUnavailable: 0" "$RENDERED_FILE"
grep -Fq "checksum/config:" "$RENDERED_FILE"
grep -Fq 'helm.sh/hook: pre-install,pre-upgrade' "$RENDERED_FILE"
grep -Fq "global.production" "$CHART_DIR/templates/workloads.yaml"
grep -Fq 'kubeVersion: ">=1.29.0-0"' "$CHART_DIR/Chart.yaml"
grep -Fq "@sha256:" "$CHART_DIR/templates/workloads.yaml"
grep -Fq "migrator.imageRef" "$CHART_DIR/templates/migration-job.yaml"
if grep -Fq "hook-succeeded" "$CHART_DIR/templates/migration-job.yaml"; then
  echo "successful migration evidence must remain available until its TTL expires" >&2
  exit 1
fi
grep -Fq 'ENTRYPOINT ["/scripts/run-k3s-migrations.sh"]' \
  "$ROOT_DIR/deploy/k3s/migrator.Dockerfile"
grep -Fq 'FROM postgres:18-alpine@sha256:9a8afca54e7861fd90fab5fdf4c42477a6b1cb7d293595148e674e0a3181de15' \
  "$ROOT_DIR/deploy/k3s/migrator.Dockerfile"
grep -Fq 'apk upgrade --no-cache' "$ROOT_DIR/deploy/k3s/migrator.Dockerfile"
grep -Fq 'rm -f /usr/local/bin/gosu' "$ROOT_DIR/deploy/k3s/migrator.Dockerfile"
grep -Fq "check-k3s-runtime-secret.sh" "$ROOT_DIR/scripts/deploy-k3s-release.sh"
grep -Fq "servicemonitors.monitoring.coreos.com" \
  "$ROOT_DIR/scripts/deploy-k3s-release.sh"
grep -Fq "K3S_REQUIRE_DISTINCT_ZONES" \
  "$ROOT_DIR/scripts/accept-k3s-release.sh"
for migration_step in \
  run-migrations.sh \
  provision-service-db-users.sh \
  extract-logical-databases.sh \
  run-logical-database-migrations.sh \
  enable-postgres-performance-observability.sh; do
  grep -Fq "$migration_step" "$ROOT_DIR/scripts/run-k3s-migrations.sh"
done

jq -e '
  [.images[] | select(.service == "migrator")] | length == 1
' "$ROOT_DIR/deploy/production/image-matrix.json" >/dev/null

grep -Fq "instances: 3" "$DATA_RENDERED_FILE"
grep -Fq "kind: Pooler" "$DATA_RENDERED_FILE"
grep -Fq "name: warptalk-postgres-pooler-rw" "$DATA_RENDERED_FILE"
grep -Fq "poolMode: transaction" "$DATA_RENDERED_FILE"
grep -Fq 'max_client_conn: "1000"' "$DATA_RENDERED_FILE"
grep -Fq "app.kubernetes.io/name: warptalk-postgres-pooler" "$DATA_RENDERED_FILE"
# The pooler PDB allows one voluntary eviction at a time. It was `minAvailable: 2`, which over the
# production single pooler would forbid every drain; maxUnavailable means the same thing at three
# poolers and stays drainable at any count (and it is not rendered at all below two).
grep -Fq "maxUnavailable: 1" "$DATA_RENDERED_FILE"
grep -Fq "apiVersion: barmancloud.cnpg.io/v1" "$DATA_RENDERED_FILE"
grep -Fq "kind: ObjectStore" "$DATA_RENDERED_FILE"
grep -Fq "name: barman-cloud.cloudnative-pg.io" "$DATA_RENDERED_FILE"
grep -Fq "barmanObjectName: warptalk-postgres-backup" "$DATA_RENDERED_FILE"
grep -Fq "method: plugin" "$DATA_RENDERED_FILE"
grep -Fq "retentionPolicy: 30d" "$DATA_RENDERED_FILE"
grep -Fq "namespace: warptalk" "$DATA_RENDERED_FILE"
grep -Fq "name: warptalk-qdrant-auth" "$DATA_RENDERED_FILE"
grep -Fq "warptalk-data-default-deny-ingress" "$DATA_RENDERED_FILE"
grep -Fq "kubernetes.io/metadata.name: keda" "$DATA_RENDERED_FILE"
grep -Fq "warptalk-rabbitmq-allow-cluster-and-clients" "$DATA_RENDERED_FILE"
if grep -Fq "barmanObjectStore:" "$DATA_RENDERED_FILE"; then
  echo "deprecated CloudNativePG in-tree Barman backup is not allowed" >&2
  exit 1
fi
grep -Fq "replicas: 3" "$DATA_RENDERED_FILE"
grep -Fq "sentinel:" "$ROOT_DIR/deploy/k3s/data/redis-values.yaml"
# One Qdrant node: Raft needs three peers, and three peers on the single Data VM would triple the
# index for no protection against losing the VM. Recovery is the nightly S3 snapshot instead, so
# the snapshot wiring is asserted in its place.
grep -Fq "replicaCount: 1" "$ROOT_DIR/deploy/k3s/data/qdrant-values.yaml"
grep -Fq "snapshots_storage: s3" "$ROOT_DIR/deploy/k3s/data/qdrant-snapshots-s3.yaml"
# Three Redis nodes: one sentinel per node with quorum 2 cannot fail over with two.
grep -Fq "replicaCount: 2" "$ROOT_DIR/deploy/k3s/data/redis-values.yaml"
grep -Fq "quorum: 2" "$ROOT_DIR/deploy/k3s/data/redis-values.yaml"
grep -Fq "maxmemory-policy noeviction" "$ROOT_DIR/deploy/k3s/data/redis-values.yaml"
grep -Fq "warptalk-qdrant-auth" "$ROOT_DIR/deploy/k3s/data/qdrant-values.yaml"
grep -Fq "recovery window: 5 minutes" "$ROOT_DIR/deploy/k3s/FAILOVER-RUNBOOK.md"

# shellcheck disable=SC1090
source "$ROOT_DIR/deploy/k3s/addons.lock.env"
grep -Fq "$OTEL_COLLECTOR_IMAGE_DIGEST" "$CHART_DIR/values.yaml"
grep -Fq "$REDIS_IMAGE_DIGEST" "$ROOT_DIR/deploy/k3s/data/redis-values.yaml"
grep -Fq "$REDIS_SENTINEL_IMAGE_DIGEST" "$ROOT_DIR/deploy/k3s/data/redis-values.yaml"
grep -Fq "$REDIS_EXPORTER_IMAGE_DIGEST" "$ROOT_DIR/deploy/k3s/data/redis-values.yaml"
grep -Fq "$QDRANT_TEST_IMAGE_DIGEST" "$ROOT_DIR/deploy/k3s/data/qdrant-values.yaml"
grep -Fq 'QDRANT_IMAGE_DIGEST' "$ROOT_DIR/scripts/pin-qdrant-images.sh"

# ---------------------------------------------------------------------------------------------
# Production values: the release job renders the chart with deploy/k3s/k8s-app-values.yaml plus
# image references from the signed manifest, so assert on exactly that.
# ---------------------------------------------------------------------------------------------
PROD_RENDERED="$(mktemp "${TMPDIR:-/tmp}/warptalk-k3s-prod.XXXXXX")"
PROD_DATA_RENDERED="$(mktemp "${TMPDIR:-/tmp}/warptalk-k3s-prod-data.XXXXXX")"
PROD_IMAGES="$(mktemp "${TMPDIR:-/tmp}/warptalk-k3s-prod-images.XXXXXX")"
PROD_MIGRATION_RENDERED="$(mktemp "${TMPDIR:-/tmp}/warptalk-k3s-prod-migration.XXXXXX")"
trap 'rm -f "$deployment_documents" "$PROD_RENDERED" "$PROD_DATA_RENDERED" "$PROD_IMAGES" "$PROD_MIGRATION_RENDERED"' EXIT

# Nothing release-specific may live in a values file: no digests, no image refs, no release id.
for values_file in "$ROOT_DIR/deploy/k3s/k8s-app-values.yaml" "$ROOT_DIR/deploy/k3s/k8s-data-values.yaml"; do
  if grep -Eq 'imageRef:|@sha256:|releaseId:|prod-k8s-v[0-9]' "$values_file"; then
    echo "$values_file hard-codes an image reference, digest or release id; the release job passes them" >&2
    exit 1
  fi
done
# The account-scoped object-store endpoint is a runtime value, not a committed one.
if grep -Fq 'r2.cloudflarestorage.com' "$ROOT_DIR/deploy/k3s/k8s-data-values.yaml"; then
  echo "the backup endpoint belongs in BACKUP_S3_ENDPOINT_URL, not in git" >&2
  exit 1
fi

jq '{
  global: {releaseId: "contract01"},
  migrator: {imageRef: ("ghcr.io/warptalk/migrator:contract01@sha256:" + ("1" * 64))},
  workloads: ([.images[] | select(.k3s != false and .service != "migrator") |
    {key: .service, value: {imageRef: ("ghcr.io/warptalk/" + .name + ":contract01@sha256:" + ("1" * 64))}}
  ] | from_entries)
}' "$ROOT_DIR/deploy/production/image-matrix.json" >"$PROD_IMAGES"
"$HELM" template warptalk "$CHART_DIR" --namespace warptalk \
  -f "$ROOT_DIR/deploy/k3s/k8s-app-values.yaml" -f "$PROD_IMAGES" >"$PROD_RENDERED"
# The migration gate exactly as scripts/deploy-k3s-release.sh renders it for run_migration_gate.
"$HELM" template warptalk "$CHART_DIR" --namespace warptalk \
  -f "$ROOT_DIR/deploy/k3s/k8s-app-values.yaml" -f "$PROD_IMAGES" \
  --set migrations.mode=job --show-only templates/migration-job.yaml >"$PROD_MIGRATION_RENDERED"
# As the release job renders it with GitHub-sourced secrets (which enables the Qdrant snapshots).
"$HELM" template warptalk-data "$DATA_CHART_DIR" --namespace warptalk-data \
  -f "$ROOT_DIR/deploy/k3s/k8s-data-values.yaml" \
  --set qdrantSnapshots.enabled=true \
  --set-string postgres.backup.endpointURL=https://object-store.warptalk.invalid >"$PROD_DATA_RENDERED"
docker run --rm -i ghcr.io/yannh/kubeconform:v0.7.0-alpine \
  -strict -summary -ignore-missing-schemas <"$PROD_RENDERED"
docker run --rm -i ghcr.io/yannh/kubeconform:v0.7.0-alpine \
  -strict -summary -ignore-missing-schemas <"$PROD_DATA_RENDERED"
docker run --rm -i ghcr.io/yannh/kubeconform:v0.7.0-alpine \
  -strict -summary -ignore-missing-schemas <"$PROD_MIGRATION_RENDERED"

prod_fail() {
  echo "K3s production contract: $*" >&2
  exit 1
}

# One secret source: GitHub `production`, materialized by the release job.
if grep -Fq "kind: ExternalSecret" "$PROD_RENDERED" "$PROD_DATA_RENDERED"; then
  prod_fail "production must not render ExternalSecrets; runtime secrets come from GitHub production"
fi

python3 - "$PROD_RENDERED" "$PROD_DATA_RENDERED" "$ROOT_DIR" "$PROD_MIGRATION_RENDERED" <<'PY'
import re
import sys

prod_path, data_path, root, migration_path = sys.argv[1:5]


def documents(path):
    text = open(path, encoding="utf-8").read()
    return [d for d in re.split(r"(?m)^---\s*$", text) if d.strip()]


def kind_name(doc):
    kind = re.search(r"(?m)^kind:\s*(\S+)", doc)
    name = re.search(r"(?m)^metadata:\n(?:  .*\n)*?  name:\s*(\S+)", doc)
    return (kind.group(1) if kind else None, name.group(1) if name else None)


def fail(message):
    sys.exit(f"K3s production contract: {message}")


def cpu(value):
    value = value.strip('"')
    return float(value[:-1]) if value.endswith("m") else float(value) * 1000


def mem(value):
    value = value.strip('"')
    units = {"Ki": 1 / 1024, "Mi": 1, "Gi": 1024}
    for suffix, factor in units.items():
        if value.endswith(suffix):
            return float(value[: -len(suffix)]) * factor
    return float(value) / (1024 * 1024)


docs = documents(prod_path)
by_kind = {}
for doc in docs:
    kind, name = kind_name(doc)
    by_kind.setdefault(kind, {})[name] = doc

# 2. ServiceAccounts and the migration gate. warptalk is a release resource. The migrations are
# NOT in the release: scripts/deploy-k3s-release.sh runs them as a plain Job before `helm upgrade`
# and stops the release with nothing rolled if it fails. A migration hook inside the upgrade is
# how new images ended up running on an unmigrated schema (24 Sep).
sas = by_kind.get("ServiceAccount", {})
if "warptalk" not in sas or "helm.sh/hook" in sas["warptalk"]:
    fail("ServiceAccount warptalk must exist and must not be a Helm hook")
if "warptalk-migrator" in sas or any(n.startswith("warptalk-migrations-") for n in by_kind.get("Job", {})):
    fail("production must render no migration hook; migrations run as the gate before the upgrade (migrations.mode: external)")
migration_docs = {kind_name(d): d for d in documents(migration_path)}
gate_job = next((d for (k, n), d in migration_docs.items() if k == "Job" and n.startswith("warptalk-migrations-")), "")
if ("ServiceAccount", "warptalk-migrator") not in migration_docs or not gate_job:
    fail("the migration gate must render the warptalk-migrator ServiceAccount and a warptalk-migrations-<release> Job")
if any("helm.sh/hook" in d for d in migration_docs.values()):
    fail("the migration gate objects must be plain objects, not Helm hooks")
if "serviceAccountName: warptalk-migrator" not in gate_job:
    fail("the migration Job must run as warptalk-migrator")
if "name: warptalk-migrations-contract01" not in gate_job:
    fail("the migration Job must be named after the release id, so each release keeps its own evidence")
if "optional: true" not in gate_job or "name: PGHOST" not in gate_job:
    fail("the gate runs before the release's ConfigMap exists or changes: PGHOST must be explicit and the ConfigMap optional")
if "activeDeadlineSeconds:" not in gate_job:
    fail("the migration Job needs a deadline, or a hung migration holds the release forever")

# 3. Stickiness on the gateway Service only, with a cookie name of its own; none on the Ingress.
sticky = [n for n, d in by_kind.get("Service", {}).items() if "service.sticky.cookie:" in d]
if sticky != ["gateway"]:
    fail(f"exactly the gateway Service must be sticky, found {sticky}")
if "warptalk_gateway_affinity" not in by_kind["Service"]["gateway"]:
    fail("the gateway sticky cookie must have its own name")
ingress = by_kind.get("Ingress", {}).get("warptalk", "")
if "sticky" in ingress:
    fail("sticky annotations on the Ingress are ignored by Traefik; they belong on the Service")

# 3. Backplanes on every service that hosts a SignalR hub.
deployments = by_kind.get("Deployment", {})
for service in ("gateway", "meeting-service", "assistant-service", "billing-service"):
    if "name: SignalR__Redis" not in deployments.get(service, ""):
        fail(f"{service} hosts a SignalR hub and needs SignalR__Redis")

# 4. The middleware reference names the namespace the chart creates the Middleware in.
if "router.middlewares: warptalk-warptalk-security-headers@kubernetescrd" not in ingress:
    fail("the Ingress must reference warptalk-warptalk-security-headers@kubernetescrd")
middleware = by_kind.get("Middleware", {}).get("warptalk-security-headers", "")
for header in ("contentSecurityPolicy:", "stsSeconds: 31536000", "customFrameOptionsValue: DENY"):
    if header not in middleware:
        fail(f"the security-headers Middleware is missing {header}")

# 13. Hosts exactly as compose/Caddy: app -> frontend, api -> gateway.
rules = re.findall(r'- host: "([^"]+)"\n\s+http:\n\s+paths:\n((?:\s+.*\n?)*?)(?=\s+- host:|\Z)', ingress)
hosts = {host: body for host, body in rules}
if set(hosts) != {"app.warptalk.io.vn", "api.warptalk.io.vn"}:
    fail(f"the Ingress must serve app. and api. as compose does, got {sorted(hosts)}")
if "name: gateway" in hosts["app.warptalk.io.vn"] or "name: frontend" in hosts["api.warptalk.io.vn"]:
    fail("app. must route to the frontend only and api. to the gateway only, as in the Caddyfile")

config = by_kind.get("ConfigMap", {}).get("warptalk-runtime", "")
for needle, message in (
    ("monitoring-kube-prometheus-prometheus.monitoring.svc", "Monitoring__PrometheusUrl must point at the monitoring namespace"),
    ("monitoring-kube-prometheus-alertmanager.monitoring.svc", "Monitoring__AlertmanagerUrl must point at Alertmanager, the only place silences exist"),
    ('Monitoring__GrafanaEmbedPath: "/grafana"', "Monitoring__GrafanaEmbedPath must be the same-origin /grafana path the Grafana Ingress serves"),
    ('RateLimits__LoginPermitLimit: "5"', "login rate limit must be back at the compose value of 5"),
    ('ForwardedHeaders__KnownNetworks__0: "192.168.0.0/16"', "the gateway must trust X-Forwarded-For from the live Calico pod CIDR"),
    ('AllowedOrigins__0: "https://app.warptalk.io.vn"', "AllowedOrigins must hold the app origin"),
):
    if needle not in config:
        fail(message)

# 5/10/11/15. Per-workload rules.
hpas = by_kind.get("HorizontalPodAutoscaler", {})
scaled = by_kind.get("ScaledObject", {})
pdbs = by_kind.get("PodDisruptionBudget", {})
total_cpu = 0.0
total_mem = 0.0
largest_pod_mem = 0.0
minimums = {}


# Scrape targets and the log/trace pipeline: nothing user-facing waits on them, so the drain and
# spread rules below do not apply (the rollout shape still does).
INTERNAL_ONLY = {"billing-cost-exporter", "livekit-cost-exporter", "workspace-storage-exporter",
                 "warptalk-otel-collector", "seq"}


def int_field(doc, field):
    match = re.search(rf"(?m)^\s+{field}: (\d+)", doc)
    return int(match.group(1)) if match else None


for name, doc in deployments.items():
    if "node.warptalk.io/role: app" not in doc:
        fail(f"{name} is not pinned to the App node")
    uids = set(re.findall(r"runAsUser: (\d+)", doc))
    if name != "seq" and len(uids) != 1:
        fail(f"{name} runs its pod and container as different users {sorted(uids)}")
    autoscaled = name in hpas or f"{name}-queue-lag" in scaled
    replicas = re.search(r"(?m)^  replicas: (\d+)", doc)
    if not autoscaled and not replicas:
        fail(f"{name} has no autoscaler and no rendered replica count")
    if autoscaled and replicas:
        fail(f"{name} is autoscaled but also renders a static replica count")
    if name in hpas:
        minimum = int(re.search(r"minReplicas: (\d+)", hpas[name]).group(1))
    elif f"{name}-queue-lag" in scaled:
        minimum = int(re.search(r"minReplicaCount: (\d+)", scaled[f"{name}-queue-lag"]).group(1))
    else:
        minimum = int(replicas.group(1))
    minimums[name] = minimum
    if minimum < 2 and name in pdbs:
        fail(f"{name} runs one pod and must not have a PDB")
    for request in re.findall(r"requests:\n\s+cpu: (\S+)\n\s+memory: (\S+)", doc):
        total_cpu += cpu(request[0]) * minimum
        total_mem += mem(request[1]) * minimum
        largest_pod_mem = max(largest_pod_mem, mem(request[1]))

    # Zero-downtime rollout. Every RollingUpdate surges: the new pod must be Ready before an old
    # one goes. (#216 set surge 0 / unavailable 1 in the production values because the App node
    # was full; deploy-k3s-release.sh now decides that per release from measured headroom.)
    if "type: Recreate" not in doc:
        if int_field(doc, "maxSurge") != 1 or int_field(doc, "maxUnavailable") != 0:
            fail(f"{name} must roll out with maxSurge 1 / maxUnavailable 0")
    # Exec probes (the Python workers expose no port): a new interpreter per run, so a 5s
    # timeout killed healthy workers on a busy node. Pin a realistic timeout and a startup
    # window of at least 2 minutes.
    for probe in ("startupProbe", "livenessProbe", "readinessProbe"):
        block = re.search(rf"(?m)^(\s+){probe}:\n((?:\1\s+.*\n)+)", doc)
        if not block or "exec:" not in block.group(2):
            continue
        timeout = re.search(r"timeoutSeconds: (\d+)", block.group(2))
        if not timeout or int(timeout.group(1)) < 15:
            fail(f"{name} {probe} is an exec probe (python start-up included) and needs timeoutSeconds >= 15")
        if probe == "startupProbe":
            period = int(re.search(r"periodSeconds: (\d+)", block.group(2)).group(1))
            threshold = int(re.search(r"failureThreshold: (\d+)", block.group(2)).group(1))
            if period * threshold < 120:
                fail(f"{name} startup probe allows {period * threshold}s; a worker needs at least 2 minutes on a busy node")
    if "containerPort:" in doc and "exec:\n" in doc.split("readinessProbe:", 1)[-1][:120]:
        fail(f"{name} exposes a port; probe it over HTTP or TCP, not exec")
    if name in INTERNAL_ONLY:
        continue
    # Drain: preStop sleep so Traefik and kube-proxy stop routing before SIGTERM, and a grace
    # period that covers the sleep plus the process's own shutdown.
    sleep = re.search(r"preStop:\n\s+sleep:\n\s+seconds: (\d+)", doc)
    grace = int_field(doc, "terminationGracePeriodSeconds")
    if not sleep or int(sleep.group(1)) < 5:
        fail(f"{name} needs a preStop sleep (>= 5s) so in-flight requests drain")
    if grace is None or grace < int(sleep.group(1)) + 30:
        fail(f"{name} terminationGracePeriodSeconds must cover the preStop sleep plus 30s of shutdown")
    # Readiness gates traffic: anything with a Service port must have a readiness probe, and a
    # startup probe so liveness cannot kill a slow start.
    if "containerPort:" in doc and ("readinessProbe:" not in doc or "startupProbe:" not in doc):
        fail(f"{name} serves traffic and needs readiness and startup probes")
    if "readinessProbe:" in doc and "timeoutSeconds: 1\n" in doc.split("readinessProbe:", 1)[1][:300]:
        fail(f"{name} readiness probe timeout must be above the 1s default")
    # Spread replicas across hosts where there is capacity - softly, so one App node still works.
    if re.search(r"topologyKey: kubernetes.io/hostname\n\s+whenUnsatisfiable: ScheduleAnyway", doc) is None:
        fail(f"{name} must spread over kubernetes.io/hostname with whenUnsatisfiable: ScheduleAnyway")
    if "whenUnsatisfiable: DoNotSchedule" in doc or "requiredDuringScheduling" in doc:
        fail(f"{name} must not hard-require spreading; one App node has to stay schedulable")

# The data tier outranks the application tier, never the reverse: no application pod carries a
# priority class (so it stays at 0 and can preempt nothing that has one).
if "priorityClassName" in open(prod_path, encoding="utf-8").read():
    fail("the application chart sets a priorityClassName; application pods must never outrank (or preempt) data pods")

for name, doc in pdbs.items():
    if "minAvailable" in doc:
        fail(f"PDB {name} uses minAvailable; use maxUnavailable")
    if "maxUnavailable: 1" not in doc:
        fail(f"PDB {name} must allow exactly one voluntary disruption (maxUnavailable: 1)")
for singleton in ("suggestion-worker", "metrics-exporter"):
    if "type: Recreate" not in deployments[singleton] or "replicas: 1" not in deployments[singleton]:
        fail(f"{singleton} is a singleton: one replica and a Recreate rollout")

# Every user-facing service (behind the Ingress or the gateway) keeps two pods and a PDB, so a
# rollout, a drain or one crashed pod never takes it away.
USER_FACING = ("frontend", "gateway", "auth-service", "translation-room-service", "transcript-service",
               "notification-service", "meeting-service", "workspace-service", "billing-service",
               "assistant-service")
for name in USER_FACING:
    if minimums.get(name, 0) < 2:
        fail(f"{name} is user-facing and must keep at least 2 replicas (found {minimums.get(name)})")
    if name not in pdbs:
        fail(f"{name} is user-facing and needs a PodDisruptionBudget")

# 5. Capacity: the WHOLE App node, not just this chart. Allocatable is the live value (kubelet
# reports 16273348Ki = 15892Mi; the cluster was built without kubelet reservations). Everything
# else that requests memory there is listed below, measured on 2026-09-24; when a data pod moves
# to the Data node (deploy/k3s/DATA-PLACEMENT-RUNBOOK.md) take it out of APP_NODE_DATA_PODS.
#
# Target: at minimum replicas the node keeps >= 25% of its memory unrequested, and that free
# space holds one surge pod of the largest workload PLUS redis-node-0 (so Redis can always be
# rescheduled, and a release can always surge).
APP_ALLOCATABLE_MI = 15892
ADDONS_ON_APP_NODE_MI = {  # requests of the add-ons that run on the App node (live, 2026-09-24)
    "keda (3 pods)": 300,
    "metrics-server": 200,
    "alertmanager": 200,
    "rabbitmq-cluster-operator": 500,
}
data_values = open(f"{root}/deploy/k3s/k8s-data-values.yaml", encoding="utf-8").read()
redis_values_text = open(f"{root}/deploy/k3s/data/redis-values.yaml", encoding="utf-8").read()
postgres_request = mem(re.search(r"(?s)postgres:.*?requests: \{cpu: \S+, memory: (\S+)\}", data_values).group(1))
rabbit_request = mem(re.search(r"(?s)rabbitmq:.*?requests: \{cpu: \S+, memory: (\S+)\}", data_values).group(1))
redis_pod = sum(mem(m) for m in re.findall(r"requests: \{cpu: \S+, memory: (\S+)\}", redis_values_text))
APP_NODE_DATA_PODS = {  # data pods whose local-path volumes are still on the App node
    "warptalk-postgres-1": postgres_request,
    "warptalk-postgres-2": postgres_request,
    "warptalk-redis-node-0": redis_pod,
    "warptalk-rabbitmq-server-0": rabbit_request,
}
app_node_mem = total_mem + sum(ADDONS_ON_APP_NODE_MI.values()) + sum(APP_NODE_DATA_PODS.values())
free_mem = APP_ALLOCATABLE_MI - app_node_mem
if free_mem < 0.25 * APP_ALLOCATABLE_MI:
    fail(f"App-node memory requests at minimum replicas are {app_node_mem:.0f}Mi of {APP_ALLOCATABLE_MI}Mi "
         f"({app_node_mem / APP_ALLOCATABLE_MI:.0%}); at least 25% must stay free")
if free_mem < largest_pod_mem + redis_pod:
    fail(f"App-node free memory {free_mem:.0f}Mi cannot hold one surge pod of the largest workload "
         f"({largest_pod_mem:.0f}Mi) plus redis-node-0 ({redis_pod:.0f}Mi)")
if total_cpu > 5000:
    fail(f"WarpTalk CPU requests at minimum replicas are {total_cpu:.0f}m; budget is 5000m")
print(f"K3s production contract: WarpTalk requests at minimum replicas {total_cpu:.0f}m CPU / {total_mem:.0f}Mi; "
      f"App node {app_node_mem:.0f}Mi of {APP_ALLOCATABLE_MI}Mi requested ({app_node_mem / APP_ALLOCATABLE_MI:.1%}), "
      f"{free_mem:.0f}Mi free >= largest pod {largest_pod_mem:.0f}Mi + redis-node-0 {redis_pod:.0f}Mi")

# Production values must not pin the rollout shape: the deploy script decides it per release.
if re.search(r"(?m)^rollout:", open(f"{root}/deploy/k3s/k8s-app-values.yaml", encoding="utf-8").read()):
    fail("k8s-app-values.yaml must not override rollout.*; deploy-k3s-release.sh chooses surge or in-place per release")

# 5. Collector: container memory limit ~20% above the memory_limiter.
collector = deployments["warptalk-otel-collector"]
limit = mem(re.search(r"limits:\n\s+cpu: \S+\n\s+memory: (\S+)", collector).group(1))
limiter = float(re.search(r"limit_mib: (\d+)", open(f"{root}/deploy/k3s/chart/files/otel-collector.yaml").read()).group(1))
if not limit >= limiter * 1.2:
    fail(f"collector memory limit {limit:.0f}Mi must be >= 1.2 x memory_limiter {limiter:.0f}MiB")
if "debug" in re.search(r"(?s)service:.*", open(f"{root}/deploy/k3s/chart/files/otel-collector.yaml").read()).group(0):
    fail("collector pipelines must export to Seq, not to the debug exporter")

# 7. Alert rules: the Kubernetes rules are the compose rules plus Kubernetes extras.
compose_rules = open(f"{root}/observability/alerts/warptalk.rules.yml", encoding="utf-8").read()
chart_rules = open(f"{root}/deploy/k3s/chart/files/warptalk.rules.yml", encoding="utf-8").read()
if not chart_rules.startswith(compose_rules.rstrip("\n")):
    fail("deploy/k3s/chart/files/warptalk.rules.yml must begin with observability/alerts/warptalk.rules.yml verbatim")
for alert in ("WarpTalkServiceHighErrorRatio", "WarpTalkAiStreamLag", "WarpTalkDeadLetterPresent",
              "WarpTalkStreamGroupUnread", "WarpTalkStreamGroupCoverageLow", "WarpTalkRedisMaxmemoryUnset"):
    if f"alert: {alert}" not in chart_rules:
        fail(f"missing alert {alert}")

# 6. Data layer on one VM.
data = open(data_path, encoding="utf-8").read()
for needle, message in (
    ("instances: 2", "Postgres runs two instances"),
    ("dataDurability: preferred", "two instances need preferred durability so a lost standby does not stop writes"),
    ("pg_stat_statements.max", "pg_stat_statements must be preloaded through CloudNativePG"),
    ("values: [data]", "data pods must prefer the Data node"),
    ("effect: NoSchedule", "data pods must tolerate the Data node taint"),
    ("name: warptalk-qdrant-snapshot", "Qdrant needs its nightly snapshot"),
):
    if needle not in data:
        fail(message)
if "minSyncReplicas" in data:
    fail("minSyncReplicas conflicts with the synchronous stanza")
# The data tier's PriorityClass: preempts app pods, and the app chart carries none (checked above).
data_docs = {kind_name(d): d for d in documents(data_path)}
priority = data_docs.get(("PriorityClass", "warptalk-data-critical"), "")
if not priority or "preemptionPolicy: PreemptLowerPriority" not in priority or "globalDefault: false" not in priority:
    fail("the data chart must ship the warptalk-data-critical PriorityClass (PreemptLowerPriority, not global default)")
if int(re.search(r"(?m)^value: (\d+)", priority).group(1)) <= 0:
    fail("warptalk-data-critical must rank above the application tier (priority 0)")
cluster = data_docs.get(("Cluster", "warptalk-postgres"), "")
if "priorityClassName: warptalk-data-critical" not in cluster:
    fail("Postgres must run under warptalk-data-critical")
if "primaryUpdateMethod: switchover" not in cluster:
    fail("a Postgres rolling update must switch over, never restart the primary in place")
if "containers: []" not in data:
    # Not dead: the RabbitmqCluster CRD requires `containers` whenever the override pod template
    # has a spec, and the live object carries `containers: []`. Dropping it made Helm's patch
    # remove a required field and failed the first k8s release (run 35946575671).
    fail("the RabbitMQ override pod template must keep `containers: []` (required by the CRD)")

# 6. Storage. The live claims were created at these sizes and a PVC cannot shrink (CloudNativePG
# rejects it, and StatefulSet volumeClaimTemplates are immutable), so the values must never go
# below them. Together they exceed the 35 GB Data volume on paper; local-path does not enforce
# sizes and actual use is under 1 GiB (README "Capacity plan"), watched by
# WarpTalkPersistentVolumeFilling.
def size(text, pattern):
    return mem(re.search(pattern, text).group(1)) / 1024

values = open(f"{root}/deploy/k3s/k8s-data-values.yaml", encoding="utf-8").read()
redis_values = open(f"{root}/deploy/k3s/data/redis-values.yaml", encoding="utf-8").read()
qdrant_values = open(f"{root}/deploy/k3s/data/qdrant-values.yaml", encoding="utf-8").read()
postgres = size(values, r"storageSize: (\S+)") * int(re.search(r"(?m)^  instances: (\d+)", values).group(1))
rabbit = size(values, r"(?s)rabbitmq:.*?storageSize: (\S+)")
redis = size(redis_values, r"(?s)persistence:.*?size: (\S+)") * int(re.search(r"replicaCount: (\d+)", redis_values).group(1))
qdrant = size(qdrant_values, r"(?s)persistence:.*?size: (\S+)")
live = {"postgres": 25, "rabbitmq": 5, "redis": 20, "qdrant": 50}
per_claim = {
    "postgres": size(values, r"storageSize: (\S+)"),
    "rabbitmq": rabbit,
    "redis": size(redis_values, r"(?s)persistence:.*?size: (\S+)"),
    "qdrant": qdrant,
}
for name, minimum in live.items():
    if per_claim[name] < minimum:
        fail(f"{name} claim {per_claim[name]:.0f} GiB is below the live {minimum} GiB; a PVC cannot shrink")
total = postgres + rabbit + redis + qdrant
print(f"K3s production contract: data claims {total:.0f} GiB nominal (none below the live sizes)")
PY

# The embedded Grafana and the control-plane scrape fix (deploy/k3s/monitoring-values.yaml).
python3 - "$ROOT_DIR/deploy/k3s/monitoring-values.yaml" <<'PY'
import sys
import yaml

values = yaml.safe_load(open(sys.argv[1]))

def fail(message):
    print(f"K3s monitoring contract: {message}", file=sys.stderr)
    sys.exit(1)

# kubeadm binds these to localhost; scraping them only produced down targets and false alerts.
for component in ("kubeEtcd", "kubeScheduler", "kubeControllerManager", "kubeProxy"):
    if values.get(component, {}).get("enabled", True) is not False:
        fail(f"{component} must stay disabled until its metrics bind beyond 127.0.0.1")

grafana = values["grafana"]
ini = grafana["grafana.ini"]
if ini.get("auth.anonymous", {}).get("enabled") is not False:
    fail("Grafana must never allow anonymous access")
proxy = ini.get("auth.proxy", {})
if not proxy.get("enabled") or proxy.get("header_name") != "X-WEBAUTH-USER":
    fail("Grafana must authenticate through the gateway ForwardAuth header")
if proxy.get("whitelist") != "192.168.0.0/16":
    fail("auth.proxy must trust the header only from the Calico pod CIDR")
if ini.get("users", {}).get("auto_assign_org_role") != "Viewer":
    fail("proxy-authenticated admins must land as Viewer")
if ini["security"].get("allow_embedding") is not True or ini["security"].get("cookie_samesite") != "lax":
    fail("the admin page embeds Grafana same-origin: allow_embedding true, SameSite=Lax")
if not ini["server"]["root_url"].endswith("/grafana/") or ini["server"].get("serve_from_sub_path") is not True:
    fail("Grafana must be served from the /grafana sub-path")
ingress = grafana["ingress"]
if ingress.get("path") != "/grafana" or "monitoring-grafana-admin-auth@kubernetescrd" not in ingress["annotations"].get("traefik.ingress.kubernetes.io/router.middlewares", ""):
    fail("the Grafana Ingress must serve /grafana behind the admin ForwardAuth middleware")
objects = {o["metadata"]["name"]: o for o in grafana.get("extraObjects", [])}
auth = objects.get("grafana-admin-auth", {}).get("spec", {}).get("forwardAuth", {})
if not auth.get("address", "").endswith("/internal/grafana/auth") or auth.get("authResponseHeaders") != ["X-WEBAUTH-USER"]:
    fail("the ForwardAuth must ask the gateway and copy back only X-WEBAUTH-USER")
if "grafana-ingress" not in objects:
    fail("a NetworkPolicy must keep everything but Traefik and monitoring away from Grafana")
if "frame-ancestors 'self'" not in objects.get("grafana-embed-headers", {}).get("spec", {}).get("headers", {}).get("contentSecurityPolicy", ""):
    fail("Grafana must be frameable by its own origin only")
print("K3s monitoring contract: Grafana embed and control-plane scrape settings OK")
PY

"$ROOT_DIR/scripts/check-k3s-compose-url-parity.sh"

echo "K3s deployment contract: PASS"
