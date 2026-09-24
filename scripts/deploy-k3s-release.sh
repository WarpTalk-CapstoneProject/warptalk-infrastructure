#!/bin/sh
set -eu

: "${RELEASE_MANIFEST:?RELEASE_MANIFEST is required}"
: "${K3S_VALUES_FILE:?K3S_VALUES_FILE is required}"
: "${K3S_STORAGE_CLASS:?K3S_STORAGE_CLASS is required}"
: "${K3S_TLS_SECRET_NAME:?K3S_TLS_SECRET_NAME is required}"

# Where warptalk-runtime comes from:
#   github            - written by the release job from the GitHub `production` environment
#                       (scripts/materialize-k8s-runtime-secrets.sh) before this script runs.
#                       Production uses this; values set secret.externalSecret.enabled: false.
#   external-secrets  - an ExternalSecret against K3S_SECRET_STORE_NAME (a ClusterSecretStore).
K3S_SECRET_SOURCE="${K3S_SECRET_SOURCE:-external-secrets}"
case "$K3S_SECRET_SOURCE" in
  github) ;;
  external-secrets)
    : "${K3S_SECRET_STORE_NAME:?K3S_SECRET_STORE_NAME is required for K3S_SECRET_SOURCE=external-secrets}"
    ;;
  *) echo "K3s release: K3S_SECRET_SOURCE must be github or external-secrets" >&2; exit 1 ;;
esac

OFFLINE_RENDER_ONLY="${OFFLINE_RENDER_ONLY:-false}"
# Server-side dry run: everything up to and including `helm upgrade --dry-run=server`, which the
# API server validates and admits without persisting. Nothing in the cluster changes.
K3S_DRY_RUN="${K3S_DRY_RUN:-false}"
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
helm_locked="$infra_root/scripts/helm-locked.sh"

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

jq --slurpfile matrix "$matrix_file" --arg secretSource "$K3S_SECRET_SOURCE" '
  ($matrix[0].images | map(select(.k3s != false) | .service)) as $k3s_services |
  {
    global: {
      production: true,
      releaseId: .tag
    },
    # The secret source is chosen by the release job, not by the values file.
    secret: {externalSecret: {enabled: ($secretSource == "external-secrets")}},
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

"$helm_locked" template "$RELEASE_NAME" "$chart_dir" \
  --namespace "$NAMESPACE" \
  -f "$K3S_VALUES_FILE" \
  -f "$override_file" >"$rendered_file"

docker run --rm -i "$KUBECONFORM_IMAGE" \
  -strict -summary -ignore-missing-schemas <"$rendered_file"

if grep -Eiq 'CHANGE_ME|replace-with|example\.com|:latest([@"[:space:]]|$)' "$rendered_file"; then
  fail "rendered release contains a placeholder or mutable latest tag"
fi

image_count="$(grep -Ec '^[[:space:]]+image: ".+@sha256:[a-f0-9]{64}"$' "$rendered_file")"
expected_image_count="$(jq '[.images[] | select(.k3s != false)] | length' "$matrix_file")"
otel_image_count="$(grep -Fc "$OTEL_COLLECTOR_IMAGE_DIGEST" "$rendered_file")"
sql_exporter_image_count="$(grep -Fc "$SQL_EXPORTER_IMAGE_DIGEST" "$rendered_file")"
# The document converter is a third-party image like the two above: it is not built from this
# release, so it is pinned in addons.lock.env rather than in the image matrix, and the count below
# has to know about it or every release fails on an image it deliberately added.
gotenberg_image_count="$(grep -Fc "$GOTENBERG_IMAGE_DIGEST" "$rendered_file")"
# Seq, the log and trace store. Optional in the chart, so zero is allowed; more than one is not.
seq_image_count="$(grep -Fc "$SEQ_IMAGE_DIGEST" "$rendered_file" || true)"
[ "$otel_image_count" -eq 1 ] ||
  fail "rendered release must contain one locked telemetry collector image"
[ "$sql_exporter_image_count" -eq 3 ] ||
  fail "rendered release must contain three locked SQL cost exporters"
[ "$gotenberg_image_count" -eq 1 ] ||
  fail "rendered release must contain one locked document converter image"
[ "$seq_image_count" -le 1 ] ||
  fail "rendered release must contain at most one locked Seq image"
platform_image_count=$((otel_image_count + sql_exporter_image_count + gotenberg_image_count + seq_image_count))
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

if [ "$K3S_SECRET_SOURCE" = "external-secrets" ]; then
  grep -Fq "name: $K3S_SECRET_STORE_NAME" "$rendered_file" ||
    fail "provider values do not reference K3S_SECRET_STORE_NAME"
else
  if grep -Fq "kind: ExternalSecret" "$rendered_file"; then
    fail "K3S_SECRET_SOURCE=github but the values still render an ExternalSecret; set secret.externalSecret.enabled: false"
  fi
fi
# The release identity comes from the manifest, never from a values file.
grep -Fq "value: \"$(jq -r '.tag' "$RELEASE_MANIFEST")\"" "$rendered_file" ||
  fail "rendered release does not carry the manifest tag as RELEASE_ID"
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

[ -n "${K3S_DOMAIN:-}" ] || fail "K3S_DOMAIN is required for online acceptance"
# Never the operator's default context: a deploy aimed by accident at whatever cluster
# ~/.kube/config points to is how a laptop deploys production.
# An explicit test, not ${KUBECONFIG:?}: after the EXIT trap above, a failed ${:?} expansion can
# leave some /bin/sh implementations exiting 0.
[ -n "${KUBECONFIG:-}" ] || fail "KUBECONFIG must name the target cluster explicitly"
export KUBECONFIG

command -v kubectl >/dev/null 2>&1 || fail "missing dependency: kubectl"

server_minor="$(kubectl version -o json | jq -r '.serverVersion.minor | sub("[^0-9].*$"; "") | tonumber')"
[ "$server_minor" -ge 29 ] || fail "Kubernetes 1.29 or newer is required"

kubectl get storageclass "$K3S_STORAGE_CLASS" >/dev/null
if [ "$K3S_SECRET_SOURCE" = "external-secrets" ]; then
  kubectl get clustersecretstore "$K3S_SECRET_STORE_NAME" -o json |
    jq -e 'any(.status.conditions[]?; .type == "Ready" and .status == "True")' \
      >/dev/null || fail "ClusterSecretStore is not Ready"
  kubectl get crd externalsecrets.external-secrets.io >/dev/null ||
    fail "missing required CRD: externalsecrets.external-secrets.io"
fi
for crd in \
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

# In a dry run the data platform may legitimately not exist yet (its own dry run created nothing),
# so its absence is reported instead of failing; a real deploy requires all of it.
require_or_note() {
  if [ "$K3S_DRY_RUN" = "true" ]; then
    echo "K3s release (dry run): $* - a real deploy would stop here" >&2
    return 0
  fi
  fail "$*"
}
for service in \
  warptalk-postgres-pooler-rw \
  warptalk-redis \
  warptalk-qdrant; do
  kubectl get service "$service" --namespace "$DATA_NAMESPACE" >/dev/null 2>&1 ||
    require_or_note "required data service is unavailable: $DATA_NAMESPACE/$service"
done
kubectl get service warptalk-rabbitmq --namespace "$NAMESPACE" >/dev/null 2>&1 ||
  require_or_note "required messaging service is unavailable: $NAMESPACE/warptalk-rabbitmq"
kubectl get secret warptalk-rabbitmq-default-user --namespace "$NAMESPACE" >/dev/null 2>&1 ||
  require_or_note "RabbitMQ generated credentials are unavailable"
if [ "$K3S_SECRET_SOURCE" = "github" ] && [ "$K3S_DRY_RUN" = "true" ]; then
  # A dry run does not write the Secret, so whatever is on the cluster is the PREVIOUS one — the
  # very thing this release replaces. materialize-k8s-runtime-secrets.sh already validated the
  # content this release would write against the same contract; checking the old Secret here only
  # fails a dry run on keys the new one adds (first k8s dry run: GOOGLE_CLIENT_ID,
  # SEQ_ADMIN_PASSWORD_HASH), while the real run would pass.
  echo "K3s release (dry run): runtime secret not written (dry run); its content was validated offline" >&2
elif [ "$K3S_SECRET_SOURCE" = "github" ]; then
  # Materialized by the release job before this script; its absence is a job defect, not
  # something to paper over. The pre-install migration hook reads it before any pod starts.
  K3S_NAMESPACE="$NAMESPACE" \
    K3S_RUNTIME_SECRET_NAME="${K3S_RUNTIME_SECRET_NAME:-warptalk-runtime}" \
    "$runtime_secret_check" ||
    fail "runtime secret from the GitHub production environment is missing or invalid"
elif kubectl get secret "${K3S_RUNTIME_SECRET_NAME:-warptalk-runtime}" \
  --namespace "$NAMESPACE" >/dev/null 2>&1; then
  K3S_NAMESPACE="$NAMESPACE" \
    K3S_RUNTIME_SECRET_NAME="${K3S_RUNTIME_SECRET_NAME:-warptalk-runtime}" \
    "$runtime_secret_check"
fi

if [ "$K3S_DRY_RUN" = "true" ]; then
  # The API server admits every rendered object (schemas, CRDs, webhooks, quotas, RBAC for this
  # identity) without persisting anything. Hooks are rendered, not run.
  "$helm_locked" upgrade --install "$RELEASE_NAME" "$chart_dir" \
    --namespace "$NAMESPACE" \
    --dry-run=server \
    -f "$K3S_VALUES_FILE" \
    -f "$override_file" >/dev/null
  echo "K3s immutable release server-side dry run: PASS ($(jq -r '.tag' "$RELEASE_MANIFEST")); nothing was changed"
  exit 0
fi

# Adopt the `warptalk` ServiceAccount. The previous chart revision created it as a Helm HOOK, and
# Helm refuses to take over an existing object that lacks its release ownership metadata, so the
# first upgrade to this chart would otherwise fail with "invalid ownership metadata".
if sa_json="$(kubectl get serviceaccount warptalk --namespace "$NAMESPACE" -o json 2>/dev/null)" &&
  printf '%s\n' "$sa_json" | jq -e '.metadata.annotations["helm.sh/hook"] != null' >/dev/null; then
  kubectl annotate serviceaccount warptalk --namespace "$NAMESPACE" --overwrite \
    "meta.helm.sh/release-name=$RELEASE_NAME" "meta.helm.sh/release-namespace=$NAMESPACE" \
    helm.sh/hook- helm.sh/hook-weight- helm.sh/hook-delete-policy- >/dev/null
  kubectl label serviceaccount warptalk --namespace "$NAMESPACE" --overwrite \
    app.kubernetes.io/managed-by=Helm >/dev/null
  echo "K3s release: adopted the former hook ServiceAccount warptalk into release $RELEASE_NAME"
fi

previous_revision=""
if "$helm_locked" status "$RELEASE_NAME" --namespace "$NAMESPACE" >/dev/null 2>&1; then
  previous_revision="$(
    "$helm_locked" history "$RELEASE_NAME" --namespace "$NAMESPACE" --output json |
      jq -r '[.[] | select(.status == "deployed")] | last | .revision // empty'
  )"
fi

"$helm_locked" upgrade --install "$RELEASE_NAME" "$chart_dir" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --atomic \
  --wait \
  --timeout 15m \
  -f "$K3S_VALUES_FILE" \
  -f "$override_file"

rollback_release() {
  if [ -n "$previous_revision" ]; then
    "$helm_locked" rollback "$RELEASE_NAME" "$previous_revision" \
      --namespace "$NAMESPACE" \
      --wait \
      --timeout 15m
    return
  fi

  "$helm_locked" uninstall "$RELEASE_NAME" \
    --namespace "$NAMESPACE" \
    --wait \
    --timeout 15m
}

post_deploy_checks() {
  if [ "$K3S_SECRET_SOURCE" = "external-secrets" ]; then
    kubectl wait --for=condition=Ready \
      "externalsecret/${K3S_RUNTIME_SECRET_NAME:-warptalk-runtime}" \
      --namespace "$NAMESPACE" \
      --timeout=5m || return 1
  fi
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
    K3S_SECRET_SOURCE="$K3S_SECRET_SOURCE" \
    "$acceptance_check"
}

if ! post_deploy_checks; then
  echo "K3s release post-deploy acceptance failed; restoring the previous release." >&2
  rollback_release ||
    fail "post-deploy acceptance failed and automatic rollback also failed"
  fail "post-deploy acceptance failed; previous release restored"
fi

echo "K3s immutable release deployed: $(jq -r '.tag' "$RELEASE_MANIFEST")"
