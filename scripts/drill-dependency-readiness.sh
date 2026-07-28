#!/bin/sh
set -eu

dependency_container="${DEPENDENCY_CONTAINER:-warptalk-postgres}"
live_url="${LIVE_URL:-http://127.0.0.1:5101/health/live}"
ready_url="${READY_URL:-http://127.0.0.1:5101/health/ready}"
wait_seconds="${WAIT_SECONDS:-60}"

fail() {
  echo "dependency readiness drill: $*" >&2
  exit 1
}

for dependency in curl docker; do
  command -v "$dependency" >/dev/null 2>&1 ||
    fail "missing dependency: $dependency"
done

[ "${CONFIRM_DEPENDENCY_DRILL:-}" = "YES" ] ||
  fail "set CONFIRM_DEPENDENCY_DRILL=YES to stop the selected dependency temporarily"

docker inspect "$dependency_container" >/dev/null 2>&1 ||
  fail "container does not exist: $dependency_container"

http_status() {
  curl --silent --show-error --max-time 10 \
    --output /dev/null \
    --write-out '%{http_code}' \
    "$1"
}

wait_for_status() {
  url="$1"
  expected="$2"
  elapsed=0

  while [ "$elapsed" -lt "$wait_seconds" ]; do
    actual="$(http_status "$url" 2>/dev/null || true)"
    if [ "$actual" = "$expected" ]; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  fail "$url did not return $expected within ${wait_seconds}s (last status: ${actual:-unreachable})"
}

restore_dependency() {
  docker start "$dependency_container" >/dev/null 2>&1 || true
}

[ "$(http_status "$live_url")" = "200" ] ||
  fail "liveness must be healthy before the drill"
[ "$(http_status "$ready_url")" = "200" ] ||
  fail "readiness must be healthy before the drill"

trap restore_dependency EXIT INT TERM
docker stop "$dependency_container" >/dev/null

wait_for_status "$live_url" "200"
wait_for_status "$ready_url" "503"

restore_dependency
trap - EXIT INT TERM

wait_for_status "$ready_url" "200"

echo "dependency readiness drill: PASS"
echo "  dependency: $dependency_container"
echo "  outage: liveness=200 readiness=503"
echo "  recovery: readiness=200"
