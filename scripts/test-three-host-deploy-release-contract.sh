#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/deploy-release.sh"

fail() {
  echo "three-host release deploy contract: FAIL - $*" >&2
  exit 1
}

sh -n "$script" || fail "deploy script has invalid shell syntax"
rg -q 'DEPLOY_ROLE' "$script" || fail "deployment role is not required"
for role in app data infra; do
  rg -q "$role" "$script" || fail "deployment role $role is missing"
done
rg -q 'data\.compose\.yml' "$script" || fail "Data manifest is not routed"
rg -q 'infra\.compose\.yml' "$script" || fail "Infra manifest is not routed"
rg -q 'app\.compose\.yml' "$script" || fail "App manifest is not routed"
rg -q 'has\(\$image\.service\)' "$script" ||
  fail "release override is not filtered to services on the selected host"
rg -q 'compose run --rm migrator' "$script" ||
  fail "App migration gate is missing"

echo "three-host release deploy contract: PASS"
