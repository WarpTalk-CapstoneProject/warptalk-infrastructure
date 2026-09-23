#!/bin/sh
set -eu

: "${K3S_DATA_VALUES_FILE:?K3S_DATA_VALUES_FILE is required}"
: "${K3S_STORAGE_CLASS:?K3S_STORAGE_CLASS is required}"

# Where the four data-namespace secrets come from (postgres superuser, backup credentials, redis
# auth, qdrant auth):
#   github            - written by the release job from the GitHub `production` environment
#                       (scripts/materialize-k8s-runtime-secrets.sh). Production.
#   external-secrets  - ExternalSecrets against K3S_SECRET_STORE_NAME.
K3S_SECRET_SOURCE="${K3S_SECRET_SOURCE:-external-secrets}"
case "$K3S_SECRET_SOURCE" in
  github) ;;
  external-secrets)
    : "${K3S_SECRET_STORE_NAME:?K3S_SECRET_STORE_NAME is required for K3S_SECRET_SOURCE=external-secrets}"
    ;;
  *) echo "K3s data deployment: K3S_SECRET_SOURCE must be github or external-secrets" >&2; exit 1 ;;
esac

OFFLINE_RENDER_ONLY="${OFFLINE_RENDER_ONLY:-false}"
# Server-side dry run: every release is validated and admitted by the API server, nothing persists.
K3S_DRY_RUN="${K3S_DRY_RUN:-false}"
APP_NAMESPACE="${K3S_NAMESPACE:-warptalk}"
DATA_NAMESPACE="${K3S_DATA_NAMESPACE:-warptalk-data}"
# The object-store endpoint carries the account id, so it is not committed; the release job
# passes it from BACKUP_S3_ENDPOINT_URL in the GitHub `production` runtime env.
K3S_BACKUP_ENDPOINT_URL="${K3S_BACKUP_ENDPOINT_URL:-}"

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
infra_root="$(CDPATH='' cd -- "$script_dir/.." && pwd)"
data_chart="$infra_root/deploy/k3s/data-chart"
redis_values="$infra_root/deploy/k3s/data/redis-values.yaml"
qdrant_values="$infra_root/deploy/k3s/data/qdrant-values.yaml"
qdrant_post_renderer="$infra_root/scripts/pin-qdrant-images.sh"
lock_file="$infra_root/deploy/k3s/addons.lock.env"
helm_locked="$infra_root/scripts/helm-locked.sh"

fail() {
  echo "K3s data deployment: $*" >&2
  exit 1
}

for dependency in docker jq; do
  command -v "$dependency" >/dev/null 2>&1 || fail "missing dependency: $dependency"
done

test -r "$K3S_DATA_VALUES_FILE" || fail "cannot read data provider values"
test -r "$lock_file" || fail "cannot read add-on lock"

case "$K3S_DATA_VALUES_FILE" in
  /*) ;;
  *) K3S_DATA_VALUES_FILE="$(pwd)/$K3S_DATA_VALUES_FILE" ;;
esac

# shellcheck disable=SC1090
. "$lock_file"

render_dir="$(mktemp -d "${TMPDIR:-/tmp}/warptalk-k3s-data.XXXXXX")"
trap 'rm -rf "$render_dir"' EXIT INT TERM

# Arguments shared by render, dry run and install, so the three can never disagree.
data_chart_arguments="$render_dir/data-chart.args"
{
  printf '%s\n' --namespace "$DATA_NAMESPACE" -f "$K3S_DATA_VALUES_FILE"
  printf '%s\n' --set-string "storageClass=$K3S_STORAGE_CLASS"
  printf '%s\n' --set-string "postgres.namespace=$DATA_NAMESPACE"
  printf '%s\n' --set-string "rabbitmq.namespace=$APP_NAMESPACE"
  if [ "$K3S_SECRET_SOURCE" = "external-secrets" ]; then
    printf '%s\n' --set-string "externalSecrets.secretStoreName=$K3S_SECRET_STORE_NAME"
  else
    printf '%s\n' --set "externalSecrets.enabled=false"
  fi
  if [ -n "$K3S_BACKUP_ENDPOINT_URL" ]; then
    printf '%s\n' --set-string "postgres.backup.endpointURL=$K3S_BACKUP_ENDPOINT_URL"
  fi
} >"$data_chart_arguments"

# helm_data <helm verb and leading args...>: appends the data-chart arguments above.
helm_data() {
  set -- "$@"
  while IFS= read -r argument; do
    set -- "$@" "$argument"
  done <"$data_chart_arguments"
  "$helm_locked" "$@"
}

"$helm_locked" repo add bitnami https://charts.bitnami.com/bitnami --force-update >/dev/null
"$helm_locked" repo add qdrant https://qdrant.github.io/qdrant-helm --force-update >/dev/null
"$helm_locked" repo update >/dev/null

helm_data template warptalk-data "$data_chart" >"$render_dir/data.yaml"

"$helm_locked" template warptalk-redis bitnami/redis \
  --version "$REDIS_CHART_VERSION" \
  --namespace "$DATA_NAMESPACE" \
  -f "$redis_values" \
  --set-string replica.persistence.storageClass="$K3S_STORAGE_CLASS" \
  >"$render_dir/redis.yaml"

"$helm_locked" template warptalk-qdrant qdrant/qdrant \
  --version "$QDRANT_CHART_VERSION" \
  --namespace "$DATA_NAMESPACE" \
  -f "$qdrant_values" \
  --set-string persistence.storageClassName="$K3S_STORAGE_CLASS" \
  --post-renderer "$qdrant_post_renderer" \
  >"$render_dir/qdrant.yaml"

if grep -Eirq 'CHANGE_ME|example\.com|:latest([@"[:space:]]|$)' "$render_dir"/*.yaml; then
  grep -Eirn 'CHANGE_ME|example\.com|:latest([@"[:space:]]|$)' "$render_dir"/*.yaml >&2
  fail "rendered data platform contains a placeholder or mutable latest tag"
fi

grep -Fq "storageClassName: $K3S_STORAGE_CLASS" "$render_dir"/*.yaml ||
  grep -Fq "storageClass: $K3S_STORAGE_CLASS" "$render_dir"/*.yaml ||
  fail "rendered data platform does not use K3S_STORAGE_CLASS"
if [ "$K3S_SECRET_SOURCE" = "external-secrets" ]; then
  grep -Fq "name: $K3S_SECRET_STORE_NAME" "$render_dir"/*.yaml ||
    fail "rendered data platform does not use K3S_SECRET_STORE_NAME"
elif grep -Fq "kind: ExternalSecret" "$render_dir/data.yaml"; then
  fail "K3S_SECRET_SOURCE=github but the data chart still renders ExternalSecrets"
fi
# The chart resolves apiKey.valueFrom with `lookup` at install time, so an offline render cannot
# show the key itself; check the wiring in the values instead.
grep -Fq "name: warptalk-qdrant-auth" "$qdrant_values" ||
  fail "Qdrant API-key secret is not wired"
grep -Fq "warptalk-redis-auth" "$render_dir/redis.yaml" ||
  fail "Redis auth secret is not wired"
grep -Fq "maxmemory-policy noeviction" "$render_dir/redis.yaml" ||
  fail "Redis must refuse writes when full (noeviction), not silently delete live meeting state"

cat "$render_dir/data.yaml" "$render_dir/redis.yaml" "$render_dir/qdrant.yaml" |
  docker run --rm -i "$KUBECONFORM_IMAGE" \
    -strict -summary -ignore-missing-schemas

if [ "$OFFLINE_RENDER_ONLY" = "true" ]; then
  echo "K3s data platform offline render: PASS"
  exit 0
fi

# Never the operator's default context (~/.kube/config): the target cluster is named explicitly.
# An explicit test, not ${KUBECONFIG:?}: after the EXIT trap above, a failed ${:?} expansion can
# leave some /bin/sh implementations exiting 0.
[ -n "${KUBECONFIG:-}" ] || fail "KUBECONFIG must name the target cluster explicitly"
export KUBECONFIG
command -v kubectl >/dev/null 2>&1 || fail "missing dependency: kubectl"

kubectl get storageclass "$K3S_STORAGE_CLASS" >/dev/null
if [ "$K3S_SECRET_SOURCE" = "external-secrets" ]; then
  kubectl get clustersecretstore "$K3S_SECRET_STORE_NAME" -o json |
    jq -e 'any(.status.conditions[]?; .type == "Ready" and .status == "True")' \
      >/dev/null || fail "ClusterSecretStore is not Ready"
  kubectl get crd externalsecrets.external-secrets.io >/dev/null ||
    fail "missing required CRD: externalsecrets.external-secrets.io"
fi
for crd in \
  clusters.postgresql.cnpg.io \
  poolers.postgresql.cnpg.io \
  objectstores.barmancloud.cnpg.io \
  rabbitmqclusters.rabbitmq.com; do
  kubectl get crd "$crd" >/dev/null || fail "missing required CRD: $crd"
done

require_secret_keys() {
  # $1 namespace, $2 secret, remaining: keys that must be non-empty
  namespace="$1"
  secret="$2"
  shift 2
  secret_json="$(kubectl get secret "$secret" --namespace "$namespace" -o json)" ||
    fail "required secret $namespace/$secret is missing"
  for key in "$@"; do
    printf '%s\n' "$secret_json" |
      jq -e --arg key "$key" '(.data[$key] // "") | length > 0' >/dev/null ||
      fail "secret $namespace/$secret has no value for $key"
  done
}

if [ "$K3S_DRY_RUN" = "true" ]; then
  if [ "$K3S_SECRET_SOURCE" = "github" ]; then
    require_secret_keys "$DATA_NAMESPACE" warptalk-postgres-superuser username password
    require_secret_keys "$DATA_NAMESPACE" warptalk-backup-credentials ACCESS_KEY_ID SECRET_ACCESS_KEY ENDPOINT_URL
    require_secret_keys "$DATA_NAMESPACE" warptalk-redis-auth password
    require_secret_keys "$DATA_NAMESPACE" warptalk-qdrant-auth api-key
  fi
  helm_data upgrade --install warptalk-data "$data_chart" --dry-run=server >/dev/null
  "$helm_locked" upgrade --install warptalk-redis bitnami/redis \
    --version "$REDIS_CHART_VERSION" --namespace "$DATA_NAMESPACE" --dry-run=server \
    -f "$redis_values" \
    --set-string replica.persistence.storageClass="$K3S_STORAGE_CLASS" >/dev/null
  "$helm_locked" upgrade --install warptalk-qdrant qdrant/qdrant \
    --version "$QDRANT_CHART_VERSION" --namespace "$DATA_NAMESPACE" --dry-run=server \
    -f "$qdrant_values" \
    --set-string persistence.storageClassName="$K3S_STORAGE_CLASS" \
    --post-renderer "$qdrant_post_renderer" >/dev/null
  echo "K3s data platform server-side dry run: PASS; nothing was changed"
  exit 0
fi

for namespace in "$APP_NAMESPACE" "$DATA_NAMESPACE"; do
  kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
done
kubectl label namespace "$APP_NAMESPACE" warptalk.io/tier=application --overwrite
kubectl label namespace "$DATA_NAMESPACE" warptalk.io/tier=data --overwrite

helm_data upgrade --install warptalk-data "$data_chart" \
  --atomic \
  --wait \
  --timeout 15m

if [ "$K3S_SECRET_SOURCE" = "external-secrets" ]; then
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
else
  require_secret_keys "$DATA_NAMESPACE" warptalk-postgres-superuser username password
  require_secret_keys "$DATA_NAMESPACE" warptalk-backup-credentials ACCESS_KEY_ID SECRET_ACCESS_KEY ENDPOINT_URL
  require_secret_keys "$DATA_NAMESPACE" warptalk-redis-auth password
  require_secret_keys "$DATA_NAMESPACE" warptalk-qdrant-auth api-key
fi

"$helm_locked" upgrade --install warptalk-redis bitnami/redis \
  --version "$REDIS_CHART_VERSION" \
  --namespace "$DATA_NAMESPACE" \
  --atomic \
  --wait \
  --timeout 15m \
  -f "$redis_values" \
  --set-string replica.persistence.storageClass="$K3S_STORAGE_CLASS"

"$helm_locked" upgrade --install warptalk-qdrant qdrant/qdrant \
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
