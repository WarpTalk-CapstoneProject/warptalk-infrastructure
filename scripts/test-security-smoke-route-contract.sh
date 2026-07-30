#!/bin/sh
set -eu

repo_root="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
smoke="$repo_root/scripts/security-smoke.sh"

grep -Fq '"$API_URL/api/v1/payments/webhook"' "$smoke" || {
  echo "security smoke route contract: FAIL - Stripe webhook route is stale" >&2
  exit 1
}

if grep -Fq '/api/v1/billing/payments/webhook' "$smoke"; then
  echo "security smoke route contract: FAIL - legacy billing prefix remains" >&2
  exit 1
fi

echo "security smoke route contract: PASS"
