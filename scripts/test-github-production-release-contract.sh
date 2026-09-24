#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$repo_root/.github/workflows/release.yml"

fail() {
  echo "GitHub production release contract: FAIL - $*" >&2
  exit 1
}

[[ -r "$workflow" ]] || fail "release workflow is missing"

# Production runs on Kubernetes, and production-k8s is the only deploy job. The staging job, the
# compose (SSH + docker compose) production job and the opt-in cluster-admin bootstrap job were
# always skipped and are gone; their scripts stay for manual recovery (deploy/k3s/README.md).
jobs="$(awk '/^jobs:$/ { inside = 1; next } inside && /^  [A-Za-z0-9_-]+:$/ { sub(/:$/, ""); sub(/^  /, ""); print }' "$workflow" | tr '\n' ' ')"
[[ "$jobs" == "build-scan-sign production-k8s " ]] ||
  fail "the release must have exactly build-scan-sign and production-k8s, found: $jobs"
for removed in deploy_target k8s_bootstrap k8s-bootstrap force_full_deploy K8S_BOOTSTRAP_KUBECONFIG STAGING_ STAGING_ENABLED; do
  if grep -Fq "$removed" "$workflow"; then
    fail "the release still references $removed (removed with the always-skipped jobs)"
  fi
done
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

# The build job is where every supply-chain gate lives; the deploy job only consumes its output.
build_job="$(awk '/^  build-scan-sign:$/,/^  production-k8s:$/' "$workflow")"
printf '%s\n' "$build_job" | grep -Fq 'sigstore/cosign-installer@' ||
  fail "the build job must install Cosign to sign the images"
printf '%s\n' "$build_job" | grep -Eq '^      id-token: write$' ||
  fail "keyless Cosign signing needs id-token: write on the build job"
printf '%s\n' "$build_job" | grep -Fq 'secure-release-images.sh' ||
  fail "the build job must run the SBOM, Trivy and Cosign sign/verify gate"

# No release reaches a host over SSH any more: the deploy runs through the scoped Kubernetes
# deployer. A normal release must never carry an SSH identity.
for ssh_marker in PRODUCTION_SSH_KEY PRODUCTION_KNOWN_HOSTS 'ssh production-' ProxyJump deploy-release.sh; do
  if grep -Fq "$ssh_marker" "$workflow"; then
    fail "the release still deploys over SSH ($ssh_marker); production is Kubernetes-only"
  fi
done

# --- Kubernetes path: the only deploy job ------------------------------------------------------
grep -Eq '^      k8s_dry_run:$' "$workflow" || fail "k8s_dry_run input is missing"
awk '/^      k8s_dry_run:$/,/default:/' "$workflow" | grep -Eq 'type: boolean$' ||
  fail "k8s_dry_run must be a boolean"
awk '/^      k8s_dry_run:$/,/default:/' "$workflow" | grep -Eq 'default: false$' ||
  fail "k8s_dry_run must default to a real release"
grep -Eq '^  production-k8s:$' "$workflow" || fail "Kubernetes release job is missing"
k8s_job="$(awk '/^  production-k8s:$/,0' "$workflow")"
printf '%s\n' "$k8s_job" | grep -Eq '^    needs: build-scan-sign$' ||
  fail "the k8s release must follow the signed build, and nothing else"
# A plain needs: runs only after a successful build. Any job-level if: (always(), a target input)
# could let it run after a failed or skipped build, or skip it silently.
if printf '%s\n' "$k8s_job" | grep -Eq '^    if:'; then
  fail "the k8s release must not carry a job-level if:; it runs whenever the build succeeds"
fi
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
# The cluster bootstrap (cluster-admin) is not part of a release; it is run by hand, and the
# procedure must stay documented so the removed job is recoverable.
readme="$repo_root/deploy/k3s/README.md"
grep -Fq '### Cluster bootstrap by hand' "$readme" ||
  fail "deploy/k3s/README.md must document the manual cluster bootstrap"
for step in deploy/k3s/cluster/deployer-rbac.yaml materialize-k8s-runtime-secrets.sh label-k8s-nodes.sh install-k3s-addons.sh; do
  awk '/^### Cluster bootstrap by hand$/,/^## /' "$readme" | grep -Fq "$step" ||
    fail "the manual cluster bootstrap in deploy/k3s/README.md must run $step"
  [[ -e "$repo_root/$step" || -e "$repo_root/scripts/$step" ]] ||
    fail "$step is referenced by the manual bootstrap but no longer exists"
done
if grep -Eq 'required_reviewers' "$workflow"; then
  fail "the production Environment gate is a wait timer; do not add required_reviewers"
fi

echo "GitHub production release contract: PASS"
