#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/validate-production-env.sh"

fail() {
  echo "production env validator contract: FAIL - $*" >&2
  exit 1
}

[[ -x "$script" ]] || fail "validator is missing or not executable"
sh -n "$script" || fail "validator has invalid shell syntax"
for contract in CHANGE_ME duplicate 0600 JWT_SECRET GRPC_INTERNAL_SECRET IMAGE_TAG INFRA_PRIVATE_IP STRIPE_WEBHOOK_SECRET; do
  rg -q "$contract" "$script" || fail "validator is missing $contract contract"
done
rg -q 'validate-production-env\.sh' "$repo_root/scripts/deploy-release.sh" ||
  fail "immutable deploy does not invoke the environment gate"

echo "production env validator contract: PASS"
