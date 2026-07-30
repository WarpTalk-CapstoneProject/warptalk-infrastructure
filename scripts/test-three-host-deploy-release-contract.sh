#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/deploy-release.sh"
override_filter="$repo_root/deploy/production/release-override.jq"

fail() {
  echo "three-host release deploy contract: FAIL - $*" >&2
  exit 1
}

sh -n "$script" || fail "deploy script has invalid shell syntax"
[ -r "$override_filter" ] || fail "release override jq filter is missing"
rg -q 'DEPLOY_ROLE' "$script" || fail "deployment role is not required"
for role in app data infra; do
  rg -q "$role" "$script" || fail "deployment role $role is missing"
done
rg -q 'data\.compose\.yml' "$script" || fail "Data manifest is not routed"
rg -q 'infra\.compose\.yml' "$script" || fail "Infra manifest is not routed"
rg -q 'app\.compose\.yml' "$script" || fail "App manifest is not routed"
rg -q 'has\(\$image\.service\)' "$override_filter" ||
  fail "release override is not filtered to services on the selected host"
rg -q 'compose run --rm migrator' "$script" ||
  fail "App migration gate is missing"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

jq -n '{
  images: [
    {
      service: "auth-service",
      ref: "example.invalid/auth-service:test",
      digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    },
    {
      service: "metrics-exporter",
      ref: "example.invalid/metrics-exporter:test",
      digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    }
  ]
}' >"$tmp_dir/manifest.json"

jq -n '{
  services: {
    "auth-service": {image: "old-auth"},
    postgres: {image: "postgres:18-alpine"}
  }
}' >"$tmp_dir/base.json"

jq --slurpfile base "$tmp_dir/base.json" \
  -f "$override_filter" \
  "$tmp_dir/manifest.json" >"$tmp_dir/override.json" ||
  fail "release override jq filter does not compile"

jq -e '
  (.services | keys) == ["auth-service"] and
  .services["auth-service"].image ==
    "example.invalid/auth-service:test@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
' "$tmp_dir/override.json" >/dev/null ||
  fail "release override jq filter produced the wrong host-scoped override"

echo "three-host release deploy contract: PASS"
