#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/mount-production-data-volume.sh"

fail() {
  echo "mount production volume contract: FAIL - $*" >&2
  exit 1
}

[[ -x "$script" ]] || fail "mount script is missing or not executable"
sh -n "$script" || fail "mount script has invalid shell syntax"

rg -q 'ROLE must be data or infra' "$script" ||
  fail "role allow-list is missing"
rg -q 'DEVICE is required' "$script" ||
  fail "explicit device is not required"
rg -q 'lsblk -bndo SIZE' "$script" ||
  fail "exact block-device size guard is missing"
rg -q 'existing filesystem is not the expected WarpTalk volume' "$script" ||
  fail "existing filesystem rejection is missing"
rg -q 'mkfs\.ext4' "$script" ||
  fail "ext4 creation is missing"
rg -q 'UUID=' "$script" ||
  fail "persistent UUID mount is missing"
rg -q 'findmnt --mountpoint' "$script" ||
  fail "post-mount verification is missing"
rg -q 'flock' "$script" ||
  fail "concurrent execution guard is missing"

echo "mount production volume contract: PASS"
