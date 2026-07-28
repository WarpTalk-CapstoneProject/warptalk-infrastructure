#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOAD_TEST="$ROOT_DIR/performance/k6/warptalk.js"
DATA_COMPOSE="$ROOT_DIR/deploy/production/data.compose.yml"
PGBOUNCER_CONFIG="$ROOT_DIR/pgbouncer/pgbouncer.ini"

[[ -f "$LOAD_TEST" ]] || {
  echo "missing k6 workload: $LOAD_TEST" >&2
  exit 1
}

required_patterns=(
  '/api/v1/auth/login'
  '/api/v1/workspaces'
  '/api/v1/translation-rooms/join'
  '/api/v1/transcripts/'
  '/hubs/translation-room/negotiate'
  'http_req_duration'
  'http_req_failed'
  'signalr_connected'
)

for pattern in "${required_patterns[@]}"; do
  grep -Fq "$pattern" "$LOAD_TEST" || {
    echo "k6 workload is missing required contract: $pattern" >&2
    exit 1
  }
done

grep -Fq "shared_preload_libraries=pg_stat_statements" "$DATA_COMPOSE"
grep -Fq "log_min_duration_statement=500" "$DATA_COMPOSE"
grep -Eq '^default_pool_size = 15$' "$PGBOUNCER_CONFIG"
grep -Eq '^reserve_pool_size = 5$' "$PGBOUNCER_CONFIG"

for script in \
  "$ROOT_DIR/scripts/enable-postgres-performance-observability.sh" \
  "$ROOT_DIR/scripts/report-postgres-performance.sh"; do
  [[ -x "$script" ]] || {
    echo "missing executable performance script: $script" >&2
    exit 1
  }
done

echo "performance workload contract: PASS"
