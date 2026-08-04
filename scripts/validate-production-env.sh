#!/bin/sh
set -eu

PRODUCTION_ENV_FILE="${PRODUCTION_ENV_FILE:-}"

fail() {
  echo "validate-production-env: $*" >&2
  exit 1
}

[ -n "$PRODUCTION_ENV_FILE" ] || fail "PRODUCTION_ENV_FILE is required"
[ -f "$PRODUCTION_ENV_FILE" ] || fail "production environment file is missing"
[ ! -L "$PRODUCTION_ENV_FILE" ] || fail "production environment must not be a symlink"

if mode="$(stat -c '%a' "$PRODUCTION_ENV_FILE" 2>/dev/null)"; then
  :
else
  mode="$(stat -f '%Lp' "$PRODUCTION_ENV_FILE")"
fi
[ "$mode" = "600" ] || fail "production environment mode must be 0600"

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
template="$script_dir/../deploy/production/.env.example"
[ -r "$template" ] || fail "production environment template is missing"

keys="$(mktemp)"
template_keys="$(mktemp)"
trap 'rm -f "$keys" "$template_keys"' EXIT INT TERM

sed -n 's/^\([A-Z][A-Z0-9_]*\)=.*/\1/p' "$PRODUCTION_ENV_FILE" >"$keys"
sed -n 's/^\([A-Z][A-Z0-9_]*\)=.*/\1/p' "$template" >"$template_keys"

duplicate="$(sort "$keys" | uniq -d | head -n 1)"
[ -z "$duplicate" ] || fail "duplicate environment key: $duplicate"

while IFS= read -r required_key; do
  grep -Fxq "$required_key" "$keys" ||
    fail "missing environment key: $required_key"
done <"$template_keys"

if grep -Eq 'CHANGE_ME|<[^>]+>' "$PRODUCTION_ENV_FILE"; then
  fail "CHANGE_ME or angle-bracket placeholder remains"
fi

value_of() {
  sed -n "s/^$1=//p" "$PRODUCTION_ENV_FILE" | tail -n 1
}

require_length() {
  key="$1"
  minimum="$2"
  value="$(value_of "$key")"
  [ "${#value}" -ge "$minimum" ] ||
    fail "$key must contain at least $minimum characters"
}

require_length JWT_SECRET 64
require_length GRPC_INTERNAL_SECRET 64
require_length WORKSPACE_STORAGE_MASTER_KEY 32
require_length POSTGRES_PASSWORD 24
require_length REDIS_PASSWORD 24
require_length RABBITMQ_PASSWORD 24
require_length MINIO_ROOT_PASSWORD 24

[ "$(value_of APP_PRIVATE_IP)" = "10.20.0.200" ] ||
  fail "APP_PRIVATE_IP must match the provisioned App VM"
[ "$(value_of DATA_PRIVATE_IP)" = "10.20.0.20" ] ||
  fail "DATA_PRIVATE_IP must match the provisioned Data VM"
[ "$(value_of INFRA_PRIVATE_IP)" = "10.20.0.30" ] ||
  fail "INFRA_PRIVATE_IP must match the provisioned Infra VM"

image_tag="$(value_of IMAGE_TAG)"
[ "$image_tag" != "latest" ] || fail "IMAGE_TAG=latest is forbidden"
echo "$image_tag" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{6,127}$' ||
  fail "IMAGE_TAG is not an immutable release identifier"

case "$(value_of STRIPE_SECRET_KEY)" in
  sk_test_*|sk_live_*) ;;
  *) fail "STRIPE_SECRET_KEY has an invalid prefix" ;;
esac
case "$(value_of STRIPE_WEBHOOK_SECRET)" in
  whsec_*) ;;
  *) fail "STRIPE_WEBHOOK_SECRET has an invalid prefix" ;;
esac
case "$(value_of LIVEKIT_URL)" in
  wss://*.livekit.cloud) ;;
  *) fail "LIVEKIT_URL must be a LiveKit Cloud WebSocket URL" ;;
esac

case "$(value_of ALERT_EMAIL_TO)" in
  *@*.*) ;;
  *) fail "ALERT_EMAIL_TO must be an email address" ;;
esac

echo "validate-production-env: PASS"
