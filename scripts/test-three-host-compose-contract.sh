#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
deploy_root="$repo_root/deploy/production"
env_file="$deploy_root/.env.example"
app_compose="$deploy_root/app.compose.yml"
data_compose="$deploy_root/data.compose.yml"
infra_compose="$deploy_root/infra.compose.yml"
alert_renderer="$repo_root/scripts/render-alertmanager-config.sh"
cost_renderer="$repo_root/scripts/render-cost-observability.sh"

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

printf '%s\n' "$data_json" | jq -e '
  .services["minio-init"].read_only == true and
  .services["minio-init"].environment.MC_CONFIG_DIR == "/tmp/.mc" and
  any(.services["minio-init"].tmpfs[]; startswith("/tmp:"))
' >/dev/null || fail "MinIO init must keep its writable config under tmpfs"

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

render_dir="$(mktemp -d)"
trap 'rm -rf "$render_dir"' EXIT

ALERT_WEBHOOK_URL=https://example.invalid/warptalk-alerts \
ALERTMANAGER_CONFIG_PATH="$render_dir/alertmanager.yml" \
  "$alert_renderer" >/dev/null

AI_COST_STT_USD_PER_MINUTE=0 \
AI_COST_TRANSLATION_USD_PER_MINUTE=0 \
AI_COST_TTS_USD_PER_MINUTE=0 \
AI_COST_VOICE_CLONE_USD_PER_MINUTE=0 \
AI_BUDGET_STT_USD=0 \
AI_BUDGET_TRANSLATION_USD=0 \
AI_BUDGET_TTS_USD=0 \
AI_BUDGET_VOICE_CLONE_USD=0 \
LIVEKIT_COST_USD_PER_ROOM_MINUTE=0 \
LIVEKIT_MONTHLY_BUDGET_USD=0 \
OBJECT_STORAGE_BUDGET_GB=0 \
BILLING_COST_QUERIES_PATH="$render_dir/billing.yml" \
LIVEKIT_COST_QUERIES_PATH="$render_dir/livekit.yml" \
WORKSPACE_STORAGE_QUERIES_PATH="$render_dir/workspace.yml" \
COST_RULES_PATH="$render_dir/rules.yml" \
  "$cost_renderer" >/dev/null

file_mode() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"
}

for rendered_config in \
  "$render_dir/alertmanager.yml" \
  "$render_dir/billing.yml" \
  "$render_dir/livekit.yml" \
  "$render_dir/workspace.yml" \
  "$render_dir/rules.yml"; do
  [[ "$(file_mode "$rendered_config")" == "640" ]] ||
    fail "container-mounted rendered config must use mode 0640: $rendered_config"
done

rg -q 'chown 0:65534' "$alert_renderer" ||
  fail "Alertmanager renderer must grant the container nobody group access when run as root"
rg -q 'chown 0:65534' "$cost_renderer" ||
  fail "cost renderer must grant the container nobody group access when run as root"

echo "three-host Compose contract: PASS"
