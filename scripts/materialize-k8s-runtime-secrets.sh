#!/usr/bin/env bash
# Write every Kubernetes runtime secret from ONE source: the GitHub `production` environment.
#
#   K8S_RUNTIME_ENV_FILE  a KEY=VALUE file - the content of the GitHub secret K8S_RUNTIME_ENV,
#                         written to a 0600 file by the release job. Template with every key:
#                         deploy/k3s/runtime-env.template.
#   Overlay variables     the individual GitHub secrets/vars the compose release already passes
#                         (Stripe, LiveKit, Google, Cartesia). A non-empty overlay wins over the
#                         same key in the file, so a value rotated in GitHub reaches both runtimes.
#
# Secrets written (server-side apply, field manager warptalk-release):
#   warptalk/warptalk-runtime                 every key; validated by check-k3s-runtime-secret.sh
#                                             BEFORE anything is applied
#   warptalk-data/warptalk-postgres-superuser PGUSER / PGPASSWORD (basic-auth, CloudNativePG)
#   warptalk-data/warptalk-backup-credentials BACKUP_S3_ACCESS_KEY_ID / _SECRET_ACCESS_KEY / _ENDPOINT_URL
#   warptalk-data/warptalk-redis-auth         REDIS_PASSWORD
#   warptalk-data/warptalk-qdrant-auth        VECTOR_DB_API_KEY
#   monitoring/warptalk-alertmanager          alertmanager.yaml via render-alertmanager-config.sh
#   monitoring/warptalk-grafana-admin         GRAFANA_ADMIN_USER / GRAFANA_ADMIN_PASSWORD
#   warptalk/warptalk-ghcr                    registry pull secret, when GHCR_PULL_USER and
#                                             GHCR_PULL_TOKEN are set (read:packages)
#
# K8S_DRY_RUN=true validates everything (contract + server-side dry run) and changes nothing.
# No value is ever printed or placed on a command line.
set -euo pipefail

: "${K8S_RUNTIME_ENV_FILE:?K8S_RUNTIME_ENV_FILE is required}"
NAMESPACE="${K3S_NAMESPACE:-warptalk}"
DATA_NAMESPACE="${K3S_DATA_NAMESPACE:-warptalk-data}"
MONITORING_NAMESPACE="${K3S_MONITORING_NAMESPACE:-monitoring}"
SECRET_NAME="${K3S_RUNTIME_SECRET_NAME:-warptalk-runtime}"
K8S_DRY_RUN="${K8S_DRY_RUN:-false}"
# Render and validate only; used by the offline contract test. Needs no cluster.
K8S_RENDER_ONLY="${K8S_RENDER_ONLY:-false}"
K8S_RENDER_OUTPUT="${K8S_RENDER_OUTPUT:-}"

overlay_keys=(
  STRIPE_SECRET_KEY
  STRIPE_WEBHOOK_SECRET
  LIVEKIT_URL
  LIVEKIT_API_KEY
  LIVEKIT_API_SECRET
  GOOGLE_CLIENT_ID
  GOOGLE_WORKSPACE_CLIENT_ID
  GOOGLE_WORKSPACE_CLIENT_SECRET
  CARTESIA_ADMIN_API_KEY
  CARTESIA_USAGE_API_KEY_ID
)
# Required outside warptalk-runtime (the runtime keys are enforced by runtime-secret-contract.json).
platform_keys=(
  BACKUP_S3_ACCESS_KEY_ID
  BACKUP_S3_SECRET_ACCESS_KEY
  BACKUP_S3_ENDPOINT_URL
  ALERT_EMAIL_TO
  GRAFANA_ADMIN_PASSWORD
)

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
runtime_secret_check="$script_dir/check-k3s-runtime-secret.sh"
alertmanager_renderer="$script_dir/render-alertmanager-config.sh"

fail() {
  echo "materialize-k8s-runtime-secrets: $*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "missing dependency: jq"
test -r "$K8S_RUNTIME_ENV_FILE" || fail "cannot read K8S_RUNTIME_ENV_FILE"
if [ "$K8S_RENDER_ONLY" != "true" ]; then
  : "${KUBECONFIG:?KUBECONFIG must name the target cluster explicitly}"
  export KUBECONFIG
  command -v kubectl >/dev/null 2>&1 || fail "missing dependency: kubectl"
fi

umask 077
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/warptalk-runtime-secrets.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT INT TERM

# KEY=VALUE lines -> JSON object. Blank lines and # comments are skipped; the value is everything
# after the first '=', verbatim (connection strings are full of '=' and ';'). No shell evaluation,
# no quote stripping: the file is data, never sourced.
env_json="$work_dir/env.json"
jq -Rn '
  [inputs
    | sub("\r$"; "")
    | select(test("^[[:space:]]*(#|$)") | not)
    | if test("^[A-Za-z_][A-Za-z0-9_]*=") then . else error("malformed line (expected KEY=VALUE)") end
    | capture("^(?<key>[A-Za-z_][A-Za-z0-9_]*)=(?<value>.*)$")
  ]
  | reduce .[] as $pair ({}; .[$pair.key] = $pair.value)
' <"$K8S_RUNTIME_ENV_FILE" >"$env_json" || fail "K8S_RUNTIME_ENV is not a KEY=VALUE file"

for key in "${overlay_keys[@]}"; do
  if [ -n "${!key:-}" ]; then
    # Read from the environment inside jq, so the value never appears in an argv.
    jq --arg key "$key" '.[$key] = env[$key]' "$env_json" >"$env_json.next"
    mv "$env_json.next" "$env_json"
  fi
done

for key in "${platform_keys[@]}"; do
  jq -e --arg key "$key" '(.[$key] // "") | length > 0' "$env_json" >/dev/null ||
    fail "K8S_RUNTIME_ENV has no value for $key"
done
jq -e '.PGUSER == "postgres"' "$env_json" >/dev/null ||
  fail "PGUSER must be postgres: it is also the CloudNativePG superuser secret"

secret_of() {
  # $1 namespace, $2 name, $3 type, $4 jq program producing {key: plainValue}
  jq --arg namespace "$1" --arg name "$2" --arg type "$3" "
    {
      apiVersion: \"v1\",
      kind: \"Secret\",
      type: \$type,
      metadata: {
        name: \$name,
        namespace: \$namespace,
        labels: {\"app.kubernetes.io/managed-by\": \"warptalk-release\"}
      },
      data: (($4) | map_values(@base64))
    }" "$env_json"
}

runtime_secret="$work_dir/runtime-secret.json"
secret_of "$NAMESPACE" "$SECRET_NAME" Opaque '.' >"$runtime_secret"
K3S_RUNTIME_SECRET_FILE="$runtime_secret" "$runtime_secret_check" >/dev/null ||
  fail "K8S_RUNTIME_ENV does not satisfy deploy/k3s/runtime-secret-contract.json (missing, empty, weak, placeholder or non-PgBouncer value)"

alertmanager_file="$work_dir/alertmanager.yaml"
ALERT_EMAIL_TO="$(jq -r '.ALERT_EMAIL_TO' "$env_json")" \
  RESEND_API_KEY="$(jq -r '.RESEND_API_KEY // ""' "$env_json")" \
  RESEND_FROM_EMAIL="$(jq -r '.RESEND_FROM_EMAIL // ""' "$env_json")" \
  ALERTMANAGER_CONFIG_PATH="$alertmanager_file" \
  "$alertmanager_renderer" >/dev/null
alertmanager_secret="$(jq -n \
  --arg namespace "$MONITORING_NAMESPACE" \
  --rawfile config "$alertmanager_file" '
  {
    apiVersion: "v1", kind: "Secret", type: "Opaque",
    metadata: {name: "warptalk-alertmanager", namespace: $namespace,
      labels: {"app.kubernetes.io/managed-by": "warptalk-release"}},
    data: {"alertmanager.yaml": ($config | @base64)}
  }')"

{
  cat "$runtime_secret"
  secret_of "$DATA_NAMESPACE" warptalk-postgres-superuser kubernetes.io/basic-auth \
    '{username: .PGUSER, password: .PGPASSWORD}'
  secret_of "$DATA_NAMESPACE" warptalk-backup-credentials Opaque \
    '{ACCESS_KEY_ID: .BACKUP_S3_ACCESS_KEY_ID, SECRET_ACCESS_KEY: .BACKUP_S3_SECRET_ACCESS_KEY, ENDPOINT_URL: .BACKUP_S3_ENDPOINT_URL}'
  secret_of "$DATA_NAMESPACE" warptalk-redis-auth Opaque '{password: .REDIS_PASSWORD}'
  secret_of "$DATA_NAMESPACE" warptalk-qdrant-auth Opaque '{"api-key": .VECTOR_DB_API_KEY}'
  printf '%s\n' "$alertmanager_secret"
  secret_of "$MONITORING_NAMESPACE" warptalk-grafana-admin Opaque \
    '{"admin-user": (.GRAFANA_ADMIN_USER // "admin"), "admin-password": .GRAFANA_ADMIN_PASSWORD}'
  if [ -n "${GHCR_PULL_USER:-}" ] && [ -n "${GHCR_PULL_TOKEN:-}" ]; then
    jq -n --arg namespace "$NAMESPACE" '
      {auths: {"ghcr.io": {
        username: env.GHCR_PULL_USER,
        password: env.GHCR_PULL_TOKEN,
        auth: ((env.GHCR_PULL_USER + ":" + env.GHCR_PULL_TOKEN) | @base64)}}} as $config
      | {
          apiVersion: "v1", kind: "Secret", type: "kubernetes.io/dockerconfigjson",
          metadata: {name: "warptalk-ghcr", namespace: $namespace,
            labels: {"app.kubernetes.io/managed-by": "warptalk-release"}},
          data: {".dockerconfigjson": ($config | tojson | @base64)}
        }'
  fi
} | jq -s '{apiVersion: "v1", kind: "List", items: .}' >"$work_dir/secrets.json"

secret_count="$(jq '.items | length' "$work_dir/secrets.json")"
runtime_key_count="$(jq '.data | length' "$runtime_secret")"

if [ "$K8S_RENDER_ONLY" = "true" ]; then
  if [ -n "$K8S_RENDER_OUTPUT" ]; then
    cp "$work_dir/secrets.json" "$K8S_RENDER_OUTPUT"
  fi
  echo "materialize-k8s-runtime-secrets: render PASS ($secret_count secrets, $runtime_key_count runtime keys)"
  exit 0
fi

apply_args=(--server-side --force-conflicts --field-manager=warptalk-release)
if [ "$K8S_DRY_RUN" = "true" ]; then
  apply_args+=(--dry-run=server)
fi
kubectl apply "${apply_args[@]}" -f "$work_dir/secrets.json" >/dev/null

if [ "$K8S_DRY_RUN" = "true" ]; then
  echo "materialize-k8s-runtime-secrets: server-side dry run PASS ($secret_count secrets, $runtime_key_count runtime keys); nothing was changed"
else
  echo "materialize-k8s-runtime-secrets: applied $secret_count secrets ($runtime_key_count runtime keys) from the GitHub production environment"
fi
