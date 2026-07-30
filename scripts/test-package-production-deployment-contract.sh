#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/package-production-deployment.sh"

fail() {
  echo "production package contract: FAIL - $*" >&2
  exit 1
}

[[ -x "$script" ]] || fail "packaging script is missing or not executable"
sh -n "$script" || fail "packaging script has invalid shell syntax"
for path in deploy/production scripts observability pgbouncer; do
  rg -q "$path" "$script" || fail "package is missing $path"
done
rg -q '\.env\.production' "$script" ||
  fail "production environment exclusion is missing"
rg -q 'release-manifest\.json' "$script" ||
  fail "release manifest exclusion is missing"
rg -q 'shasum -a 256' "$script" ||
  fail "bundle checksum is missing"
rg -q 'COPYFILE_DISABLE=1' "$script" ||
  fail "macOS metadata suppression is missing"

echo "production package contract: PASS"
