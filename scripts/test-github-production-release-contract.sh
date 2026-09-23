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

# The release must verify its own migration artifact against the backend SHA it is
# shipping. CI's copy of this check resolves the backend to a branch, so it cannot see a
# migration that landed on the released commit but not on that branch — which is exactly
# how a migration reached main and never reached production.
grep -Eq 'check-service-migration-coverage\.sh \.\./warptalk-backend' "$workflow" ||
  fail "release does not verify staged service migrations against the released backend"

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

grep -Eq 'remote_token_file=.*GITHUB_RUN_ID.*\.token' "$workflow" ||
  fail "GHCR token must use a per-run remote token file"
grep -Eq 'chmod 0600.*remote_token_file' "$workflow" ||
  fail "remote GHCR token file must be restricted to its owner"
grep -Eq 'rm -f.*TOKEN_FILE' "$workflow" ||
  fail "remote GHCR token file is not cleaned up"
if grep -Fq "printf '%s\\n' \"\$GHCR_TOKEN\"" "$workflow"; then
  fail "GHCR token must not be prepended to the remote shell program"
fi

# --- Kubernetes path (deploy_target=k8s) -------------------------------------------------------
# Production runs on Kubernetes, so a dispatch that says nothing must deploy there; compose is a
# fallback that runs only when chosen explicitly.
grep -Eq '^      deploy_target:$' "$workflow" || fail "deploy_target input is missing"
awk '/^      deploy_target:$/,/default:/' "$workflow" | grep -Eq 'default: k8s$' ||
  fail "deploy_target must default to k8s, which is what production runs"
awk '/^  production:$/,/^    permissions:$/' "$workflow" | grep -Fq "if: \${{ inputs.deploy_target == 'compose' }}" ||
  fail "the compose job must run only when compose is chosen explicitly"
grep -Eq '^  production-k8s:$' "$workflow" || fail "Kubernetes release job is missing"
k8s_job="$(awk '/^  production-k8s:$/,0' "$workflow")"
printf '%s\n' "$k8s_job" | grep -Eq '^    needs: \[build-scan-sign, k8s-bootstrap\]$' ||
  fail "the k8s release must follow the signed build (and the optional bootstrap)"
printf '%s\n' "$k8s_job" | grep -Eq "needs.build-scan-sign.result == 'success'" ||
  fail "the k8s release must never run after a failed build"
printf '%s\n' "$k8s_job" | grep -Eq '^    environment: production$' ||
  fail "the k8s release must use the production Environment"
printf '%s\n' "$k8s_job" | grep -Eq '^      group: warptalk-production$' ||
  fail "the k8s release must share the production concurrency group"
printf '%s\n' "$k8s_job" | grep -Eq 'tailscale/github-action@[0-9a-f]{40}' ||
  fail "the k8s release must reach the cluster over the tailnet"
printf '%s\n' "$k8s_job" | grep -Fq 'secrets.K8S_KUBECONFIG' ||
  fail "the k8s release must use the scoped K8S_KUBECONFIG"
printf '%s\n' "$k8s_job" | grep -Fq "kubectl auth can-i '*' '*' --all-namespaces" ||
  fail "the k8s release must refuse a cluster-admin kubeconfig"
if printf '%s\n' "$k8s_job" | grep -Fq 'K8S_BOOTSTRAP_KUBECONFIG'; then
  fail "the k8s release must not see the bootstrap (cluster-admin) kubeconfig"
fi
printf '%s\n' "$k8s_job" | grep -Fq 'secrets.K8S_RUNTIME_ENV' ||
  fail "runtime secrets must come from the GitHub production environment"
for secret in STRIPE_SECRET_KEY STRIPE_WEBHOOK_SECRET LIVEKIT_API_SECRET GOOGLE_WORKSPACE_CLIENT_SECRET CARTESIA_ADMIN_API_KEY; do
  printf '%s\n' "$k8s_job" | grep -Fq "secrets.$secret" ||
    fail "the k8s release must overlay $secret from GitHub like the compose release"
done
printf '%s\n' "$k8s_job" | grep -Fq 'needs.build-scan-sign.outputs.google_client_id' ||
  fail "the k8s release must use the Google client id the web bundle was built with"
printf '%s\n' "$k8s_job" | grep -Fq 'name: release-${{ inputs.release_tag }}' ||
  fail "the k8s release must deploy the signed manifest from the build job"
printf '%s\n' "$k8s_job" | grep -Fq 'ref: ${{ inputs.infrastructure_ref }}' ||
  fail "the k8s release must use the dispatched infrastructure SHA"
for step in materialize-k8s-runtime-secrets.sh label-k8s-nodes.sh deploy-k3s-data.sh deploy-k3s-release.sh smoke-production.sh; do
  printf '%s\n' "$k8s_job" | grep -Fq "$step" || fail "the k8s release does not run $step"
done
data_line="$(printf '%s\n' "$k8s_job" | grep -n 'deploy-k3s-data.sh' | head -n1 | cut -d: -f1)"
release_line="$(printf '%s\n' "$k8s_job" | grep -n 'deploy-k3s-release.sh' | head -n1 | cut -d: -f1)"
(( data_line < release_line )) || fail "the data platform must deploy before the release"
printf '%s\n' "$k8s_job" | grep -Fq 'echo "K3S_SECRET_SOURCE=github"' ||
  fail "the k8s release must use GitHub production secrets when K8S_RUNTIME_ENV is set"
printf '%s\n' "$k8s_job" | grep -Fq 'K3S_DRY_RUN: ${{ inputs.k8s_dry_run }}' ||
  fail "k8s_dry_run must reach the deploy scripts"
# The bootstrap is the only holder of cluster-admin, and it is opt-in.
bootstrap_job="$(awk '/^  k8s-bootstrap:$/,/^  production-k8s:$/' "$workflow")"
printf '%s\n' "$bootstrap_job" | grep -Fq "if: \${{ inputs.deploy_target == 'k8s' && inputs.k8s_bootstrap }}" ||
  fail "the cluster bootstrap must be opt-in"
printf '%s\n' "$bootstrap_job" | grep -Fq 'deploy/k3s/cluster/deployer-rbac.yaml' ||
  fail "the bootstrap must apply the deployer RBAC"
if grep -Eq 'required_reviewers' "$workflow"; then
  fail "the production Environment gate is a wait timer; do not add required_reviewers"
fi

echo "GitHub production release contract: PASS"
