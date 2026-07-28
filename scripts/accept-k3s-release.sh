#!/bin/sh
# Read-only acceptance gate for a deployed WarpTalk HA release.
set -eu

: "${RELEASE_MANIFEST:?RELEASE_MANIFEST is required}"
: "${K3S_DOMAIN:?K3S_DOMAIN is required}"

NAMESPACE="${K3S_NAMESPACE:-warptalk}"
DATA_NAMESPACE="${K3S_DATA_NAMESPACE:-warptalk-data}"
REQUIRE_DISTINCT_ZONES="${K3S_REQUIRE_DISTINCT_ZONES:-true}"
RUNTIME_SECRET_NAME="${K3S_RUNTIME_SECRET_NAME:-warptalk-runtime}"
TLS_SECRET_NAME="${K3S_TLS_SECRET_NAME:-warptalk-tls}"
MANAGED_TLS="${K3S_MANAGED_TLS:-true}"
REPORT="${K3S_ACCEPTANCE_REPORT:-${TMPDIR:-/tmp}/warptalk-k3s-acceptance.json}"

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
infra_root="$(CDPATH='' cd -- "$script_dir/.." && pwd)"
matrix="$infra_root/deploy/production/image-matrix.json"
lock_file="$infra_root/deploy/k3s/addons.lock.env"

fail() {
  echo "K3s acceptance: $*" >&2
  exit 1
}

for dependency in kubectl jq curl; do
  command -v "$dependency" >/dev/null 2>&1 ||
    fail "missing dependency: $dependency"
done
test -r "$RELEASE_MANIFEST" || fail "cannot read release manifest"
test -r "$lock_file" || fail "cannot read add-on lock"

# shellcheck disable=SC1090
. "$lock_file"

jq -e --slurpfile matrix "$matrix" '
  .schemaVersion == 1 and
  ([.images[].service] | sort) == ([$matrix[0].images[].service] | sort) and
  all(.images[]; .digest | test("^sha256:[a-f0-9]{64}$"))
' "$RELEASE_MANIFEST" >/dev/null ||
  fail "release manifest does not match the canonical image matrix"

nodes_json="$(kubectl get nodes -o json)"
ready_nodes="$(printf '%s\n' "$nodes_json" | jq '
  [.items[] |
    select(.spec.unschedulable != true) |
    select(any(.status.conditions[]; .type == "Ready" and .status == "True"))
  ] | length
')"
[ "$ready_nodes" -ge 3 ] || fail "fewer than three schedulable Ready nodes"

zone_count="$(printf '%s\n' "$nodes_json" | jq '
  [.items[] |
    select(.spec.unschedulable != true) |
    select(any(.status.conditions[]; .type == "Ready" and .status == "True")) |
    .metadata.labels["topology.kubernetes.io/zone"] // empty
  ] | unique | length
')"
if [ "$REQUIRE_DISTINCT_ZONES" = "true" ]; then
  [ "$zone_count" -ge 3 ] ||
    fail "fewer than three distinct topology.kubernetes.io/zone values"
fi

kubectl get cluster warptalk-postgres --namespace "$DATA_NAMESPACE" -o json |
  jq -e '
    (.status.readyInstances // 0) >= 3 and
    any(.status.conditions[]?; .type == "Ready" and .status == "True")
  ' >/dev/null || fail "CloudNativePG is not three-instance Ready"

kubectl get pooler warptalk-postgres-pooler-rw \
  --namespace "$DATA_NAMESPACE" -o json |
  jq -e '(.status.phase | ascii_downcase) == "active"' >/dev/null ||
  fail "CloudNativePG PgBouncer Pooler is not active"

kubectl get rabbitmqcluster warptalk-rabbitmq --namespace "$NAMESPACE" -o json |
  jq -e '
    .spec.replicas == 3 and
    any(.status.conditions[]?; .type == "AllReplicasReady" and .status == "True")
  ' >/dev/null || fail "RabbitMQ quorum is not ready"

for stateful_set in warptalk-redis-node warptalk-qdrant; do
  kubectl get statefulset "$stateful_set" --namespace "$DATA_NAMESPACE" -o json |
    jq -e '
      (.spec.replicas // 0) >= 3 and
      (.status.readyReplicas // 0) == .spec.replicas
    ' >/dev/null || fail "$stateful_set does not have all replicas ready"
done

jq -r '.images[] | select(.service != "migrator") | [.service, (.ref + "@" + .digest)] | @tsv' \
  "$RELEASE_MANIFEST" |
  while IFS="$(printf '\t')" read -r service expected_image; do
    deployment="$(kubectl get deployment "$service" --namespace "$NAMESPACE" -o json)"
    printf '%s\n' "$deployment" | jq -e '
      (.spec.replicas // 0) >= 2 and
      (.status.availableReplicas // 0) == .spec.replicas and
      (.status.updatedReplicas // 0) == .spec.replicas
    ' >/dev/null || fail "$service rollout is not fully available"
    actual_image="$(printf '%s\n' "$deployment" |
      jq -r --arg name "$service" \
        '.spec.template.spec.containers[] | select(.name == $name) | .image')"
    [ "$actual_image" = "$expected_image" ] ||
      fail "$service is not running its release-manifest digest"
    pod_nodes="$(kubectl get pods --namespace "$NAMESPACE" \
      --selector "app.kubernetes.io/name=$service" -o json |
      jq '
        [.items[] |
          select(.status.phase == "Running") |
          select(all(.status.containerStatuses[]?; .ready == true)) |
          .spec.nodeName
        ] | unique | length
      ')"
    [ "$pod_nodes" -ge 2 ] ||
      fail "$service Ready replicas are not spread across at least two nodes"
  done

collector_image="$(kubectl get deployment warptalk-otel-collector \
  --namespace "$NAMESPACE" \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="collector")].image}')"
case "$collector_image" in
  *"@$OTEL_COLLECTOR_IMAGE_DIGEST") ;;
  *) fail "OpenTelemetry Collector is not running the locked digest" ;;
esac

latest_migration_job="$(kubectl get jobs --namespace "$NAMESPACE" -o json |
  jq -r '
    [.items[] | select(.metadata.name | startswith("warptalk-migrations-"))] |
    sort_by(.metadata.creationTimestamp) | last | .metadata.name // empty
  ')"
[ -n "$latest_migration_job" ] || fail "no retained migration Job evidence"
kubectl get job "$latest_migration_job" --namespace "$NAMESPACE" -o json |
  jq -e '(.status.succeeded // 0) == 1' >/dev/null ||
  fail "latest migration Job did not succeed"
migration_image="$(kubectl get job "$latest_migration_job" \
  --namespace "$NAMESPACE" \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="migrator")].image}')"
expected_migration_image="$(jq -r '
  .images[] | select(.service == "migrator") | .ref + "@" + .digest
' "$RELEASE_MANIFEST")"
[ "$migration_image" = "$expected_migration_image" ] ||
  fail "migration Job did not run the release-manifest digest"

for resource in \
  "externalsecret/$RUNTIME_SECRET_NAME" \
  "scaledobject/stt-worker-queue-lag" \
  "scaledobject/translation-worker-queue-lag" \
  "scaledobject/tts-worker-queue-lag"; do
  kubectl get "$resource" --namespace "$NAMESPACE" -o json |
    jq -e 'any(.status.conditions[]?; .type == "Ready" and .status == "True")' \
      >/dev/null || fail "$resource is not Ready"
done
if [ "$MANAGED_TLS" = "true" ]; then
  kubectl get "certificate/$TLS_SECRET_NAME" --namespace "$NAMESPACE" -o json |
    jq -e 'any(.status.conditions[]?; .type == "Ready" and .status == "True")' \
      >/dev/null || fail "certificate/$TLS_SECRET_NAME is not Ready"
fi
kubectl get secret "$TLS_SECRET_NAME" --namespace "$NAMESPACE" -o json |
  jq -e '
    .type == "kubernetes.io/tls" and
    (.data["tls.crt"] | length > 0) and
    (.data["tls.key"] | length > 0)
  ' >/dev/null || fail "TLS Secret is missing or invalid"
K3S_NAMESPACE="$NAMESPACE" \
  K3S_RUNTIME_SECRET_NAME="$RUNTIME_SECRET_NAME" \
  "$script_dir/check-k3s-runtime-secret.sh" >/dev/null

kubectl get servicemonitor warptalk-otel-collector \
  --namespace "$NAMESPACE" >/dev/null ||
  fail "OpenTelemetry ServiceMonitor is missing"
kubectl get servicemonitor metrics-exporter \
  --namespace "$NAMESPACE" >/dev/null ||
  fail "Redis stream metrics ServiceMonitor is missing"
kubectl get prometheusrule warptalk \
  --namespace "$NAMESPACE" >/dev/null ||
  fail "WarpTalk Prometheus alert rules are missing"
kubectl get prometheusrule warptalk-cost \
  --namespace "$NAMESPACE" >/dev/null ||
  fail "WarpTalk cost alert rules are missing"
for exporter in billing-cost-exporter livekit-cost-exporter workspace-storage-exporter; do
  kubectl get servicemonitor "$exporter" --namespace "$NAMESPACE" >/dev/null ||
    fail "$exporter ServiceMonitor is missing"
  kubectl get deployment "$exporter" --namespace "$NAMESPACE" -o json |
    jq -e '
      (.status.availableReplicas // 0) >= 1 and
      (.status.updatedReplicas // 0) >= 1
    ' >/dev/null || fail "$exporter is not available"
done
kubectl get configmap warptalk-grafana-dashboard \
  --namespace monitoring >/dev/null ||
  fail "WarpTalk Grafana dashboard is missing"

traefik_ingress="$(kubectl get service traefik --namespace traefik -o json |
  jq -r '.status.loadBalancer.ingress[0].ip // .status.loadBalancer.ingress[0].hostname // empty')"
[ -n "$traefik_ingress" ] || fail "Traefik has no external LoadBalancer address"

headers="$(curl --fail --silent --show-error --head "https://$K3S_DOMAIN/")" ||
  fail "public HTTPS frontend probe failed"
printf '%s\n' "$headers" | grep -Eiq '^strict-transport-security:' ||
  fail "public response is missing HSTS"
printf '%s\n' "$headers" | grep -Eiq '^x-content-type-options:[[:space:]]*nosniff' ||
  fail "public response is missing X-Content-Type-Options"

jq -n \
  --arg acceptedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg release "$(jq -r '.tag' "$RELEASE_MANIFEST")" \
  --arg domain "$K3S_DOMAIN" \
  --arg loadBalancer "$traefik_ingress" \
  --argjson readyNodes "$ready_nodes" \
  --argjson zones "$zone_count" \
  '{
    schemaVersion: 1,
    acceptedAt: $acceptedAt,
    release: $release,
    domain: $domain,
    loadBalancer: $loadBalancer,
    readyNodes: $readyNodes,
    distinctZones: $zones,
    checks: {
      dataQuorum: "pass",
      immutableImages: "pass",
      migrations: "pass",
      externalSecrets: "pass",
      keda: "pass",
      telemetry: "pass",
      tlsAndHeaders: "pass"
    }
  }' >"$REPORT"

echo "K3s acceptance: PASS; report written to $REPORT"
