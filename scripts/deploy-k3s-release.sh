#!/bin/sh
set -eu

: "${RELEASE_MANIFEST:?RELEASE_MANIFEST is required}"
: "${K3S_VALUES_FILE:?K3S_VALUES_FILE is required}"
: "${K3S_SECRET_STORE_NAME:?K3S_SECRET_STORE_NAME is required}"
: "${K3S_STORAGE_CLASS:?K3S_STORAGE_CLASS is required}"
: "${K3S_TLS_SECRET_NAME:?K3S_TLS_SECRET_NAME is required}"

OFFLINE_RENDER_ONLY="${OFFLINE_RENDER_ONLY:-false}"
K3S_MANAGED_TLS="${K3S_MANAGED_TLS:-true}"
NAMESPACE="${K3S_NAMESPACE:-warptalk}"
DATA_NAMESPACE="${K3S_DATA_NAMESPACE:-warptalk-data}"
RELEASE_NAME="${K3S_RELEASE_NAME:-warptalk}"

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
infra_root="$(CDPATH='' cd -- "$script_dir/.." && pwd)"
chart_dir="$infra_root/deploy/k3s/chart"
matrix_file="$infra_root/deploy/production/image-matrix.json"
lock_file="$infra_root/deploy/k3s/addons.lock.env"
runtime_secret_check="$infra_root/scripts/check-k3s-runtime-secret.sh"
acceptance_check="$infra_root/scripts/accept-k3s-release.sh"

fail() {
  echo "K3s release: $*" >&2
  exit 1
}

for dependency in docker jq; do
  command -v "$dependency" >/dev/null 2>&1 || fail "missing dependency: $dependency"
done

test -r "$RELEASE_MANIFEST" || fail "cannot read release manifest"
test -r "$K3S_VALUES_FILE" || fail "cannot read provider values"
test -r "$lock_file" || fail "cannot read add-on lock"

case "$RELEASE_MANIFEST" in
  /*) ;;
  *) RELEASE_MANIFEST="$(pwd)/$RELEASE_MANIFEST" ;;
esac
case "$K3S_VALUES_FILE" in
  /*) ;;
  *) K3S_VALUES_FILE="$(pwd)/$K3S_VALUES_FILE" ;;
esac

jq -e --slurpfile matrix "$matrix_file" '
  .schemaVersion == 1 and
  ([.images[].service] | sort) == ([$matrix[0].images[].service] | sort) and
  (.images | length) == ([.images[].service] | unique | length) and
  all(.images[];
    (.service | test("^[a-z0-9][a-z0-9-]*$")) and
    (.ref | test("^.+:[A-Za-z0-9][A-Za-z0-9._-]{6,127}$")) and
    (.digest | test("^sha256:[a-f0-9]{64}$"))
  )
' "$RELEASE_MANIFEST" >/dev/null ||
  fail "release manifest must contain exactly one immutable image for every matrix service"

override_file="$(mktemp "${TMPDIR:-/tmp}/warptalk-k3s-images.XXXXXX")"
rendered_file="$(mktemp "${TMPDIR:-/tmp}/warptalk-k3s-release.XXXXXX")"
trap 'rm -f "$override_file" "$rendered_file"' EXIT INT TERM

jq --slurpfile matrix "$matrix_file" '
  ($matrix[0].images | map(select(.k3s != false) | .service)) as $k3s_services |
  {
    global: {
      production: true,
      releaseId: .tag
    },
    migrator: {
      imageRef: (
        .images[]
        | select(.service == "migrator")
        | (.ref + "@" + .digest)
      )
    },
    workloads: (
      reduce (
        .images[]
        | select(.service != "migrator")
        | select(.service as $service | $k3s_services | index($service))
      ) as $image ({};
        .[$image.service] = {imageRef: ($image.ref + "@" + $image.digest)}
      )
    )
  }
' "$RELEASE_MANIFEST" >"$override_file"

# shellcheck disable=SC1090
. "$lock_file"

docker run --rm \
  -v "$chart_dir:/chart:ro" \
  -v "$K3S_VALUES_FILE:/provider-values.yaml:ro" \
  -v "$override_file:/image-values.json:ro" \
  "$HELM_IMAGE" \
  template "$RELEASE_NAME" /chart \
    --namespace "$NAMESPACE" \
    -f /provider-values.yaml \
    -f /image-values.json >"$rendered_file"

docker run --rm -i "$KUBECONFORM_IMAGE" \
  -strict -summary -ignore-missing-schemas <"$rendered_file"

if grep -Eiq 'CHANGE_ME|replace-with|example\.com|:latest([@"[:space:]]|$)' "$rendered_file"; then
  fail "rendered release contains a placeholder or mutable latest tag"
fi

image_count="$(grep -Ec '^[[:space:]]+image: ".+@sha256:[a-f0-9]{64}"$' "$rendered_file")"
expected_image_count="$(jq '[.images[] | select(.k3s != false)] | length' "$matrix_file")"
otel_image_count="$(grep -Fc "$OTEL_COLLECTOR_IMAGE_DIGEST" "$rendered_file")"
sql_exporter_image_count="$(grep -Fc "$SQL_EXPORTER_IMAGE_DIGEST" "$rendered_file")"
[ "$otel_image_count" -eq 1 ] ||
  fail "rendered release must contain one locked telemetry collector image"
[ "$sql_exporter_image_count" -eq 3 ] ||
  fail "rendered release must contain three locked SQL cost exporters"
platform_image_count=$((otel_image_count + sql_exporter_image_count))
expected_total_image_count=$((expected_image_count + platform_image_count))
[ "$image_count" -eq "$expected_total_image_count" ] ||
  fail "rendered $image_count immutable images; expected $expected_image_count release plus $platform_image_count locked platform images"
jq -r --slurpfile matrix "$matrix_file" '
  ($matrix[0].images | map(select(.k3s != false) | .service)) as $k3s_services |
  .images[] |
  select(.service as $service | $k3s_services | index($service)) |
  .ref + "@" + .digest
' "$RELEASE_MANIFEST" |
  while IFS= read -r image_ref; do
    [ "$(grep -Fc "$image_ref" "$rendered_file")" -eq 1 ] ||
      fail "release image must appear exactly once: $image_ref"
  done

grep -Fq "name: $K3S_SECRET_STORE_NAME" "$rendered_file" ||
  fail "provider values do not reference K3S_SECRET_STORE_NAME"
grep -Fq "secretName: $K3S_TLS_SECRET_NAME" "$rendered_file" ||
  fail "provider values do not reference K3S_TLS_SECRET_NAME"
if [ "$K3S_MANAGED_TLS" = "true" ]; then
  grep -Fq "kind: Certificate" "$rendered_file" ||
    fail "managed TLS requires a cert-manager Certificate"
fi

if [ "$OFFLINE_RENDER_ONLY" = "true" ]; then
  echo "K3s immutable release offline render: PASS ($expected_image_count release images + $platform_image_count platform images)"
  exit 0
fi

: "${K3S_DOMAIN:?K3S_DOMAIN is required for online acceptance}"

for dependency in helm kubectl; do
  command -v "$dependency" >/dev/null 2>&1 || fail "missing dependency: $dependency"
done

server_minor="$(kubectl version -o json | jq -r '.serverVersion.minor | sub("[^0-9].*$"; "") | tonumber')"
[ "$server_minor" -ge 29 ] || fail "Kubernetes 1.29 or newer is required"

kubectl get storageclass "$K3S_STORAGE_CLASS" >/dev/null
kubectl get clustersecretstore "$K3S_SECRET_STORE_NAME" -o json |
  jq -e 'any(.status.conditions[]?; .type == "Ready" and .status == "True")' \
    >/dev/null || fail "ClusterSecretStore is not Ready"
for crd in \
  externalsecrets.external-secrets.io \
  scaledobjects.keda.sh \
  triggerauthentications.keda.sh \
  servicemonitors.monitoring.coreos.com \
  prometheusrules.monitoring.coreos.com \
  middlewares.traefik.io; do
  kubectl get crd "$crd" >/dev/null || fail "missing required CRD: $crd"
done
if [ "$K3S_MANAGED_TLS" = "true" ]; then
  kubectl get crd certificates.cert-manager.io >/dev/null ||
    fail "missing required CRD: certificates.cert-manager.io"
fi
if [ "$K3S_MANAGED_TLS" != "true" ]; then
  kubectl get secret "$K3S_TLS_SECRET_NAME" --namespace "$NAMESPACE" \
    -o json |
    jq -e '
      .type == "kubernetes.io/tls" and
      (.data["tls.crt"] | length > 0) and
      (.data["tls.key"] | length > 0)
    ' >/dev/null ||
    fail "pre-provisioned TLS secret is missing or invalid"
fi
kubectl auth can-i create deployments.apps --namespace "$NAMESPACE" | grep -Fxq yes ||
  fail "current Kubernetes identity cannot deploy into $NAMESPACE"

for service in \
  warptalk-postgres-pooler-rw \
  warptalk-redis \
  warptalk-qdrant; do
  kubectl get service "$service" --namespace "$DATA_NAMESPACE" >/dev/null ||
    fail "required data service is unavailable: $DATA_NAMESPACE/$service"
done
kubectl get service warptalk-rabbitmq --namespace "$NAMESPACE" >/dev/null ||
  fail "required messaging service is unavailable: $NAMESPACE/warptalk-rabbitmq"
kubectl get secret warptalk-rabbitmq-default-user --namespace "$NAMESPACE" >/dev/null ||
  fail "RabbitMQ generated credentials are unavailable"
if kubectl get secret "${K3S_RUNTIME_SECRET_NAME:-warptalk-runtime}" \
  --namespace "$NAMESPACE" >/dev/null 2>&1; then
  K3S_NAMESPACE="$NAMESPACE" \
    K3S_RUNTIME_SECRET_NAME="${K3S_RUNTIME_SECRET_NAME:-warptalk-runtime}" \
    "$runtime_secret_check"
fi

previous_revision=""
if helm status "$RELEASE_NAME" --namespace "$NAMESPACE" >/dev/null 2>&1; then
  previous_revision="$(
    helm history "$RELEASE_NAME" --namespace "$NAMESPACE" --output json |
      jq -r '[.[] | select(.status == "deployed")] | last | .revision // empty'
  )"
fi

helm upgrade --install "$RELEASE_NAME" "$chart_dir" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --atomic \
  --wait \
  --timeout 15m \
  -f "$K3S_VALUES_FILE" \
  -f "$override_file"

rollback_release() {
  if [ -n "$previous_revision" ]; then
    helm rollback "$RELEASE_NAME" "$previous_revision" \
      --namespace "$NAMESPACE" \
      --wait \
      --timeout 15m
    return
  fi

  helm uninstall "$RELEASE_NAME" \
    --namespace "$NAMESPACE" \
    --wait \
    --timeout 15m
}

post_deploy_checks() {
  kubectl wait --for=condition=Ready \
    "externalsecret/${K3S_RUNTIME_SECRET_NAME:-warptalk-runtime}" \
    --namespace "$NAMESPACE" \
    --timeout=5m || return 1
  K3S_NAMESPACE="$NAMESPACE" \
    K3S_RUNTIME_SECRET_NAME="${K3S_RUNTIME_SECRET_NAME:-warptalk-runtime}" \
    "$runtime_secret_check" || return 1

  if [ "$K3S_MANAGED_TLS" = "true" ]; then
    kubectl wait --for=condition=Ready \
      "certificate/$K3S_TLS_SECRET_NAME" \
      --namespace "$NAMESPACE" \
      --timeout=5m || return 1
  fi
  kubectl get secret "$K3S_TLS_SECRET_NAME" --namespace "$NAMESPACE" \
    -o json |
    jq -e '
      .type == "kubernetes.io/tls" and
      (.data["tls.crt"] | length > 0) and
      (.data["tls.key"] | length > 0)
    ' >/dev/null || return 1

  RELEASE_MANIFEST="$RELEASE_MANIFEST" \
    K3S_DOMAIN="$K3S_DOMAIN" \
    K3S_NAMESPACE="$NAMESPACE" \
    K3S_DATA_NAMESPACE="$DATA_NAMESPACE" \
    K3S_RUNTIME_SECRET_NAME="${K3S_RUNTIME_SECRET_NAME:-warptalk-runtime}" \
    K3S_TLS_SECRET_NAME="$K3S_TLS_SECRET_NAME" \
    K3S_MANAGED_TLS="$K3S_MANAGED_TLS" \
    "$acceptance_check"
}

if ! post_deploy_checks; then
  echo "K3s release post-deploy acceptance failed; restoring the previous release." >&2
  rollback_release ||
    fail "post-deploy acceptance failed and automatic rollback also failed"
  fail "post-deploy acceptance failed; previous release restored"
fi

echo "K3s immutable release deployed: $(jq -r '.tag' "$RELEASE_MANIFEST")"
