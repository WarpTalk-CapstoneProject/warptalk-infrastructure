#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
builder="$repo_root/scripts/build-release.sh"
planner="$repo_root/scripts/plan-release-deployment.sh"
security="$repo_root/scripts/secure-release-images.sh"
deployer="$repo_root/scripts/deploy-release.sh"
workflow="$repo_root/.github/workflows/release.yml"
ci_workflow="$repo_root/.github/workflows/ci.yml"

fail() {
  echo "release optimization contract: FAIL - $*" >&2
  exit 1
}

[[ -x "$planner" ]] || fail "deployment planner is missing"
[[ -x "$security" ]] || fail "release image security runner is missing"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

cat >"$tmp_dir/matrix.json" <<'JSON'
{
  "schemaVersion": 1,
  "platform": "linux/amd64",
  "images": [
    {"name":"auth-service","service":"auth-service","role":"app","triggersMigrations":true},
    {"name":"frontend","service":"frontend","role":"app"},
    {"name":"ai-metrics","service":"metrics-exporter","role":"infra"},
    {"name":"health-inspector","service":"health-inspector","role":"none"}
  ]
}
JSON

cat >"$tmp_dir/current.json" <<'JSON'
{
  "schemaVersion": 1,
  "repositories": {"warptalk-infrastructure":{"commit":"infra-a"}},
  "images": [
    {"name":"auth-service","service":"auth-service","digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
    {"name":"frontend","service":"frontend","digest":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},
    {"name":"ai-metrics","service":"metrics-exporter","digest":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"},
    {"name":"health-inspector","service":"health-inspector","digest":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}
  ]
}
JSON

jq '.images |= map(if .name == "frontend" then .digest = "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee" else . end)' \
  "$tmp_dir/current.json" >"$tmp_dir/desired.json"

MATRIX_FILE="$tmp_dir/matrix.json" \
  "$planner" "$tmp_dir/current.json" "$tmp_dir/desired.json" >"$tmp_dir/plan.json"

jq -e '
  .roles.data == {deploy:false, fullDeploy:false, changedServices:[], runMigrations:false} and
  .roles.infra == {deploy:false, fullDeploy:false, changedServices:[], runMigrations:false} and
  .roles.app.deploy == true and
  .roles.app.fullDeploy == false and
  .roles.app.changedServices == ["frontend"] and
  .roles.app.runMigrations == false
' "$tmp_dir/plan.json" >/dev/null ||
  fail "web-only change did not produce a frontend-only deployment"

jq '.images |= map(if .name == "auth-service" then .digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" else . end)' \
  "$tmp_dir/current.json" >"$tmp_dir/backend-change.json"
MATRIX_FILE="$tmp_dir/matrix.json" \
  "$planner" "$tmp_dir/current.json" "$tmp_dir/backend-change.json" >"$tmp_dir/backend-plan.json"
jq -e '
  .roles.data.deploy == false and
  .roles.infra.deploy == false and
  .roles.app.deploy == true and
  .roles.app.fullDeploy == false and
  .roles.app.changedServices == ["auth-service"] and
  .roles.app.runMigrations == true
' "$tmp_dir/backend-plan.json" >/dev/null ||
  fail "backend service changes must run the shared database migrator"

# ONE IMAGE, SEVERAL CONTAINERS.
#
# An image can back more than one service — the live translation worker and the post-meeting
# backfill worker are the same code reading different streams. A selective deploy that restarts
# only the first service named leaves the others running the previous digest while the release
# reports success, which is a silent partial rollout.
cat >"$tmp_dir/shared-matrix.json" <<'JSON'
{
  "schemaVersion": 1,
  "platform": "linux/amd64",
  "images": [
    {"name":"ai-translation","service":"translation-worker","alsoServices":["translation-backfill-worker"],"role":"app"},
    {"name":"frontend","service":"frontend","role":"app"}
  ]
}
JSON
cat >"$tmp_dir/shared-current.json" <<'JSON'
{
  "schemaVersion": 1,
  "repositories": {"warptalk-infrastructure":{"commit":"infra-a"}},
  "images": [
    {"name":"ai-translation","service":"translation-worker","alsoServices":["translation-backfill-worker"],"digest":"sha256:1111111111111111111111111111111111111111111111111111111111111111"},
    {"name":"frontend","service":"frontend","digest":"sha256:2222222222222222222222222222222222222222222222222222222222222222"}
  ]
}
JSON
jq '.images |= map(if .name == "ai-translation" then .digest = "sha256:3333333333333333333333333333333333333333333333333333333333333333" else . end)' \
  "$tmp_dir/shared-current.json" >"$tmp_dir/shared-desired.json"
MATRIX_FILE="$tmp_dir/shared-matrix.json" \
  "$planner" "$tmp_dir/shared-current.json" "$tmp_dir/shared-desired.json" >"$tmp_dir/shared-plan.json"
jq -e '
  .roles.app.changedServices == ["translation-backfill-worker", "translation-worker"]
' "$tmp_dir/shared-plan.json" >/dev/null ||
  fail "a changed image must restart every service it backs, not only the first one named"

# The same fact on the deploy side: the override has to PIN every one of those services, or the
# unpinned one falls through to ${IMAGE_REGISTRY}/${IMAGE_TAG} from the host .env — values no
# release rewrites — and pulls a tag that no longer exists. That is what failed v144.
cat >"$tmp_dir/override-base.json" <<'JSON'
{"services":{"translation-worker":{},"translation-backfill-worker":{},"frontend":{},"absent-here":{}}}
JSON
jq -n '{images:[
  {"name":"ai-translation","service":"translation-worker","alsoServices":["translation-backfill-worker"],"ref":"ghcr.io/x/ai-translation:src-a","digest":"sha256:1111111111111111111111111111111111111111111111111111111111111111"},
  {"name":"only-elsewhere","service":"not-on-this-role","ref":"ghcr.io/x/other:src-b","digest":"sha256:2222222222222222222222222222222222222222222222222222222222222222"}
]}' >"$tmp_dir/override-manifest.json"
jq --slurpfile base "$tmp_dir/override-base.json" \
  -f "$repo_root/deploy/production/release-override.jq" \
  "$tmp_dir/override-manifest.json" >"$tmp_dir/override.json"
jq -e '
  .services["translation-worker"].image == "ghcr.io/x/ai-translation:src-a@sha256:1111111111111111111111111111111111111111111111111111111111111111" and
  .services["translation-backfill-worker"].image == .services["translation-worker"].image and
  (.services | has("not-on-this-role") | not)
' "$tmp_dir/override.json" >/dev/null ||
  fail "the release override must pin every service an image backs, and invent none"

jq '.repositories["warptalk-infrastructure"].commit = "infra-b"' \
  "$tmp_dir/desired.json" >"$tmp_dir/infra-change.json"
MATRIX_FILE="$tmp_dir/matrix.json" \
  "$planner" "$tmp_dir/current.json" "$tmp_dir/infra-change.json" >"$tmp_dir/full-plan.json"
jq -e '
  all(.roles[]; .deploy == true and .fullDeploy == true) and
  .roles.app.runMigrations == true
' "$tmp_dir/full-plan.json" >/dev/null ||
  fail "infrastructure changes must fail safe to a full ordered deployment"

MATRIX_FILE="$tmp_dir/matrix.json" FORCE_FULL_DEPLOY=true \
  "$planner" "$tmp_dir/current.json" "$tmp_dir/desired.json" >"$tmp_dir/forced-plan.json"
jq -e 'all(.roles[]; .deploy == true and .fullDeploy == true)' \
  "$tmp_dir/forced-plan.json" >/dev/null ||
  fail "force-full deployment escape hatch is missing"

grep -Eq -- '--cache-from.*type=registry' "$builder" ||
  fail "BuildKit registry cache import is missing"
grep -Eq -- '--cache-to.*type=registry.*mode=max' "$builder" ||
  fail "BuildKit registry cache export is missing"
grep -Eq 'org\.opencontainers\.image\.revision=\$source_commit' "$builder" ||
  fail "OCI revision is not tied to the source commit"
grep -Eq 'reused.*true|true.*reused' "$builder" ||
  fail "release manifest does not record reused images"
grep -Eq 'VERIFY_REUSED_IMAGES' "$builder" ||
  fail "registry hits can be reused without prior signature verification"

grep -Eq 'cosign verify-attestation' "$security" ||
  fail "reused SBOM attestations are not verified"
grep -Eq -- '--type custom' "$security" ||
  fail "source fingerprint provenance is not attested and verified"
grep -Eq 'buildFingerprint' "$security" ||
  fail "verified provenance is not bound to the requested build fingerprint"
grep -Eq 'cosign verify([^a-z-]|$)' "$security" ||
  fail "image signatures are not verified"
grep -Eq 'trivy sbom' "$security" ||
  fail "current vulnerability policy is not evaluated from the generated SBOM"
grep -Eq 'xargs.*-P|--max-procs' "$security" ||
  fail "image security checks are not bounded-parallel"

security_fixture_bin="$repo_root/scripts/test-fixtures/release-security-bin"
cat >"$tmp_dir/security-manifest.json" <<'JSON'
{
  "schemaVersion": 1,
  "images": [
    {"name":"new-image","ref":"example.invalid/new-image:src-a","digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","sourceRepository":"repo-new","sourceCommit":"1111111111111111111111111111111111111111","buildFingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","reused":false},
    {"name":"reused-image","ref":"example.invalid/reused-image:src-b","digest":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","sourceRepository":"repo-reused","sourceCommit":"2222222222222222222222222222222222222222","buildFingerprint":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","reused":true}
  ]
}
JSON
PATH="$security_fixture_bin:$PATH" \
  RELEASE_SECURITY_LOG="$tmp_dir/security.log" \
  RELEASE_MANIFEST="$tmp_dir/security-manifest.json" \
  SBOM_OUTPUT_DIR="$tmp_dir/sbom" \
  SECURITY_PARALLELISM=2 \
  COSIGN_CERTIFICATE_IDENTITY_REGEXP='^https://example.invalid/workflow$' \
  COSIGN_CERTIFICATE_OIDC_ISSUER='https://issuer.example.invalid' \
  "$security" >/dev/null || fail "runtime image security gate failed"
[[ "$(grep -c '^cosign sign ' "$tmp_dir/security.log")" -eq 1 ]] ||
  fail "new and reused images were not distinguished during signing"
[[ "$(grep -c '^cosign attest ' "$tmp_dir/security.log")" -eq 2 ]] ||
  fail "new images must receive SBOM and source provenance attestations"
[[ "$(grep -c '^cosign verify ' "$tmp_dir/security.log")" -eq 2 ]] ||
  fail "every image signature must be verified"
[[ "$(grep -c '^cosign verify-attestation ' "$tmp_dir/security.log")" -eq 4 ]] ||
  fail "every image SBOM and source provenance attestation must be verified"
[[ "$(find "$tmp_dir/sbom" -name '*.spdx.json' | wc -l | tr -d ' ')" -eq 2 ]] ||
  fail "security gate did not generate a complete SBOM set"

if PATH="$security_fixture_bin:$PATH" \
  RELEASE_SECURITY_LOG="$tmp_dir/bad-provenance.log" \
  RELEASE_SECURITY_BAD_PROVENANCE=true \
  RELEASE_MANIFEST="$tmp_dir/security-manifest.json" \
  SBOM_OUTPUT_DIR="$tmp_dir/bad-provenance-sbom" \
  SECURITY_PARALLELISM=1 \
  COSIGN_CERTIFICATE_IDENTITY_REGEXP='^https://example.invalid/workflow$' \
  COSIGN_CERTIFICATE_OIDC_ISSUER='https://issuer.example.invalid' \
  "$security" >/dev/null 2>&1; then
  fail "mismatched source provenance was accepted"
fi

grep -Eq 'DEPLOY_SERVICES' "$deployer" ||
  fail "deploy script cannot target changed services"
grep -Eq -- '--no-deps' "$deployer" ||
  fail "selective deploy can start unrelated dependencies"
grep -Eq 'RUN_MIGRATIONS' "$deployer" ||
  fail "migration execution is not controlled by the release plan"

if grep -Eq 'docker/setup-qemu-action@' "$workflow"; then
  fail "single-platform amd64 workflow still installs QEMU"
fi
grep -Eq 'secure-release-images\.sh' "$workflow" ||
  fail "workflow does not use the secure parallel image gate"
grep -Eq 'SECURITY_PARALLELISM:[[:space:]]*["'\'']?1["'\'']?' "$workflow" ||
  fail "workflow permits concurrent Trivy cache and keyless OIDC access"
grep -Eq 'VERIFY_REUSED_IMAGES: "true"' "$workflow" ||
  fail "workflow does not fail closed when a cached image is unsigned"
grep -Eq 'plan-release-deployment\.sh' "$workflow" ||
  fail "workflow does not calculate a deployment diff"
grep -Fq 'warptalk-infrastructure/deploy/production/image-matrix.json' "$workflow" ||
  fail "release artifact omits the deployment planner image matrix"
grep -Eq 'force_full_deploy:' "$workflow" ||
  fail "workflow lacks an explicit full-deploy path for runtime config changes"
grep -Eq 'timeout:[[:space:]]*["'\'']?45s' "$workflow" ||
  fail "Tailscale connection attempts are not bounded below the previous two-minute timeout"
grep -Eq 'retry:[[:space:]]*["'\'']?3["'\'']?' "$workflow" ||
  fail "Tailscale retry count is not explicitly bounded"
grep -Eq '^    permissions:$' "$workflow" ||
  fail "job-level least-privilege permissions are missing"
grep -Eq 'test-release-optimization-contract\.sh' "$ci_workflow" ||
  fail "release optimization regressions are not enforced by infrastructure CI"
grep -Eq 'stage_role\(\)' "$workflow" ||
  fail "workflow cannot skip staging unchanged production roles"
awk '
  /^[[:space:]]*stage_host\(\)/ { inside_stage_host = 1 }
  inside_stage_host && /^[[:space:]]*REMOTE$/ { remote_payload_closed = 1 }
  remote_payload_closed && /^[[:space:]]*stage_role\(\)/ { stage_role_is_local = 1 }
  END { exit(stage_role_is_local ? 0 : 1) }
' "$workflow" || fail "stage_role is defined inside the remote staging payload"
grep -Eq '\.roles\[\$role\]\.deploy' "$workflow" ||
  fail "production staging is not controlled by the deployment plan"
if grep -Eq '^[[:space:]]+stage_host production-(data|infra|app)' "$workflow"; then
  fail "workflow still stages every production host unconditionally"
fi
grep -Fq "/opt/warptalk/current/scripts/smoke-production.sh" "$workflow" ||
  fail "smoke checks do not use the active release when the app role is unchanged"

duplicate_staging_destination="$({
  sed -n '/scp "\$manifest"/,/ssh "\$STAGING_USER/p' "$workflow" || true
} | grep -Ec 'STAGING_USER.*STAGING_HOST.*releases' || true)"
[[ "$duplicate_staging_destination" -le 1 ]] ||
  fail "staging manifest destination is duplicated as a shell command"

echo "release optimization contract: PASS"
