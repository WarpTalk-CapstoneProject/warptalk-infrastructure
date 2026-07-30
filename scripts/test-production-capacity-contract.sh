#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
deploy_root="$repo_root/deploy/production"
env_file="$deploy_root/.env.example"

fail() {
  echo "production capacity contract: FAIL - $*" >&2
  exit 1
}

assert_memory_ceiling() {
  role="$1"
  ceiling_bytes="$2"
  compose_file="$deploy_root/$role.compose.yml"
  total="$(
    docker compose --env-file "$env_file" -f "$compose_file" \
      config --format json |
      jq '[.services[].deploy.resources.limits.memory // "0" | tonumber] | add'
  )"
  [[ "$total" -le "$ceiling_bytes" ]] ||
    fail "$role declared memory $total exceeds ceiling $ceiling_bytes"
}

# Leave host headroom for Ubuntu, Docker, page cache and deployment spikes.
assert_memory_ceiling app 15032385536
assert_memory_ceiling data 7784628224
assert_memory_ceiling infra 3221225472

echo "production capacity contract: PASS"
