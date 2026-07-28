#!/bin/sh
set -eu

: "${K3S_STORAGE_CLASS:?K3S_STORAGE_CLASS is required}"

INSTALL_TRAEFIK="${INSTALL_TRAEFIK:-true}"
INSTALL_METRICS_SERVER="${INSTALL_METRICS_SERVER:-false}"

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
infra_root="$(CDPATH='' cd -- "$script_dir/.." && pwd)"
lock_file="$infra_root/deploy/k3s/addons.lock.env"
traefik_values="$infra_root/deploy/k3s/traefik-values.yaml"

fail() {
  echo "K3s add-on install: $*" >&2
  exit 1
}

for dependency in helm kubectl curl shasum jq docker; do
  command -v "$dependency" >/dev/null 2>&1 || fail "missing dependency: $dependency"
done

test -r "$lock_file" || fail "cannot read add-on lock"
# shellcheck disable=SC1090
. "$lock_file"

"$script_dir/check-k3s-addons.sh"

server_minor="$(kubectl version -o json | jq -r '.serverVersion.minor | sub("[^0-9].*$"; "") | tonumber')"
minimum_minor="${KUBERNETES_MIN_VERSION#*.}"
[ "$server_minor" -ge "$minimum_minor" ] ||
  fail "Kubernetes $KUBERNETES_MIN_VERSION or newer is required"
kubectl get storageclass "$K3S_STORAGE_CLASS" >/dev/null

for namespace in \
  cert-manager \
  cnpg-system \
  external-secrets \
  rabbitmq-system \
  keda \
  monitoring \
  traefik; do
  kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
done

helm repo add cnpg https://cloudnative-pg.github.io/charts --force-update
helm repo add external-secrets https://charts.external-secrets.io --force-update
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo add kedacore https://kedacore.github.io/charts --force-update
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server --force-update
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo add traefik https://traefik.github.io/charts --force-update
helm repo update

helm upgrade --install cert-manager jetstack/cert-manager \
  --version "$CERT_MANAGER_CHART_VERSION" \
  --namespace cert-manager \
  --atomic --wait --timeout 10m \
  --set crds.enabled=true

helm upgrade --install cnpg cnpg/cloudnative-pg \
  --version "$CNPG_CHART_VERSION" \
  --namespace cnpg-system \
  --atomic --wait --timeout 10m

manifest_dir="$(mktemp -d "${TMPDIR:-/tmp}/warptalk-k3s-operators.XXXXXX")"
trap 'rm -rf "$manifest_dir"' EXIT INT TERM
barman_manifest="$manifest_dir/barman-cloud.yaml"
rabbitmq_manifest="$manifest_dir/rabbitmq-cluster-operator.yaml"

curl --fail --location --silent --show-error \
  "https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/v${BARMAN_PLUGIN_VERSION}/manifest.yaml" \
  >"$barman_manifest"
echo "$BARMAN_PLUGIN_MANIFEST_SHA256  $barman_manifest" | shasum -a 256 -c -
kubectl apply --server-side -f "$barman_manifest"
kubectl rollout status deployment/barman-cloud \
  --namespace cnpg-system --timeout=5m

curl --fail --location --silent --show-error \
  "https://github.com/rabbitmq/cluster-operator/releases/download/v${RABBITMQ_OPERATOR_VERSION}/cluster-operator.yml" \
  >"$rabbitmq_manifest"
echo "$RABBITMQ_OPERATOR_MANIFEST_SHA256  $rabbitmq_manifest" | shasum -a 256 -c -
kubectl apply --server-side -f "$rabbitmq_manifest"
kubectl rollout status deployment/rabbitmq-cluster-operator \
  --namespace rabbitmq-system --timeout=5m

helm upgrade --install external-secrets external-secrets/external-secrets \
  --version "$EXTERNAL_SECRETS_CHART_VERSION" \
  --namespace external-secrets \
  --atomic --wait --timeout 10m

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version "$PROMETHEUS_STACK_CHART_VERSION" \
  --namespace monitoring \
  --atomic --wait --timeout 15m

helm upgrade --install keda kedacore/keda \
  --version "$KEDA_CHART_VERSION" \
  --namespace keda \
  --atomic --wait --timeout 10m

if [ "$INSTALL_METRICS_SERVER" = "true" ]; then
  helm upgrade --install metrics-server metrics-server/metrics-server \
    --version "$METRICS_SERVER_CHART_VERSION" \
    --namespace kube-system \
    --atomic --wait --timeout 10m
else
  kubectl get deployment metrics-server --namespace kube-system >/dev/null ||
    fail "metrics-server is absent; rerun with INSTALL_METRICS_SERVER=true"
fi

if [ "$INSTALL_TRAEFIK" = "true" ]; then
  if helm status traefik --namespace kube-system >/dev/null 2>&1; then
    fail "bundled K3s Traefik is active; recreate K3s with --disable=traefik before installing the locked HA release"
  fi
  helm upgrade --install traefik traefik/traefik \
    --version "$TRAEFIK_CHART_VERSION" \
    --namespace traefik \
    --atomic --wait --timeout 10m \
    -f "$traefik_values"
else
  kubectl get ingressclass traefik >/dev/null ||
    fail "Traefik ingress class is absent; rerun with INSTALL_TRAEFIK=true"
fi

echo "K3s locked add-ons installed and ready"
