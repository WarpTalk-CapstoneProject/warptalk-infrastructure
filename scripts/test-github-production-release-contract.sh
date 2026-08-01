#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$repo_root/.github/workflows/release.yml"

fail() {
  echo "GitHub production release contract: FAIL - $*" >&2
  exit 1
}

[[ -r "$workflow" ]] || fail "release workflow is missing"

rg -q '^  production:$' "$workflow" ||
  fail "production deploy job is missing"
rg -q '^    environment: production$' "$workflow" ||
  fail "production job is not protected by the production Environment"
rg -q '^    needs: build-scan-sign$' "$workflow" ||
  fail "production approval must happen after the immutable build"
rg -q '^    concurrency:$' "$workflow" ||
  fail "production deployments must be serialized"
rg -q 'tailscale/github-action@[0-9a-f]{40}' "$workflow" ||
  fail "production runner does not join the tailnet with a pinned action"
rg -q 'oauth-client-id:.*TS_OAUTH_CLIENT_ID' "$workflow" ||
  fail "Tailscale OAuth client ID is missing"
rg -q 'oauth-secret:.*TS_OAUTH_SECRET' "$workflow" ||
  fail "Tailscale OAuth secret is missing"
rg -q 'tags: tag:github-actions' "$workflow" ||
  fail "Tailscale runner tag is missing"
rg -q 'ping:.*PRODUCTION_APP_HOST' "$workflow" ||
  fail "tailnet connectivity is not gated before deployment"

rg -q 'warptalk-deployment\.tar\.gz' "$workflow" ||
  fail "the selected infrastructure release is not packaged"
rg -q 'package-production-deployment\.sh' "$workflow" ||
  fail "the canonical production package builder is not used"
rg -q 'PRODUCTION_ENV_FILE=/etc/warptalk/\.env\.production' "$workflow" ||
  fail "the production deploy points at the wrong environment file"

data_line="$(rg -n 'deploy_host data' "$workflow" | cut -d: -f1)"
infra_line="$(rg -n 'deploy_host infra' "$workflow" | cut -d: -f1)"
app_line="$(rg -n 'deploy_host app' "$workflow" | cut -d: -f1)"
[[ -n "$data_line" && -n "$infra_line" && -n "$app_line" ]] ||
  fail "Data, Infra and App roles must all be deployed"
(( data_line < infra_line && infra_line < app_line )) ||
  fail "roles must deploy in Data, Infra, App order"

rg -q 'ProxyJump production-app' "$workflow" ||
  fail "private hosts are not reached through the App jump host"
rg -q 'StrictHostKeyChecking yes' "$workflow" ||
  fail "SSH host identity verification is not fail-closed"
rg -q 'PRODUCTION_KNOWN_HOSTS' "$workflow" ||
  fail "trusted production host keys are not installed"
rg -q 'PRODUCTION_SSH_KEY' "$workflow" ||
  fail "dedicated production SSH identity is not installed"

if rg -q 'SKIP_IMAGE_PULL=true' "$workflow"; then
  fail "GitHub releases must pull the newly built immutable images"
fi

echo "GitHub production release contract: PASS"
