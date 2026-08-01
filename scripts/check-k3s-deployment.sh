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
  "$CHART_DIR/templates/certificate.yaml"
  "$CHART_DIR/templates/security-headers.yaml"
  "$CHART_DIR/templates/telemetry.yaml"
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
  "$ROOT_DIR/scripts/pin-qdrant-images.sh"
  "$ROOT_DIR/deploy/k3s/migrator.Dockerfile"
  "$ROOT_DIR/scripts/run-k3s-migrations.sh"
)

for file in "${required_files[@]}"; do
  [[ -f "$file" ]] || {
    echo "missing K3s artifact: $file" >&2
    exit 1
  }
done

docker run --rm \
  -v "$CHART_DIR:/chart:ro" \
  alpine/helm:3.18.6 \
  template warptalk /chart --namespace warptalk >"$RENDERED_FILE"

docker run --rm \
  -v "$DATA_CHART_DIR:/chart:ro" \
  alpine/helm:3.18.6 \
  template warptalk-data /chart --namespace warptalk-data >"$DATA_RENDERED_FILE"

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
grep -Fq "minAvailable: 2" "$DATA_RENDERED_FILE"
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
grep -Fq "replicaCount: 3" "$ROOT_DIR/deploy/k3s/data/qdrant-values.yaml"
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

echo "K3s deployment contract: PASS"
