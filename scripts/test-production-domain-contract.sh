#!/bin/sh
set -eu

repo_root="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"

fail() {
  echo "production domain contract: FAIL - $*" >&2
  exit 1
}

production_env="$repo_root/deploy/production/.env.example"

grep -Fxq 'APP_DOMAIN=app.warptalk.io.vn' "$production_env" ||
  fail "APP_DOMAIN is not the purchased production domain"
grep -Fxq 'API_DOMAIN=api.warptalk.io.vn' "$production_env" ||
  fail "API_DOMAIN is not the purchased production domain"
grep -Fxq 'ALLOWED_ORIGINS=https://app.warptalk.io.vn' "$production_env" ||
  fail "CORS origin is not the purchased production domain"

if rg -n '(^|[./])warptalk\.vn([/:]|$)' \
  "$repo_root/deploy/production" \
  "$repo_root/deploy/k3s" \
  "$repo_root/scripts/security-smoke.sh"; then
  fail "stale warptalk.vn production reference remains"
fi

echo "production domain contract: PASS"
