#!/bin/sh
set -eu

: "${K3S_DATA_VALUES_FILE:?K3S_DATA_VALUES_FILE is required}"
: "${K3S_SECRET_STORE_NAME:?K3S_SECRET_STORE_NAME is required}"
: "${K3S_STORAGE_CLASS:?K3S_STORAGE_CLASS is required}"

OFFLINE_RENDER_ONLY="${OFFLINE_RENDER_ONLY:-false}"
APP_NAMESPACE="${K3S_NAMESPACE:-warptalk}"
DATA_NAMESPACE="${K3S_DATA_NAMESPACE:-warptalk-data}"

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
infra_root="$(CDPATH='' cd -- "$script_dir/.." && pwd)"
data_chart="$infra_root/deploy/k3s/data-chart"
redis_values="$infra_root/deploy/k3s/data/redis-values.yaml"
qdrant_values="$infra_root/deploy/k3s/data/qdrant-values.yaml"
qdrant_post_renderer="$infra_root/scripts/pin-qdrant-images.sh"
lock_file="$infra_root/deploy/k3s/addons.lock.env"

fail() {
  echo "K3s data deployment: $*" >&2
  exit 1
}

command -v docker >/dev/null 2>&1 || fail "missing dependency: docker"

test -r "$K3S_DATA_VALUES_FILE" || fail "cannot read data provider values"
test -r "$lock_file" || fail "cannot read add-on lock"

case "$K3S_DATA_VALUES_FILE" in
  /*) ;;
  *) K3S_DATA_VALUES_FILE="$(pwd)/$K3S_DATA_VALUES_FILE" ;;
esac

# shellcheck disable=SC1090
. "$lock_file"
export QDRANT_IMAGE_DIGEST QDRANT_TEST_IMAGE_DIGEST

render_dir="$(mktemp -d "${TMPDIR:-/tmp}/warptalk-k3s-data.XXXXXX")"
trap 'rm -rf "$render_dir"' EXIT INT TERM

docker run --rm \
  --env-file "$lock_file" \
  -e K3S_STORAGE_CLASS \
  -e K3S_SECRET_STORE_NAME \
  -e APP_NAMESPACE \
  -e DATA_NAMESPACE \
  -v "$data_chart:/data-chart:ro" \
  -v "$redis_values:/redis-values.yaml:ro" \
  -v "$qdrant_values:/qdrant-values.yaml:ro" \
  -v "$qdrant_post_renderer:/pin-qdrant-images.sh:ro" \
  -v "$K3S_DATA_VALUES_FILE:/provider-values.yaml:ro" \
  -v "$render_dir:/rendered" \
  --entrypoint sh \
  "$HELM_IMAGE" \
  -ec '
    helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null
    helm repo add qdrant https://qdrant.github.io/qdrant-helm >/dev/null
    helm repo update >/dev/null

    helm template warptalk-data /data-chart \
      --namespace "$DATA_NAMESPACE" \
      -f /provider-values.yaml \
      --set-string storageClass="$K3S_STORAGE_CLASS" \
      --set-string externalSecrets.secretStoreName="$K3S_SECRET_STORE_NAME" \
      --set-string postgres.namespace="$DATA_NAMESPACE" \
      --set-string rabbitmq.namespace="$APP_NAMESPACE" \
      > /rendered/data.yaml

    helm template warptalk-redis bitnami/redis \
      --version "$REDIS_CHART_VERSION" \
      --namespace "$DATA_NAMESPACE" \
      -f /redis-values.yaml \
      --set-string master.persistence.storageClass="$K3S_STORAGE_CLASS" \
      --set-string replica.persistence.storageClass="$K3S_STORAGE_CLASS" \
      > /rendered/redis.yaml

    helm template warptalk-qdrant qdrant/qdrant \
      --version "$QDRANT_CHART_VERSION" \
      --namespace "$DATA_NAMESPACE" \
      -f /qdrant-values.yaml \
      --set-string persistence.storageClassName="$K3S_STORAGE_CLASS" \
      --post-renderer /pin-qdrant-images.sh \
      > /rendered/qdrant.yaml
  '

if grep -Eirq 'CHANGE_ME|example\.com|:latest([@"[:space:]]|$)' "$render_dir"; then
  grep -Eirn 'CHANGE_ME|example\.com|:latest([@"[:space:]]|$)' "$render_dir" >&2
  fail "rendered data platform contains a placeholder or mutable latest tag"
fi

grep -R -Fq "storageClassName: $K3S_STORAGE_CLASS" "$render_dir" ||
  grep -R -Fq "storageClass: $K3S_STORAGE_CLASS" "$render_dir" ||
  fail "rendered data platform does not use K3S_STORAGE_CLASS"
grep -R -Fq "name: $K3S_SECRET_STORE_NAME" "$render_dir" ||
  fail "rendered data platform does not use K3S_SECRET_STORE_NAME"
grep -R -Fq "name: warptalk-qdrant-auth" "$render_dir" ||
  fail "Qdrant API-key secret is not wired"
grep -R -Fq "name: warptalk-redis-auth" "$render_dir" ||
  fail "Redis auth secret is not wired"

find "$render_dir" -type f -name '*.yaml' -print0 |
  sort -z |
  xargs -0 cat |
  docker run --rm -i "$KUBECONFORM_IMAGE" \
    -strict -summary -ignore-missing-schemas

if [ "$OFFLINE_RENDER_ONLY" = "true" ]; then
  echo "K3s data platform offline render: PASS"
  exit 0
fi

for dependency in helm kubectl jq; do
  command -v "$dependency" >/dev/null 2>&1 || fail "missing dependency: $dependency"
done

kubectl get storageclass "$K3S_STORAGE_CLASS" >/dev/null
kubectl get clustersecretstore "$K3S_SECRET_STORE_NAME" -o json |
  jq -e 'any(.status.conditions[]?; .type == "Ready" and .status == "True")' \
    >/dev/null || fail "ClusterSecretStore is not Ready"
for crd in \
  clusters.postgresql.cnpg.io \
  poolers.postgresql.cnpg.io \
  objectstores.barmancloud.cnpg.io \
  rabbitmqclusters.rabbitmq.com \
  externalsecrets.external-secrets.io; do
  kubectl get crd "$crd" >/dev/null || fail "missing required CRD: $crd"
done

kubectl create namespace "$APP_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$DATA_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$APP_NAMESPACE" warptalk.io/tier=application --overwrite
kubectl label namespace "$DATA_NAMESPACE" warptalk.io/tier=data --overwrite

helm repo add bitnami https://charts.bitnami.com/bitnami --force-update
helm repo add qdrant https://qdrant.github.io/qdrant-helm --force-update
helm repo update

helm upgrade --install warptalk-data "$data_chart" \
  --namespace "$DATA_NAMESPACE" \
  --atomic \
  --wait \
  --timeout 15m \
  -f "$K3S_DATA_VALUES_FILE" \
  --set-string storageClass="$K3S_STORAGE_CLASS" \
  --set-string externalSecrets.secretStoreName="$K3S_SECRET_STORE_NAME" \
  --set-string postgres.namespace="$DATA_NAMESPACE" \
  --set-string rabbitmq.namespace="$APP_NAMESPACE"

for external_secret in \
  warptalk-postgres-superuser \
  warptalk-backup-credentials \
  warptalk-redis-auth \
  warptalk-qdrant-auth; do
  kubectl wait --for=condition=Ready \
    "externalsecret/$external_secret" \
    --namespace "$DATA_NAMESPACE" \
    --timeout=5m
done

helm upgrade --install warptalk-redis bitnami/redis \
  --version "$REDIS_CHART_VERSION" \
  --namespace "$DATA_NAMESPACE" \
  --atomic \
  --wait \
  --timeout 15m \
  -f "$redis_values" \
  --set-string master.persistence.storageClass="$K3S_STORAGE_CLASS" \
  --set-string replica.persistence.storageClass="$K3S_STORAGE_CLASS"

helm upgrade --install warptalk-qdrant qdrant/qdrant \
  --version "$QDRANT_CHART_VERSION" \
  --namespace "$DATA_NAMESPACE" \
  --atomic \
  --wait \
  --timeout 15m \
  -f "$qdrant_values" \
  --set-string persistence.storageClassName="$K3S_STORAGE_CLASS" \
  --post-renderer "$qdrant_post_renderer"

kubectl wait --for=condition=Ready cluster/warptalk-postgres \
  --namespace "$DATA_NAMESPACE" --timeout=15m
kubectl wait --for=jsonpath='{.status.phase}'=active \
  pooler/warptalk-postgres-pooler-rw \
  --namespace "$DATA_NAMESPACE" --timeout=15m
kubectl wait --for=condition=AllReplicasReady rabbitmqcluster/warptalk-rabbitmq \
  --namespace "$APP_NAMESPACE" --timeout=15m
kubectl wait --for=create secret/warptalk-rabbitmq-default-user \
  --namespace "$APP_NAMESPACE" --timeout=5m

echo "K3s data platform deployed with storage class $K3S_STORAGE_CLASS"
