#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
deploy_root="$repo_root/deploy/production"
env_file="$deploy_root/.env.example"
app_compose="$deploy_root/app.compose.yml"
data_compose="$deploy_root/data.compose.yml"
infra_compose="$deploy_root/infra.compose.yml"

fail() {
  echo "three-host Compose contract: FAIL - $*" >&2
  exit 1
}

[[ -f "$infra_compose" ]] || fail "infra.compose.yml is missing"
rg -q '^INFRA_PRIVATE_IP=10\.20\.0\.30$' "$env_file" ||
  fail "production environment does not define INFRA_PRIVATE_IP"

app_json="$(docker compose --env-file "$env_file" -f "$app_compose" config --format json)"
data_json="$(docker compose --env-file "$env_file" -f "$data_compose" config --format json)"
infra_json="$(docker compose --env-file "$env_file" -f "$infra_compose" config --format json)"

printf '%s\n' "$data_json" | jq -e '
  (.services | has("postgres") and has("pgbouncer") and has("minio") and has("qdrant"))
  and ([.services | keys[] | select(. == "redis" or . == "rabbitmq" or . == "prometheus")] | length == 0)
' >/dev/null || fail "Data host service boundary is invalid"

printf '%s\n' "$infra_json" | jq -e '
  (.services | has("redis") and has("rabbitmq") and has("otel-collector") and has("prometheus"))
  and ([.services | to_entries[] | (.value.ports // [])[] | select(.host_ip != "10.20.0.30")] | length == 0)
' >/dev/null || fail "Infra host service boundary or port binding is invalid"

printf '%s\n' "$app_json" | jq -e '
  [
    .services["auth-service"].environment.Redis__ConnectionString,
    .services["workspace-service"].environment.RabbitMQ__Host,
    .services["auth-service"].environment.OTEL_EXPORTER_OTLP_ENDPOINT
  ]
  | all(contains("10.20.0.30"))
' >/dev/null || fail "App dependencies do not route through INFRA_PRIVATE_IP"

rg -q "data-host:9000" "$repo_root/observability/prometheus.yml" ||
  fail "Prometheus does not scrape remote Data host MinIO"
rg -q "data-host:6333" "$repo_root/observability/prometheus.yml" ||
  fail "Prometheus does not scrape remote Data host Qdrant"

echo "three-host Compose contract: PASS"
