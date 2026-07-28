#!/bin/sh
set -eu

: "${APP_BASE_URL:?APP_BASE_URL is required}"
: "${API_BASE_URL:?API_BASE_URL is required}"

curl_health() {
  curl --fail --silent --show-error \
    --connect-timeout 5 --max-time 20 \
    "$1" | grep -q '^Healthy$'
}

curl --fail --silent --show-error \
  --connect-timeout 5 --max-time 20 \
  "$APP_BASE_URL/" >/dev/null
curl_health "$API_BASE_URL/health/live"
curl_health "$API_BASE_URL/health/ready"

# The protected route must reach the Gateway and reject an anonymous request,
# not return a proxy 404/502.
status="$(
  curl --silent --output /dev/null --write-out '%{http_code}' \
    --connect-timeout 5 --max-time 20 \
    "$API_BASE_URL/api/v1/workspaces"
)"
[ "$status" = "401" ] || { echo "Expected protected route 401, got $status" >&2; exit 1; }

echo "Production smoke checks passed."
