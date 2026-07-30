#!/bin/sh
set -eu

: "${APP_URL:?APP_URL is required, for example https://app.warptalk.io.vn}"
: "${API_URL:?API_URL is required, for example https://api.warptalk.io.vn}"

for command_name in curl grep; do
  command -v "$command_name" >/dev/null 2>&1 ||
    { echo "$command_name is required" >&2; exit 1; }
done

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/warptalk-security-smoke.XXXXXX")"
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT INT TERM

assert_security_headers() {
  url="$1"
  headers="$work_dir/headers"
  curl --fail --silent --show-error --dump-header "$headers" --output /dev/null "$url"
  tr -d '\r' <"$headers" >"$headers.normalized"
  grep -Eiq '^strict-transport-security:.*max-age=31536000' "$headers.normalized"
  grep -Eiq '^x-content-type-options:[[:space:]]*nosniff' "$headers.normalized"
  grep -Eiq '^x-frame-options:[[:space:]]*DENY' "$headers.normalized"
  grep -Eiq "^content-security-policy:.*frame-ancestors 'none'" "$headers.normalized"
  grep -Eiq '^referrer-policy:[[:space:]]*strict-origin-when-cross-origin' "$headers.normalized"
}

assert_security_headers "$APP_URL"
assert_security_headers "$API_URL/health/live"

status="$(
  curl --silent --output /dev/null --write-out '%{http_code}' \
    "$API_URL/api/v1/workspaces"
)"
case "$status" in
  401|403) ;;
  *) echo "protected API returned $status without credentials" >&2; exit 1 ;;
esac

status="$(
  curl --silent --output /dev/null --write-out '%{http_code}' \
    -X POST \
    -H 'Content-Type: application/json' \
    -H 'Stripe-Signature: invalid-security-smoke-signature' \
    --data '{}' \
    "$API_URL/api/v1/payments/webhook"
)"
case "$status" in
  400|401) ;;
  *) echo "invalid Stripe webhook unexpectedly returned $status" >&2; exit 1 ;;
esac

echo "production security smoke: PASS"
