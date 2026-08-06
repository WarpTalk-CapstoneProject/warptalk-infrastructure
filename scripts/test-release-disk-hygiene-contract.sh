#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
deploy="$repo_root/scripts/deploy-release.sh"
preflight="$repo_root/scripts/preflight-release-disk.sh"
prune="$repo_root/scripts/prune-release-artifacts.sh"

fail() {
  echo "release disk hygiene contract: FAIL - $*" >&2
  exit 1
}

for script in "$deploy" "$preflight" "$prune"; do
  [ -r "$script" ] || fail "missing script: $script"
  [ -x "$script" ] || fail "script is not executable: $script"
  sh -n "$script" || fail "invalid shell syntax: $script"
done

# --- the guards are actually wired into the deploy path -----------------------
grep -Eq 'preflight-release-disk\.sh' "$deploy" ||
  fail "deploy does not run the disk preflight"
grep -Eq 'prune-release-artifacts\.sh' "$deploy" ||
  fail "deploy does not run the artifact prune"

# Ordering matters more than mere presence. Match the call sites specifically:
# both scripts are also named in the readable-artifact precondition loop near
# the top of the deploy script, which would otherwise satisfy a loose match.
preflight_line="$(grep -Fn '"$script_dir/preflight-release-disk.sh" "$override"' \
  "$deploy" | head -1 | cut -d: -f1)"
prune_line="$(grep -Fn '! "$script_dir/prune-release-artifacts.sh"' \
  "$deploy" | head -1 | cut -d: -f1)"
[ -n "$preflight_line" ] || fail "cannot find the disk preflight invocation"
[ -n "$prune_line" ] || fail "cannot find the artifact prune invocation"

# The preflight is worthless unless it runs BEFORE the first pull.
pull_line="$(grep -En 'compose pull' "$deploy" | head -1 | cut -d: -f1)"
[ "$preflight_line" -lt "$pull_line" ] ||
  fail "disk preflight runs after the image pull; it must gate the pull"

# The prune must run only after the release is up.
up_line="$(grep -En 'compose up -d' "$deploy" | head -1 | cut -d: -f1)"
[ "$prune_line" -gt "$up_line" ] ||
  fail "artifact prune runs before the release is up"

# --- absolute prohibitions ----------------------------------------------------
# Named volumes hold PostgreSQL data, MinIO objects and Redis state. No script in
# the deploy path may ever remove one.
for script in "$deploy" "$preflight" "$prune"; do
  grep -Fq -- '--volumes' "$script" &&
    fail "$(basename "$script") uses --volumes; this can destroy production data"
  grep -Eq 'docker +volume +(rm|prune)' "$script" &&
    fail "$(basename "$script") removes volumes; this can destroy production data"
  grep -Eq 'docker +system +prune' "$script" &&
    fail "$(basename "$script") uses docker system prune; too blunt for a live host"
done

# Pruning must not force-remove images out from under a running container.
grep -Eq 'docker +(rmi|image +rm) +(-f\b|--force)' "$prune" &&
  fail "prune force-removes images; it must let Docker refuse in-use images"

# --- retention is bounded and keeps a rollback target -------------------------
grep -Eq 'KEEP_RELEASES' "$prune" || fail "prune has no release retention bound"
grep -Eq 'KEEP_IMAGE_RELEASES' "$prune" || fail "prune has no image retention bound"
grep -Eq 'KEEP_IMAGE_RELEASES" -ge 2' "$prune" ||
  fail "prune does not guarantee a rollback generation of images survives"
grep -Eq 'docker builder prune' "$prune" ||
  fail "prune does not reclaim build cache"

# --- preflight sizes against the real image set, not a magic number ----------
grep -Eq 'docker manifest inspect' "$preflight" ||
  fail "preflight does not size the pull against the registry"
grep -Eq 'docker image inspect' "$preflight" ||
  fail "preflight does not skip images that are already resident"
grep -Eq 'DISK_EXTRACT_FACTOR_PERCENT' "$preflight" ||
  fail "preflight ignores the cost of extracting layers"
grep -Eq 'exit 1' "$preflight" || fail "preflight cannot fail the deploy"

# --- behavioural check: preflight refuses when the disk is too small ----------
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat >"$tmp_dir/override.json" <<'JSON'
{
  "services": {
    "auth-service": {
      "image": "example.invalid/auth-service:test@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    }
  }
}
JSON

# An unreachable registry means the image cannot be sized; the floor must then
# apply and an absurd floor must fail closed rather than pass.
if DISK_MIN_FREE_MIB=999999999 DISK_TARGET_PATH="$tmp_dir" \
  "$preflight" "$tmp_dir/override.json" >/dev/null 2>&1; then
  fail "preflight passed despite an impossible free-space requirement"
fi

# With a trivial requirement it must pass.
DISK_MIN_FREE_MIB=1 DISK_MARGIN_MIB=0 DISK_EXTRACT_FACTOR_PERCENT=100 \
  DISK_UNKNOWN_IMAGE_MIB=0 DISK_TARGET_PATH="$tmp_dir" \
  "$preflight" "$tmp_dir/override.json" >/dev/null 2>&1 ||
  fail "preflight refused a deploy that comfortably fits"

# --- prune is idempotent and safe on an already-clean host --------------------
mkdir -p "$tmp_dir/releases/rel-a/deploy/production" \
  "$tmp_dir/releases/rel-b/deploy/production"
echo '{"images":[]}' >"$tmp_dir/releases/rel-a/deploy/production/release-manifest.json"
echo '{"images":[]}' >"$tmp_dir/releases/rel-b/deploy/production/release-manifest.json"
ln -s "$tmp_dir/releases/rel-b" "$tmp_dir/current"

for _ in 1 2; do
  RELEASES_DIR="$tmp_dir/releases" CURRENT_LINK="$tmp_dir/current" \
    KEEP_RELEASES=10 KEEP_IMAGE_RELEASES=2 DRY_RUN=true \
    "$prune" >/dev/null 2>&1 ||
    fail "prune failed on a clean host"
done
[ -d "$tmp_dir/releases/rel-a" ] ||
  fail "prune removed a release that was within the retention bound"
[ -d "$tmp_dir/releases/rel-b" ] ||
  fail "prune removed the current release"

# Retention must never be configurable down to a state with no rollback target.
if RELEASES_DIR="$tmp_dir/releases" CURRENT_LINK="$tmp_dir/current" \
  KEEP_IMAGE_RELEASES=1 DRY_RUN=true "$prune" >/dev/null 2>&1; then
  fail "prune accepted an image retention of 1, leaving no rollback target"
fi

echo "release disk hygiene contract: PASS"
