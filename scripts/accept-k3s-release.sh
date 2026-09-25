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
SECRET_SOURCE="${K3S_SECRET_SOURCE:-external-secrets}"
# The nodes application pods are pinned to (placement.nodeSelector in the values). Replicas are
# expected to spread over as many of these as there are replicas; with one App node that is one.
APP_NODE_SELECTOR="${K3S_APP_NODE_SELECTOR:-node.warptalk.io/role=app}"
ROLLOUT_TIMEOUT="${K3S_ROLLOUT_TIMEOUT:-300s}"
REPORT="${K3S_ACCEPTANCE_REPORT:-${TMPDIR:-/tmp}/warptalk-k3s-acceptance.json}"

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
infra_root="$(CDPATH='' cd -- "$script_dir/.." && pwd)"
matrix="$infra_root/deploy/production/image-matrix.json"
lock_file="$infra_root/deploy/k3s/addons.lock.env"

fail() {
  echo "K3s acceptance: $*" >&2
  exit 1
}

: "${KUBECONFIG:?KUBECONFIG must name the target cluster explicitly}"
export KUBECONFIG

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

# Every minimum below is the one the chart itself asks for, read back from the object the chart
# created - never a number lowered until the gate passes. The previous version defaulted each of
# them to 1 and swallowed `kubectl rollout status` with `|| true`, so it accepted any release in
# which at least one pod of everything existed.

# CloudNativePG: every instance the Cluster asks for is ready, and it asks for at least two
# (k8s-data-values.yaml: a primary and a standby).
kubectl get cluster warptalk-postgres --namespace "$DATA_NAMESPACE" -o json |
  jq -e '
    (.spec.instances // 0) >= 2 and
    (.status.readyInstances // 0) == .spec.instances and
    any(.status.conditions[]?; .type == "Ready" and .status == "True")
  ' >/dev/null || fail "CloudNativePG does not have all of its (at least two) instances Ready"

kubectl get pooler warptalk-postgres-pooler-rw \
  --namespace "$DATA_NAMESPACE" -o json |
  jq -e '(.status.phase | ascii_downcase) == "active"' >/dev/null ||
  fail "CloudNativePG PgBouncer Pooler is not active"

kubectl get rabbitmqcluster warptalk-rabbitmq --namespace "$NAMESPACE" -o json |
  jq -e '
    (.spec.replicas // 0) >= 1 and
    any(.status.conditions[]?; .type == "AllReplicasReady" and .status == "True")
  ' >/dev/null || fail "RabbitMQ does not have all of its replicas ready"

# Redis runs one sentinel per node with quorum 2. Production runs TWO nodes (infra #216: the Data
# node could not hold a third), which keeps a replica of every key but cannot elect a new master if
# one node is lost. That is a known, accepted gap, so it is a warning here, not a failure: v224 was
# rolled back only because this line still demanded three after #216 made it two.
redis_json="$(kubectl get statefulset warptalk-redis-node --namespace "$DATA_NAMESPACE" -o json)"
printf '%s\n' "$redis_json" | jq -e '
    (.spec.replicas // 0) >= 2 and
    (.status.readyReplicas // 0) == .spec.replicas
  ' >/dev/null || fail "Redis does not have all of its (at least two) nodes ready"
printf '%s\n' "$redis_json" | jq -e '(.spec.replicas // 0) >= 3' >/dev/null ||
  echo "::warning::K3s acceptance: Redis runs $(printf '%s\n' "$redis_json" | jq '.spec.replicas') nodes; sentinel quorum 2 cannot fail over until it has three"
kubectl get statefulset warptalk-qdrant --namespace "$DATA_NAMESPACE" -o json |
  jq -e '
    (.spec.replicas // 0) >= 1 and
    (.status.readyReplicas // 0) == .spec.replicas
  ' >/dev/null || fail "warptalk-qdrant does not have all replicas ready"

app_nodes="$(kubectl get nodes --selector "$APP_NODE_SELECTOR" -o json | jq '
  [.items[] |
    select(.spec.unschedulable != true) |
    select(any(.status.conditions[]; .type == "Ready" and .status == "True"))
  ] | length
')"
[ "$app_nodes" -ge 1 ] || app_nodes="$ready_nodes"

hpas_json="$(kubectl get hpa --namespace "$NAMESPACE" -o json)"
scaled_objects_json="$(kubectl get scaledobjects.keda.sh --namespace "$NAMESPACE" -o json)"

jq -r --slurpfile matrix "$matrix" '
  ($matrix[0].images | map(select(.k3s != false) | .service)) as $k3s_services |
  .images[] |
  select(.service != "migrator") |
  select(.service as $service | $k3s_services | index($service)) |
  [.service, (.ref + "@" + .digest)] | @tsv
' "$RELEASE_MANIFEST" |
  while IFS="$(printf '\t')" read -r service expected_image; do
    kubectl rollout status deployment "$service" --namespace "$NAMESPACE" \
      --timeout="$ROLLOUT_TIMEOUT" >/dev/null ||
      fail "$service did not finish rolling out within $ROLLOUT_TIMEOUT"
    deployment="$(kubectl get deployment "$service" --namespace "$NAMESPACE" -o json)"
    # The floor this workload was deployed with: its HPA minimum, else its KEDA minimum, else the
    # static replica count the chart rendered (1 only for declared singletons).
    minimum="$(jq -n \
      --arg service "$service" \
      --argjson deployment "$deployment" \
      --argjson hpas "$hpas_json" \
      --argjson scaled "$scaled_objects_json" '
        ([$hpas.items[] | select(.spec.scaleTargetRef.name == $service and
            (.metadata.ownerReferences // [] | map(.kind) | index("ScaledObject") | not))
          | .spec.minReplicas // 1] | first) //
        ([$scaled.items[] | select(.spec.scaleTargetRef.name == $service)
          | .spec.minReplicaCount // 1] | first) //
        ($deployment.spec.replicas // 1)
      ')"
    printf '%s\n' "$deployment" | jq -e --argjson min "$minimum" '
      (.spec.replicas // 0) >= $min and
      (.status.availableReplicas // 0) == .spec.replicas and
      (.status.updatedReplicas // 0) == .spec.replicas
    ' >/dev/null || fail "$service is not fully available at its minimum of $minimum replica(s)"
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
    replicas="$(printf '%s\n' "$deployment" | jq '.spec.replicas // 1')"
    expected_spread="$app_nodes"
    [ "$replicas" -ge "$expected_spread" ] || expected_spread="$replicas"
    [ "$pod_nodes" -ge "$expected_spread" ] ||
      fail "$service Ready replicas are on $pod_nodes node(s); expected $expected_spread"
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

if [ "$SECRET_SOURCE" = "external-secrets" ]; then
  kubectl get "externalsecret/$RUNTIME_SECRET_NAME" --namespace "$NAMESPACE" -o json |
    jq -e 'any(.status.conditions[]?; .type == "Ready" and .status == "True")' \
      >/dev/null || fail "externalsecret/$RUNTIME_SECRET_NAME is not Ready"
fi
for resource in \
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

# Traefik runs host ports on the App node (traefik-values.yaml), fronted in-VPC by a
# LoadBalancer Service. Traefik is installed by the cluster bootstrap, not by a release, so its
# configuration checks apply once it runs the locked values (recognisable by the HTTP->HTTPS
# redirect those values add); before that the report says so instead of pretending.
traefik_service="$(kubectl get service traefik --namespace traefik -o json)"
traefik_ingress="$(printf '%s\n' "$traefik_service" |
  jq -r '.status.loadBalancer.ingress[0].ip // .status.loadBalancer.ingress[0].hostname // .spec.externalIPs[0] // empty')"
traefik_deployment="$(kubectl get deployment traefik --namespace traefik -o json)"
printf '%s\n' "$traefik_deployment" | jq -e '
  (.spec.replicas // 0) >= 1 and (.status.availableReplicas // 0) == .spec.replicas
' >/dev/null || fail "Traefik does not have all of its replicas available"
traefik_config="locked"
if printf '%s\n' "$traefik_deployment" |
  jq -e '[.spec.template.spec.containers[].args[]?] | any(test("redirections.entryPoint.to"))' >/dev/null; then
  printf '%s\n' "$traefik_service" | jq -e '.spec.externalTrafficPolicy == "Local"' >/dev/null ||
    fail "Traefik must preserve the client address (externalTrafficPolicy: Local)"
else
  traefik_config="not yet on deploy/k3s/traefik-values.yaml (run the cluster bootstrap in deploy/k3s/README.md)"
  echo "K3s acceptance: WARNING Traefik is $traefik_config; redirect and client-IP checks deferred" >&2
fi

public_checks="pass"
[ -n "$traefik_ingress" ] || fail "Traefik has neither an externalIP nor a LoadBalancer address"
if [ "$traefik_config" = "locked" ]; then
  if ! redirect_status="$(curl --silent --output /dev/null --write-out '%{http_code}' "http://$K3S_DOMAIN/")"; then
    fail "plain HTTP probe of $K3S_DOMAIN failed"
  fi
  case "$redirect_status" in
    301|308) ;;
    *) fail "plain HTTP must redirect to HTTPS (got $redirect_status)" ;;
  esac
fi
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
  --arg public "$public_checks" \
  --arg traefik "$traefik_config" \
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
      rollouts: "pass",
      httpsRedirect: (if $traefik == "locked" then $public else $traefik end),
      immutableImages: "pass",
      migrations: "pass",
      runtimeSecrets: "pass",
      keda: "pass",
      telemetry: "pass",
      tlsAndHeaders: $public
    }
  }' >"$REPORT"

echo "K3s acceptance: PASS; report written to $REPORT"
