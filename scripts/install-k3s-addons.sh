#!/usr/bin/env bash
# Cluster add-ons at the versions and digests locked in deploy/k3s/addons.lock.env. Idempotent
# (every step is an upgrade --install or a server-side apply), so the manual cluster bootstrap
# in deploy/k3s/README.md can re-run it safely. Every Helm call goes through scripts/helm-locked.sh.
set -euo pipefail

: "${K3S_STORAGE_CLASS:?K3S_STORAGE_CLASS is required}"
# Never the operator's default context.
: "${KUBECONFIG:?KUBECONFIG must name the target cluster explicitly}"
export KUBECONFIG

INSTALL_TRAEFIK="${INSTALL_TRAEFIK:-true}"
INSTALL_METRICS_SERVER="${INSTALL_METRICS_SERVER:-false}"
# External Secrets is optional: production reads runtime secrets from the GitHub `production`
# environment (scripts/materialize-k8s-runtime-secrets.sh).
INSTALL_EXTERNAL_SECRETS="${INSTALL_EXTERNAL_SECRETS:-false}"
# kubeadm kubelets serve self-signed certificates unless serverTLSBootstrap is on and the CSRs are
# approved. k8s-cluster-bootstrap.sh does both for a new cluster; the live cluster's kubelets were
# joined without it, so the manual cluster bootstrap passes true until they are re-bootstrapped
# (metrics-server -> kubelet traffic stays on the node network either way).
METRICS_SERVER_KUBELET_INSECURE_TLS="${METRICS_SERVER_KUBELET_INSECURE_TLS:-false}"

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
infra_root="$(CDPATH='' cd -- "$script_dir/.." && pwd)"
lock_file="$infra_root/deploy/k3s/addons.lock.env"
traefik_values="$infra_root/deploy/k3s/traefik-values.yaml"
monitoring_values="$infra_root/deploy/k3s/monitoring-values.yaml"
helm_locked="$infra_root/scripts/helm-locked.sh"

fail() {
  echo "K3s add-on install: $*" >&2
  exit 1
}

for dependency in kubectl curl jq docker; do
  command -v "$dependency" >/dev/null 2>&1 || fail "missing dependency: $dependency"
done

test -r "$lock_file" || fail "cannot read add-on lock"
# shellcheck disable=SC1090
. "$lock_file"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

"$script_dir/check-k3s-addons.sh"

server_minor="$(kubectl version -o json | jq -r '.serverVersion.minor | sub("[^0-9].*$"; "") | tonumber')"
minimum_minor="$(echo "$KUBERNETES_MIN_VERSION" | cut -d. -f2)"
[ "$server_minor" -ge "$minimum_minor" ] ||
  fail "Kubernetes $KUBERNETES_MIN_VERSION or newer is required"
kubectl get storageclass "$K3S_STORAGE_CLASS" >/dev/null

namespaces=(cert-manager cnpg-system rabbitmq-system keda monitoring traefik)
if [ "$INSTALL_EXTERNAL_SECRETS" = "true" ]; then
  namespaces+=(external-secrets)
fi
for namespace in "${namespaces[@]}"; do
  kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
done

for repository in \
  "cnpg https://cloudnative-pg.github.io/charts" \
  "external-secrets https://charts.external-secrets.io" \
  "jetstack https://charts.jetstack.io" \
  "kedacore https://kedacore.github.io/charts" \
  "metrics-server https://kubernetes-sigs.github.io/metrics-server" \
  "prometheus-community https://prometheus-community.github.io/helm-charts" \
  "traefik https://traefik.github.io/charts"; do
  # shellcheck disable=SC2086
  "$helm_locked" repo add $repository --force-update >/dev/null
done
"$helm_locked" repo update >/dev/null

# TLS: cert-manager owns issuance and renewal of every certificate the app chart requests.
"$helm_locked" upgrade --install cert-manager jetstack/cert-manager \
  --version "$CERT_MANAGER_CHART_VERSION" \
  --namespace cert-manager \
  --atomic --wait --timeout 10m \
  --set crds.enabled=true

"$helm_locked" upgrade --install cnpg cnpg/cloudnative-pg \
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
[ "$(sha256_of "$barman_manifest")" = "$BARMAN_PLUGIN_MANIFEST_SHA256" ] ||
  fail "Barman Cloud plugin manifest checksum mismatch"
kubectl apply --server-side -f "$barman_manifest"
kubectl rollout status deployment/barman-cloud \
  --namespace cnpg-system --timeout=5m

curl --fail --location --silent --show-error \
  "https://github.com/rabbitmq/cluster-operator/releases/download/v${RABBITMQ_OPERATOR_VERSION}/cluster-operator.yml" \
  >"$rabbitmq_manifest"
[ "$(sha256_of "$rabbitmq_manifest")" = "$RABBITMQ_OPERATOR_MANIFEST_SHA256" ] ||
  fail "RabbitMQ operator manifest checksum mismatch"
kubectl apply --server-side -f "$rabbitmq_manifest"
kubectl rollout status deployment/rabbitmq-cluster-operator \
  --namespace rabbitmq-system --timeout=5m

if [ "$INSTALL_EXTERNAL_SECRETS" = "true" ]; then
  "$helm_locked" upgrade --install external-secrets external-secrets/external-secrets \
    --version "$EXTERNAL_SECRETS_CHART_VERSION" \
    --namespace external-secrets \
    --atomic --wait --timeout 10m
fi

# Traefik before monitoring: the Grafana values create Traefik Middlewares (the admin-only
# ForwardAuth in front of the embedded Grafana), and those need Traefik's CRDs to exist.
if [ "$INSTALL_TRAEFIK" = "true" ]; then
  if "$helm_locked" status traefik --namespace kube-system >/dev/null 2>&1; then
    fail "bundled K3s Traefik is active; recreate K3s with --disable=traefik before installing the locked HA release"
  fi
  "$helm_locked" upgrade --install traefik traefik/traefik \
    --version "$TRAEFIK_CHART_VERSION" \
    --namespace traefik \
    --atomic --wait --timeout 10m \
    -f "$traefik_values"
else
  kubectl get ingressclass traefik >/dev/null ||
    fail "Traefik ingress class is absent; rerun with INSTALL_TRAEFIK=true"
fi

# Alertmanager reads its receivers from monitoring/warptalk-alertmanager and Grafana its admin from
# monitoring/warptalk-grafana-admin; scripts/materialize-k8s-runtime-secrets.sh writes both and
# must run first.
for secret in warptalk-alertmanager warptalk-grafana-admin; do
  kubectl get secret "$secret" --namespace monitoring >/dev/null ||
    fail "monitoring/$secret is missing; run scripts/materialize-k8s-runtime-secrets.sh first"
done
"$helm_locked" upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version "$PROMETHEUS_STACK_CHART_VERSION" \
  --namespace monitoring \
  --atomic --wait --timeout 15m \
  -f "$monitoring_values"

"$helm_locked" upgrade --install keda kedacore/keda \
  --version "$KEDA_CHART_VERSION" \
  --namespace keda \
  --atomic --wait --timeout 10m

if [ "$INSTALL_METRICS_SERVER" = "true" ]; then
  metrics_server_args=()
  if [ "$METRICS_SERVER_KUBELET_INSECURE_TLS" = "true" ]; then
    echo "WARNING: metrics-server will not verify kubelet certificates" >&2
    metrics_server_args=(--set "args={--kubelet-insecure-tls}")
  fi
  "$helm_locked" upgrade --install metrics-server metrics-server/metrics-server \
    --version "$METRICS_SERVER_CHART_VERSION" \
    --namespace kube-system \
    --atomic --wait --timeout 10m \
    ${metrics_server_args[@]+"${metrics_server_args[@]}"}
else
  kubectl get deployment metrics-server --namespace kube-system >/dev/null ||
    fail "metrics-server is absent; rerun with INSTALL_METRICS_SERVER=true"
fi

echo "K3s locked add-ons installed and ready"
