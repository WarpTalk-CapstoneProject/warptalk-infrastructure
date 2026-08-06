#!/bin/sh
# Bounded, idempotent retention for immutable release artifacts on one host.
#
# The app host filled to 100% because nothing ever removed anything. Releases
# accumulated 43 directories and 377 images; only 21 images were in use and
# 76% of the image store was reclaimable. Two separate mechanisms produced the
# duplicates:
#
#   1. build-release.sh fingerprints an image as
#      sha256(source_commit | platform | matrix_entry), so the tag tracks the
#      COMMIT of the whole source repository rather than the individual
#      service's inputs. One commit to warptalk-backend gives all nine backend
#      services a new tag, and one commit to warptalk-ai gives all ten workers
#      a new tag, so every release lands a fresh full copy of every image in
#      that repository even when the service itself did not change.
#   2. plan-release-deployment.sh forces a full deploy whenever the
#      warptalk-infrastructure commit changes, which is nearly every release,
#      so every role re-pulls its entire image set rather than the changed
#      services.
#
# Both are deliberately left alone here: changing the fingerprint or the
# planner changes what gets deployed, which is not a disk-hygiene change. This
# script instead bounds what is RETAINED, which is safe and self-contained.
#
# Retention model
#   - Release directories are kept for forensics. They are ~2MiB each, so a
#     generous count costs almost nothing.
#   - Images are kept for exactly two generations: the running release and its
#     immediate predecessor, which is the rollback target. Anything older is
#     re-pullable from GHCR by immutable digest, so retaining it locally buys
#     nothing and is what filled the disk.
#
# This script NEVER touches volumes. Named volumes hold PostgreSQL data, MinIO
# objects and Redis state, so no volume-removing command or flag appears
# anywhere in this file; test-release-disk-hygiene-contract.sh enforces that.
# It also never stops, restarts or recreates a container, so it is safe to run
# against a live host.
set -eu

RELEASES_DIR="${RELEASES_DIR:-/opt/warptalk/releases}"
CURRENT_LINK="${CURRENT_LINK:-/opt/warptalk/current}"
# Release directories retained (metadata only, ~2MiB each).
KEEP_RELEASES="${KEEP_RELEASES:-10}"
# Release generations whose images stay resident: 2 = running + rollback target.
KEEP_IMAGE_RELEASES="${KEEP_IMAGE_RELEASES:-2}"
IMAGE_REGISTRY_PREFIX="${IMAGE_REGISTRY_PREFIX:-ghcr.io/warptalk-capstoneproject/}"
DRY_RUN="${DRY_RUN:-false}"

case "$DRY_RUN" in
  true|false) ;;
  *) echo "prune: DRY_RUN must be true or false" >&2; exit 1 ;;
esac
for var in KEEP_RELEASES KEEP_IMAGE_RELEASES; do
  eval "value=\$$var"
  echo "$value" | grep -Eq '^[0-9]+$' && [ "$value" -ge 1 ] || {
    echo "prune: $var must be a positive integer" >&2
    exit 1
  }
done
[ "$KEEP_IMAGE_RELEASES" -ge 2 ] || {
  echo "prune: KEEP_IMAGE_RELEASES must be at least 2 so a rollback target survives" >&2
  exit 1
}
[ "$KEEP_RELEASES" -ge "$KEEP_IMAGE_RELEASES" ] || {
  echo "prune: KEEP_RELEASES must be >= KEEP_IMAGE_RELEASES" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || { echo "prune: jq is required" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "prune: docker is required" >&2; exit 1; }
test -d "$RELEASES_DIR" || { echo "prune: no releases directory at $RELEASES_DIR" >&2; exit 0; }

run() {
  if [ "$DRY_RUN" = "true" ]; then
    echo "DRY-RUN: $*"
  else
    "$@"
  fi
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

current_release=''
if [ -L "$CURRENT_LINK" ]; then
  current_release="$(basename "$(readlink -f "$CURRENT_LINK")")"
fi

# Order releases newest-first by mtime. The staging step in release.yml creates
# each directory at deploy time, so mtime is the deployment order.
find "$RELEASES_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %f\n' 2>/dev/null |
  sort -rn | awk '{print $2}' >"$work/all"

# Split around the running release. A directory NEWER than current is a release
# that was staged but is not live -- either the one being deployed right now, or
# one whose deploy failed part-way, which is exactly the state this host was
# found in. Those are never the rollback target, so they must not be counted
# against the retention budget: doing so would evict the genuine predecessor.
: >"$work/newer"
: >"$work/older"
: >"$work/current"
if [ -n "$current_release" ] && grep -qxF "$current_release" "$work/all"; then
  echo "$current_release" >"$work/current"
  awk -v cur="$current_release" -v newer="$work/newer" -v older="$work/older" \
    'BEGIN { side = newer }
     $0 == cur { side = older; next }
     { print > side }' "$work/all"
else
  cp "$work/all" "$work/older"
fi

# Keep order: staged-but-not-live releases, then the running one, then history.
cat "$work/newer" "$work/current" "$work/older" >"$work/ordered"

# Directories are cheap (~2MiB); keep a generous window of history.
head -n "$KEEP_RELEASES" "$work/ordered" >"$work/keep_dirs"

# Images are the expensive part. Retain them for any staged release, the running
# release, and the (KEEP_IMAGE_RELEASES - 1) most recent releases that predate
# the running one -- so the rollback target always keeps its images.
head -n "$((KEEP_IMAGE_RELEASES - 1))" "$work/older" >"$work/older_keep"
cat "$work/newer" "$work/current" "$work/older_keep" >"$work/keep_images"

echo "prune: current release: ${current_release:-<none>}"
echo "prune: $(wc -l <"$work/ordered") release dir(s); keeping $(wc -l <"$work/keep_dirs")," \
  "images for $(wc -l <"$work/keep_images") generation(s)"

# ---------------------------------------------------------------- directories
removed_dirs=0
while IFS= read -r name; do
  [ -n "$name" ] || continue
  grep -qxF "$name" "$work/keep_dirs" && continue
  # Refuse anything that is not a plain, safe directory name.
  echo "$name" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$' || {
    echo "prune: skipping unsafe release name: $name" >&2
    continue
  }
  [ "$name" = "$current_release" ] && continue
  target="$RELEASES_DIR/$name"
  [ -d "$target" ] || continue
  [ -L "$target" ] && continue
  size="$(du -sh "$target" 2>/dev/null | awk '{print $1}')"
  echo "prune: removing release directory $name ($size)"
  run rm -rf -- "$target"
  removed_dirs=$((removed_dirs + 1))
done <"$work/ordered"

# -------------------------------------------------------------------- images
# Protected = every digest named by a kept release manifest, plus every image
# any container currently references (running or exited).
: >"$work/protect"
while IFS= read -r name; do
  [ -n "$name" ] || continue
  manifest="$RELEASES_DIR/$name/deploy/production/release-manifest.json"
  [ -r "$manifest" ] || continue
  jq -r '.images[]?.digest // empty' "$manifest" 2>/dev/null |
    sed 's/^sha256://' >>"$work/protect"
done <"$work/keep_images"

for container in $(docker ps -aq 2>/dev/null); do
  docker inspect -f '{{.Image}}' "$container" 2>/dev/null |
    sed 's/^sha256://' >>"$work/protect"
done
sort -u "$work/protect" -o "$work/protect"

docker images --no-trunc --format '{{.ID}}|{{.Repository}}' 2>/dev/null |
  sed 's/^sha256://' | sort -u >"$work/images"
awk -F'|' '{print $1}' "$work/images" | sort -u >"$work/image_ids"
comm -23 "$work/image_ids" "$work/protect" >"$work/unprotected"

# Only ever consider WarpTalk's own images. Third-party images (caddy, redis,
# postgres, curl, grpcurl) and locally built tools are left alone.
: >"$work/delete"
while IFS= read -r id; do
  [ -n "$id" ] || continue
  repo="$(awk -F'|' -v i="$id" '$1==i {print $2; exit}' "$work/images")"
  case "$repo" in
    "$IMAGE_REGISTRY_PREFIX"*) echo "$id" >>"$work/delete" ;;
  esac
done <"$work/unprotected"

echo "prune: $(wc -l <"$work/protect") protected image id(s)," \
  "$(wc -l <"$work/delete") removable"

removed_images=0
refused_images=0
while IFS= read -r id; do
  [ -n "$id" ] || continue
  if [ "$DRY_RUN" = "true" ]; then
    echo "DRY-RUN: docker rmi sha256:$id"
    removed_images=$((removed_images + 1))
    continue
  fi
  # Deliberately not forced: if anything still holds the image, Docker refuses
  # and we move on rather than pulling the rug out from under a live container.
  if docker rmi "sha256:$id" >/dev/null 2>&1; then
    removed_images=$((removed_images + 1))
  else
    refused_images=$((refused_images + 1))
  fi
done <"$work/delete"

# ---------------------------------------------------------------- build cache
# Production hosts pull images, they never build them. Any build cache here is
# pure waste; on this host it had grown to 13.91GB.
cache_before="$(docker builder du 2>/dev/null | awk -F'\t' '/^Total:/ {print $2}' || true)"
run docker builder prune -f >/dev/null 2>&1 || true

echo "prune: removed $removed_dirs release dir(s), $removed_images image(s)," \
  "$refused_images still referenced, build cache was ${cache_before:-unknown}"
df -Ph "${DISK_TARGET_PATH:-/var/lib/containerd}" 2>/dev/null | tail -1 ||
  df -Ph / | tail -1
