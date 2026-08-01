#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$repo_root/.github/workflows/release.yml"

fail() {
  echo "GitHub production release contract: FAIL - $*" >&2
  exit 1
}

[[ -r "$workflow" ]] || fail "release workflow is missing"

grep -Eq '^  production:$' "$workflow" ||
  fail "production deploy job is missing"
grep -Eq '^    environment: production$' "$workflow" ||
  fail "production job is not protected by the production Environment"
grep -Eq '^    needs: build-scan-sign$' "$workflow" ||
  fail "production approval must happen after the immutable build"
grep -Eq '^    concurrency:$' "$workflow" ||
  fail "production deployments must be serialized"
grep -Eq 'tailscale/github-action@[0-9a-f]{40}' "$workflow" ||
  fail "production runner does not join the tailnet with a pinned action"
grep -Eq 'oauth-client-id:.*TS_OAUTH_CLIENT_ID' "$workflow" ||
  fail "Tailscale OAuth client ID is missing"
grep -Eq 'oauth-secret:.*TS_OAUTH_SECRET' "$workflow" ||
  fail "Tailscale OAuth secret is missing"
grep -Eq 'tags: tag:github-actions' "$workflow" ||
  fail "Tailscale runner tag is missing"
grep -Eq 'ping:.*PRODUCTION_APP_HOST' "$workflow" ||
  fail "tailnet connectivity is not gated before deployment"

grep -Eq 'trivy_archive="trivy_\$\{trivy_version\}_Linux-64bit\.tar\.gz"' "$workflow" ||
  fail "Trivy archive must retain the checksum manifest filename"
grep -Eq -- '--output "\$trivy_archive"' "$workflow" ||
  fail "Trivy download filename does not match its checksum manifest"
grep -Eq 'tar -xzf "\$trivy_archive" trivy' "$workflow" ||
  fail "Trivy extraction does not use the verified archive"

grep -Eq 'warptalk-deployment\.tar\.gz' "$workflow" ||
  fail "the selected infrastructure release is not packaged"
grep -Eq 'package-production-deployment\.sh' "$workflow" ||
  fail "the canonical production package builder is not used"
grep -Eq 'PRODUCTION_ENV_FILE=/etc/warptalk/\.env\.production' "$workflow" ||
  fail "the production deploy points at the wrong environment file"

data_line="$(grep -En 'deploy_host data' "$workflow" | cut -d: -f1)"
infra_line="$(grep -En 'deploy_host infra' "$workflow" | cut -d: -f1)"
app_line="$(grep -En 'deploy_host app' "$workflow" | cut -d: -f1)"
[[ -n "$data_line" && -n "$infra_line" && -n "$app_line" ]] ||
  fail "Data, Infra and App roles must all be deployed"
(( data_line < infra_line && infra_line < app_line )) ||
  fail "roles must deploy in Data, Infra, App order"

grep -Eq 'ProxyJump production-app' "$workflow" ||
  fail "private hosts are not reached through the App jump host"
grep -Eq 'StrictHostKeyChecking yes' "$workflow" ||
  fail "SSH host identity verification is not fail-closed"
grep -Eq 'PRODUCTION_KNOWN_HOSTS' "$workflow" ||
  fail "trusted production host keys are not installed"
grep -Eq 'PRODUCTION_SSH_KEY' "$workflow" ||
  fail "dedicated production SSH identity is not installed"

if grep -Eq 'SKIP_IMAGE_PULL=true' "$workflow"; then
  fail "GitHub releases must pull the newly built immutable images"
fi

echo "GitHub production release contract: PASS"
