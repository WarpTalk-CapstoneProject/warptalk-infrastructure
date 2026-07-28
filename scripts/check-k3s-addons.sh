#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_FILE="$ROOT_DIR/deploy/k3s/addons.lock.env"

[[ -f "$LOCK_FILE" ]] || {
  echo "missing K3s add-on lock: $LOCK_FILE" >&2
  exit 1
}

# shellcheck disable=SC1090
source "$LOCK_FILE"

required_variables=(
  HELM_IMAGE KUBECONFORM_IMAGE
  OTEL_COLLECTOR_VERSION OTEL_COLLECTOR_IMAGE_DIGEST SQL_EXPORTER_IMAGE_DIGEST
  CNPG_CHART_VERSION CNPG_CHART_SHA256
  BARMAN_PLUGIN_VERSION BARMAN_PLUGIN_MANIFEST_SHA256
  RABBITMQ_OPERATOR_VERSION RABBITMQ_OPERATOR_MANIFEST_SHA256
  EXTERNAL_SECRETS_CHART_VERSION EXTERNAL_SECRETS_CHART_SHA256
  CERT_MANAGER_CHART_VERSION CERT_MANAGER_CHART_SHA256
  KEDA_CHART_VERSION KEDA_CHART_SHA256
  METRICS_SERVER_CHART_VERSION METRICS_SERVER_CHART_SHA256
  PROMETHEUS_STACK_CHART_VERSION PROMETHEUS_STACK_CHART_SHA256
  REDIS_CHART_VERSION REDIS_CHART_SHA256
  REDIS_IMAGE_DIGEST REDIS_SENTINEL_IMAGE_DIGEST REDIS_EXPORTER_IMAGE_DIGEST
  QDRANT_CHART_VERSION QDRANT_CHART_SHA256 QDRANT_IMAGE_DIGEST QDRANT_TEST_IMAGE_DIGEST
  TRAEFIK_CHART_VERSION TRAEFIK_CHART_SHA256
)

for variable in "${required_variables[@]}"; do
  [[ -n "${!variable:-}" ]] || {
    echo "missing locked value: $variable" >&2
    exit 1
  }
done

grep -Fq "$SQL_EXPORTER_IMAGE_DIGEST" \
  "$ROOT_DIR/deploy/k3s/chart/values.yaml" || {
  echo "K3s chart is missing the locked SQL exporter image digest" >&2
  exit 1
}

verify_remote_manifest() {
  local url="$1"
  local expected="$2"
  local name="$3"
  local actual

  actual="$(curl --fail --location --silent --show-error "$url" | shasum -a 256 | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || {
    echo "$name manifest checksum mismatch: expected $expected, got $actual" >&2
    exit 1
  }
}

verify_remote_manifest \
  "https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/v${BARMAN_PLUGIN_VERSION}/manifest.yaml" \
  "$BARMAN_PLUGIN_MANIFEST_SHA256" \
  "Barman Cloud plugin"
verify_remote_manifest \
  "https://github.com/rabbitmq/cluster-operator/releases/download/v${RABBITMQ_OPERATOR_VERSION}/cluster-operator.yml" \
  "$RABBITMQ_OPERATOR_MANIFEST_SHA256" \
  "RabbitMQ operator"

render_dir="$(mktemp -d "${TMPDIR:-/tmp}/warptalk-k3s-addons.XXXXXX")"
trap 'rm -rf "$render_dir"' EXIT

docker run --rm \
  --env-file "$LOCK_FILE" \
  -v "$ROOT_DIR/deploy/k3s:/work:ro" \
  -v "$ROOT_DIR/scripts/pin-qdrant-images.sh:/pin-qdrant-images.sh:ro" \
  -v "$render_dir:/rendered" \
  --entrypoint sh \
  "$HELM_IMAGE" \
  -ec '
    helm repo add cnpg https://cloudnative-pg.github.io/charts >/dev/null
    helm repo add external-secrets https://charts.external-secrets.io >/dev/null
    helm repo add jetstack https://charts.jetstack.io >/dev/null
    helm repo add kedacore https://kedacore.github.io/charts >/dev/null
    helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server >/dev/null
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
    helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null
    helm repo add qdrant https://qdrant.github.io/qdrant-helm >/dev/null
    helm repo add traefik https://traefik.github.io/charts >/dev/null
    helm repo update >/dev/null

    verify_chart() {
      chart="$1"
      version="$2"
      expected="$3"
      package_name="$4"
      helm pull "$chart" --version "$version" --destination /tmp
      actual="$(sha256sum "/tmp/$package_name" | awk "{print \$1}")"
      if [ "$actual" != "$expected" ]; then
        echo "$chart checksum mismatch: expected $expected, got $actual" >&2
        exit 1
      fi
    }

    verify_chart cnpg/cloudnative-pg "$CNPG_CHART_VERSION" "$CNPG_CHART_SHA256" "cloudnative-pg-$CNPG_CHART_VERSION.tgz"
    verify_chart external-secrets/external-secrets "$EXTERNAL_SECRETS_CHART_VERSION" "$EXTERNAL_SECRETS_CHART_SHA256" "external-secrets-$EXTERNAL_SECRETS_CHART_VERSION.tgz"
    verify_chart jetstack/cert-manager "$CERT_MANAGER_CHART_VERSION" "$CERT_MANAGER_CHART_SHA256" "cert-manager-$CERT_MANAGER_CHART_VERSION.tgz"
    verify_chart kedacore/keda "$KEDA_CHART_VERSION" "$KEDA_CHART_SHA256" "keda-$KEDA_CHART_VERSION.tgz"
    verify_chart metrics-server/metrics-server "$METRICS_SERVER_CHART_VERSION" "$METRICS_SERVER_CHART_SHA256" "metrics-server-$METRICS_SERVER_CHART_VERSION.tgz"
    verify_chart prometheus-community/kube-prometheus-stack "$PROMETHEUS_STACK_CHART_VERSION" "$PROMETHEUS_STACK_CHART_SHA256" "kube-prometheus-stack-$PROMETHEUS_STACK_CHART_VERSION.tgz"
    verify_chart bitnami/redis "$REDIS_CHART_VERSION" "$REDIS_CHART_SHA256" "redis-$REDIS_CHART_VERSION.tgz"
    verify_chart qdrant/qdrant "$QDRANT_CHART_VERSION" "$QDRANT_CHART_SHA256" "qdrant-$QDRANT_CHART_VERSION.tgz"
    verify_chart traefik/traefik "$TRAEFIK_CHART_VERSION" "$TRAEFIK_CHART_SHA256" "traefik-$TRAEFIK_CHART_VERSION.tgz"

    helm template cnpg cnpg/cloudnative-pg --version "$CNPG_CHART_VERSION" --namespace cnpg-system > /rendered/cnpg.yaml
    helm template external-secrets external-secrets/external-secrets --version "$EXTERNAL_SECRETS_CHART_VERSION" --namespace external-secrets > /rendered/external-secrets.yaml
    helm template cert-manager jetstack/cert-manager --version "$CERT_MANAGER_CHART_VERSION" --namespace cert-manager --set crds.enabled=true > /rendered/cert-manager.yaml
    helm template keda kedacore/keda --version "$KEDA_CHART_VERSION" --namespace keda > /rendered/keda.yaml
    helm template metrics-server metrics-server/metrics-server --version "$METRICS_SERVER_CHART_VERSION" --namespace kube-system > /rendered/metrics-server.yaml
    helm template monitoring prometheus-community/kube-prometheus-stack --version "$PROMETHEUS_STACK_CHART_VERSION" --namespace monitoring > /rendered/monitoring.yaml
    helm template warptalk-redis bitnami/redis --version "$REDIS_CHART_VERSION" --namespace warptalk-data -f /work/data/redis-values.yaml > /rendered/redis.yaml
    helm template warptalk-qdrant qdrant/qdrant --version "$QDRANT_CHART_VERSION" --namespace warptalk-data -f /work/data/qdrant-values.yaml --post-renderer /pin-qdrant-images.sh > /rendered/qdrant.yaml
    helm template traefik traefik/traefik --version "$TRAEFIK_CHART_VERSION" --namespace traefik -f /work/traefik-values.yaml > /rendered/traefik.yaml
  '

if grep -Eirq '^[[:space:]]+image:[[:space:]]+.*:latest([@"[:space:]]|$)' "$render_dir"; then
  grep -Eirn '^[[:space:]]+image:[[:space:]]+.*:latest([@"[:space:]]|$)' "$render_dir" >&2
  echo "locked K3s add-ons rendered a mutable latest image" >&2
  exit 1
fi

find "$render_dir" -type f -name '*.yaml' -print0 |
  sort -z |
  xargs -0 cat |
  docker run --rm -i "$KUBECONFORM_IMAGE" \
    -strict -summary -ignore-missing-schemas

docker run --rm \
  -v "$ROOT_DIR/deploy/k3s/chart/files/otel-collector.yaml:/etc/otelcol-contrib/config.yaml:ro" \
  "ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:${OTEL_COLLECTOR_VERSION}@${OTEL_COLLECTOR_IMAGE_DIGEST}" \
  validate --config=/etc/otelcol-contrib/config.yaml

echo "K3s add-on lock and render contract: PASS"
