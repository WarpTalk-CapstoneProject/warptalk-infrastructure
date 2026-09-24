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
# Always the locked Helm. K3S_HELM_COMMAND exists only so scripts/test-k3s-release-gate.sh can put
# a recording stub in front of it; the release job never sets it.
helm_locked="${K3S_HELM_COMMAND:-$infra_root/scripts/helm-locked.sh}"

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
migration_file="$(mktemp "${TMPDIR:-/tmp}/warptalk-k3s-migrations.XXXXXX")"
# The rollout shape for this one release (see choose_rollout_mode); empty means the chart default.
rollout_file="$(mktemp "${TMPDIR:-/tmp}/warptalk-k3s-rollout.XXXXXX")"
printf '{}\n' >"$rollout_file"
capacity_nodes_file="$(mktemp "${TMPDIR:-/tmp}/warptalk-k3s-nodes.XXXXXX")"
capacity_pods_file="$(mktemp "${TMPDIR:-/tmp}/warptalk-k3s-pods.XXXXXX")"
trap 'rm -f "$override_file" "$rendered_file" "$migration_file" "$rollout_file" "$capacity_nodes_file" "$capacity_pods_file"' EXIT INT TERM

jq --slurpfile matrix "$matrix_file" --arg secretSource "$K3S_SECRET_SOURCE" '
  ($matrix[0].images | map(select(.k3s != false) | .service)) as $k3s_services |
  {
    global: {
      production: true,
      releaseId: .tag
    },
    # The secret source is chosen by the release job, not by the values file.
    secret: {externalSecret: {enabled: ($secretSource == "external-secrets")}},
    # This script owns the migrations: it runs them as a gated step BEFORE `helm upgrade`
    # (run_migration_gate below), so the release itself never carries a migration hook.
    migrations: {mode: "external"},
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

# The migration gate: the migrator ServiceAccount and Job as plain objects, applied and awaited by
# run_migration_gate before `helm upgrade` touches anything. Rendered from the same chart, values
# and manifest as the release, and validated with it below (the migrator image is counted there).
"$helm_locked" template "$RELEASE_NAME" "$chart_dir" \
  --namespace "$NAMESPACE" \
  -f "$K3S_VALUES_FILE" \
  -f "$override_file" \
  --set migrations.mode=job \
  --show-only templates/migration-job.yaml >"$migration_file"
if grep -Eq '^  name: warptalk-migrations-' "$rendered_file"; then
  fail "the release renders a migration Job; migrations must run as the gate before the upgrade, not as a hook inside it"
fi
migration_job="$(awk '/^kind: Job$/ { job = 1 } job && /^  name: / { print $2; exit }' "$migration_file")"
case "$migration_job" in
  warptalk-migrations-?*) ;;
  *) fail "could not render the migration Job" ;;
esac
{
  printf '%s\n' '---'
  cat "$migration_file"
} >>"$rendered_file"

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
  # identity) without persisting anything, the migration gate's Job included.
  kubectl apply --dry-run=server --namespace "$NAMESPACE" -f "$migration_file" >/dev/null
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

# ---------------------------------------------------------------------------------------------
# Where a failure goes back to: the last revision Helm marked DEPLOYED, captured before anything
# changes. Never "the previous revision": after a failed upgrade that is a FAILED revision, and
# rolling back to it (what `--atomic` and `helm rollback` without a number do) re-applies a
# manifest that never fully existed - on 24 Sep that hit PodDisruptionBudgets the failed revision
# had never created, and the rollback itself failed.
# ---------------------------------------------------------------------------------------------
previous_revision=""
if "$helm_locked" status "$RELEASE_NAME" --namespace "$NAMESPACE" >/dev/null 2>&1; then
  history_json="$("$helm_locked" history "$RELEASE_NAME" --namespace "$NAMESPACE" --output json)"
  previous_revision="$(printf '%s\n' "$history_json" |
    jq -r '[.[] | select(.status == "deployed")] | last | .revision // empty')"
  latest_status="$(printf '%s\n' "$history_json" | jq -r 'last | .status // empty')"
  case "$latest_status" in
    pending-*)
      # An interrupted run (a cancelled job, a lost runner) or someone else's live operation.
      # Helm refuses to upgrade over it either way; which of the two it is only a human can say.
      fail "release $RELEASE_NAME is $latest_status. If no other deploy is running, restore the last deployed revision first: helm rollback $RELEASE_NAME ${previous_revision:-<none>} --namespace $NAMESPACE --wait --timeout 15m"
      ;;
  esac
  [ -n "$previous_revision" ] ||
    fail "release $RELEASE_NAME has no DEPLOYED revision to return to; refusing to upgrade without a rollback target"
fi

rollback_release() {
  if [ -n "$previous_revision" ]; then
    echo "K3s release: rolling back to the last DEPLOYED revision $previous_revision" >&2
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

# ---------------------------------------------------------------------------------------------
# Step 1: migrations, as a hard gate. A plain Job, applied and awaited HERE, before the upgrade:
# if it fails, the release stops with nothing rolled - the running pods keep the schema they
# were built for. (As a pre-upgrade hook under `--atomic` a failure still left new images running
# on an unmigrated schema, 24 Sep.) The runner records every applied file and skips it next time,
# so re-running the gate for the same release is harmless. Migrations are additive: a later
# rollback of the images leaves the schema where it is, and the previous images run against it.
# ---------------------------------------------------------------------------------------------
print_migration_logs() {
  kubectl logs "job/$migration_job" --namespace "$NAMESPACE" --all-containers --tail=200 >&2 ||
    echo "K3s release: (no migration logs available)" >&2
}

run_migration_gate() {
  kubectl delete job "$migration_job" --namespace "$NAMESPACE" \
    --ignore-not-found --wait=true >/dev/null || return 1
  kubectl apply --namespace "$NAMESPACE" -f "$migration_file" >/dev/null || return 1
  echo "K3s release: migration gate $migration_job started"
  # The Job's activeDeadlineSeconds (900) marks it Failed first; this is the backstop.
  deadline=$(($(date +%s) + 960))
  while :; do
    job_json="$(kubectl get job "$migration_job" --namespace "$NAMESPACE" -o json)" || return 1
    if printf '%s\n' "$job_json" | jq -e '(.status.succeeded // 0) >= 1' >/dev/null; then
      echo "K3s release: migration gate $migration_job succeeded"
      return 0
    fi
    if printf '%s\n' "$job_json" |
      jq -e 'any(.status.conditions[]?; .type == "Failed" and .status == "True")' >/dev/null; then
      print_migration_logs
      return 1
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      print_migration_logs
      return 1
    fi
    sleep 5
  done
}

# ---------------------------------------------------------------------------------------------
# Step 2: the rollout shape. Surge (new pod Ready before the old one goes) is the only shape with
# no unavailability, and it needs room for one more pod on the App node. Measured, not assumed:
# when no App node can fit one more pod of the largest workload in this release, surging would
# leave that pod Pending and time the release out (v220), so this ONE release replaces pods in
# place instead - every user-facing service keeps its other replica serving - and says so.
# K3S_ROLLOUT_MODE=surge|in-place forces either.
# ---------------------------------------------------------------------------------------------
K3S_ROLLOUT_MODE="${K3S_ROLLOUT_MODE:-auto}"
K3S_APP_NODE_SELECTOR="${K3S_APP_NODE_SELECTOR:-node.warptalk.io/role=app}"

# The largest per-pod request (memory MiB, CPU millicores) among the release's Deployments.
largest_release_pod() {
  awk '
    function mib(v) {
      gsub(/"/, "", v)
      if (v ~ /Ki$/) return substr(v, 1, length(v) - 2) / 1024
      if (v ~ /Mi$/) return substr(v, 1, length(v) - 2) + 0
      if (v ~ /Gi$/) return substr(v, 1, length(v) - 2) * 1024
      return v / 1048576
    }
    function milli(v) {
      gsub(/"/, "", v)
      if (v ~ /m$/) return substr(v, 1, length(v) - 1) + 0
      return v * 1000
    }
    /^kind: / { kind = $2 }
    /^[[:space:]]+requests:$/ { inreq = (kind == "Deployment"); next }
    /^[[:space:]]+limits:$/ { inreq = 0 }
    inreq && $1 == "memory:" { m = mib($2); if (m > mem) mem = m }
    inreq && $1 == "cpu:" { c = milli($2); if (c > cpu) cpu = c }
    END { printf "%d %d\n", mem, cpu }
  ' "$rendered_file"
}

# The most free memory (MiB) and CPU (m) left by requests on any single App node.
app_node_headroom() {
  # Files, not --argjson: the cluster's pod list is larger than an argument may be.
  kubectl get nodes -l "$K3S_APP_NODE_SELECTOR" -o json >"$capacity_nodes_file" || return 1
  kubectl get pods --all-namespaces \
    --field-selector 'status.phase!=Succeeded,status.phase!=Failed' -o json \
    >"$capacity_pods_file" || return 1
  jq -rn --slurpfile nodes_doc "$capacity_nodes_file" --slurpfile pods_doc "$capacity_pods_file" '
    def q:
      if . == null then 0 else tostring |
        if test("^[0-9.]+m$") then (.[:-1] | tonumber) / 1000
        elif test("Ki$") then (.[:-2] | tonumber) * 1024
        elif test("Mi$") then (.[:-2] | tonumber) * 1048576
        elif test("Gi$") then (.[:-2] | tonumber) * 1073741824
        elif test("k$") then (.[:-1] | tonumber) * 1000
        elif test("M$") then (.[:-1] | tonumber) * 1000000
        elif test("G$") then (.[:-1] | tonumber) * 1000000000
        else tonumber end
      end;
    def podreq($r):
      [([.spec.containers[]?.resources.requests[$r] | q] | add // 0),
       ([.spec.initContainers[]?.resources.requests[$r] | q] | max // 0)] | max;
    $nodes_doc[0] as $nodes | $pods_doc[0] as $pods |
    [ $nodes.items[] | .metadata.name as $node |
      {
        mem: ((.status.allocatable.memory | q) -
              ([$pods.items[] | select(.spec.nodeName == $node) | podreq("memory")] | add // 0)),
        cpu: ((.status.allocatable.cpu | q) -
              ([$pods.items[] | select(.spec.nodeName == $node) | podreq("cpu")] | add // 0))
      }
    ] |
    if length == 0 then "0 0"
    else (max_by(.mem) | "\((.mem / 1048576) | floor) \((.cpu * 1000) | floor)") end
  '
}

choose_rollout_mode() {
  case "$K3S_ROLLOUT_MODE" in
    surge) mode=surge ;;
    in-place) mode=in-place ;;
    auto)
      largest="$(largest_release_pod)"
      need_mem="${largest% *}"
      need_cpu="${largest#* }"
      headroom="$(app_node_headroom)" || fail "could not measure App-node headroom"
      free_mem="${headroom% *}"
      free_cpu="${headroom#* }"
      echo "K3s release: App-node headroom ${free_mem}Mi / ${free_cpu}m; largest pod in this release ${need_mem}Mi / ${need_cpu}m"
      if [ "$free_mem" -ge "$need_mem" ] && [ "$free_cpu" -ge "$need_cpu" ]; then
        mode=surge
      else
        mode=in-place
      fi
      ;;
    *) fail "K3S_ROLLOUT_MODE must be auto, surge or in-place" ;;
  esac
  if [ "$mode" = "in-place" ]; then
    cat >"$rollout_file" <<'EOF'
rollout:
  multiReplica: {maxSurge: 0, maxUnavailable: 1}
  singleReplica: {maxSurge: 0, maxUnavailable: 1}
EOF
    echo "::warning::K3s release: the App node cannot fit one more pod of the largest workload, so this release replaces pods IN PLACE (surge 0 / unavailable 1). Multi-replica services keep serving from their other replica; single-replica workers restart. Free App-node memory to restore surge rollouts."
  else
    echo "K3s release: surge rollout (maxSurge 1 / maxUnavailable 0)"
  fi
}

if ! run_migration_gate; then
  fail "migration gate $migration_job failed; nothing was rolled, the running release is untouched"
fi

choose_rollout_mode

# ---------------------------------------------------------------------------------------------
# Step 3: the upgrade. `--wait` (every Deployment rolled out and Ready), not `--atomic`: on failure
# this script rolls back itself, explicitly, to the revision captured above.
# ---------------------------------------------------------------------------------------------
if ! "$helm_locked" upgrade --install "$RELEASE_NAME" "$chart_dir" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --wait \
  --timeout 15m \
  -f "$K3S_VALUES_FILE" \
  -f "$override_file" \
  -f "$rollout_file"; then
  echo "K3s release: helm upgrade failed; restoring the last deployed release." >&2
  rollback_release ||
    fail "helm upgrade failed and the rollback to revision ${previous_revision:-<none>} also failed"
  fail "helm upgrade failed; restored revision ${previous_revision:-<none>} (migrations stay applied; they are additive)"
fi

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
