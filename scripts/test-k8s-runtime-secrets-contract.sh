#!/usr/bin/env bash
# Offline contract for scripts/materialize-k8s-runtime-secrets.sh: the one path by which the
# GitHub `production` environment becomes Kubernetes secrets. No cluster is needed.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"
template="$root_dir/deploy/k3s/runtime-env.template"
contract="$root_dir/deploy/k3s/runtime-secret-contract.json"
materialize="$script_dir/materialize-k8s-runtime-secrets.sh"

work="$(mktemp -d "${TMPDIR:-/tmp}/warptalk-runtime-secrets-contract.XXXXXX")"
trap 'rm -rf "$work"' EXIT

fail() {
  echo "K8s runtime secrets contract: FAIL - $*" >&2
  exit 1
}

# Every contract key must be in the template the owner fills in.
for key in $(jq -r '.requiredNonEmptyKeys[], .requiredPresentKeys[]' "$contract"); do
  grep -Eq "^$key=" "$template" || fail "runtime-env.template is missing $key"
done

pooler="$(jq -r '.pgbouncerHost' "$contract")"
valid="$work/valid.env"
# A filled-in template: realistic lengths, PgBouncer connection strings, PGUSER=postgres.
while IFS= read -r line; do
  case "$line" in
    ""|\#*) printf '%s\n' "$line" ;;
    JWT_SECRET=*|GRPC_INTERNAL_SECRET=*) printf '%s=%s\n' "${line%%=*}" "$(printf 'x%.0s' $(seq 1 64))" ;;
    WORKSPACE_STORAGE_MASTER_KEY=*) printf '%s=%s\n' "${line%%=*}" "$(printf 'k%.0s' $(seq 1 32))" ;;
    PGUSER=*) printf 'PGUSER=postgres\n' ;;
    ALERT_EMAIL_TO=*) printf 'ALERT_EMAIL_TO=ops@warptalk.invalid\n' ;;
    RESEND_FROM_EMAIL=*) printf 'RESEND_FROM_EMAIL=alerts@warptalk.invalid\n' ;;
    *_CONNECTION_STRING=*|*_DSN=*) printf '%s=Host=%s;Port=5432;Database=x;Password=a=b;c\n' "${line%%=*}" "$pooler" ;;
    *=CHANGE_ME) printf '%s=contract-value\n' "${line%%=*}" ;;
    *) printf '%s\n' "$line" ;;
  esac
done <"$template" >"$valid"

output="$work/secrets.json"
K8S_RUNTIME_ENV_FILE="$valid" K8S_RENDER_ONLY=true K8S_RENDER_OUTPUT="$output" \
  STRIPE_SECRET_KEY=overlay-from-github \
  "$materialize" >/dev/null || fail "a complete runtime env was rejected"

runtime="$(jq '.items[] | select(.metadata.name == "warptalk-runtime")' "$output")"
[ "$(printf '%s' "$runtime" | jq -r '.data.STRIPE_SECRET_KEY | @base64d')" = "overlay-from-github" ] ||
  fail "a GitHub secret overlay must win over the env file"
[ "$(printf '%s' "$runtime" | jq -r '.data.AUTH_CONNECTION_STRING | @base64d')" = "Host=$pooler;Port=5432;Database=x;Password=a=b;c" ] ||
  fail "values must be kept verbatim after the first '='"
for secret in warptalk-postgres-superuser warptalk-backup-credentials warptalk-redis-auth \
  warptalk-qdrant-auth warptalk-alertmanager warptalk-grafana-admin; do
  jq -e --arg name "$secret" 'any(.items[]; .metadata.name == $name)' "$output" >/dev/null ||
    fail "$secret is not materialized"
done
jq -e '.items[] | select(.metadata.name == "warptalk-alertmanager") | .data["alertmanager.yaml"] | @base64d
  | contains("ops@warptalk.invalid") and (contains("__") | not)' "$output" >/dev/null ||
  fail "Alertmanager must be rendered with the real receiver"
jq -e '.items[] | select(.metadata.name == "warptalk-postgres-superuser") | .type == "kubernetes.io/basic-auth"' \
  "$output" >/dev/null || fail "the CloudNativePG superuser secret must be basic-auth"

expect_rejected() {
  local description="$1" file="$2"
  if K8S_RUNTIME_ENV_FILE="$file" K8S_RENDER_ONLY=true "$materialize" >/dev/null 2>&1; then
    fail "accepted $description"
  fi
}
grep -v '^AUTH_CONNECTION_STRING=' "$valid" >"$work/missing.env"
expect_rejected "a missing contract key" "$work/missing.env"
sed 's/^STRIPE_WEBHOOK_SECRET=.*/STRIPE_WEBHOOK_SECRET=CHANGE_ME/' "$valid" >"$work/placeholder.env"
expect_rejected "a placeholder" "$work/placeholder.env"
grep -v '^BACKUP_S3_ENDPOINT_URL=' "$valid" >"$work/no-backup.env"
expect_rejected "a missing backup endpoint" "$work/no-backup.env"
sed 's/^PGUSER=.*/PGUSER=app/' "$valid" >"$work/pguser.env"
expect_rejected "a non-postgres superuser" "$work/pguser.env"
{ cat "$valid"; echo 'this is not a key value line'; } >"$work/malformed.env"
expect_rejected "a malformed line" "$work/malformed.env"

echo "K8s runtime secrets contract: PASS"
