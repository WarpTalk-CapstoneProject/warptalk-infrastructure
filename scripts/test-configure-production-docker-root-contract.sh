#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/configure-production-docker-root.sh"

fail() {
  echo "production Docker root contract: FAIL - $*" >&2
  exit 1
}

[[ -x "$script" ]] || fail "configuration script is missing or not executable"
sh -n "$script" || fail "configuration script has invalid shell syntax"
rg -q 'findmnt --mountpoint /srv/warptalk' "$script" ||
  fail "durable mount verification is missing"
rg -q 'docker ps -aq' "$script" ||
  fail "existing-container guard is missing"
rg -q 'docker images -aq' "$script" ||
  fail "existing-image guard is missing"
rg -q '"data-root"' "$script" ||
  fail "Docker data-root configuration is missing"
rg -q 'systemctl restart docker' "$script" ||
  fail "Docker restart is missing"
rg -q 'DockerRootDir' "$script" ||
  fail "post-change Docker root verification is missing"

echo "production Docker root contract: PASS"
