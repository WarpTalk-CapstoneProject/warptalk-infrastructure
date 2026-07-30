#!/bin/sh
set -eu

INFRA_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
WORKSPACE_ROOT="$(CDPATH='' cd -- "$INFRA_ROOT/.." && pwd)"
MATRIX_FILE="$INFRA_ROOT/deploy/production/image-matrix.json"

REGISTRY="${IMAGE_REGISTRY:-}"
RELEASE_TAG="${IMAGE_TAG:-}"
PUSH_IMAGES="${PUSH_IMAGES:-true}"
ALLOW_DIRTY_RELEASE="${ALLOW_DIRTY_RELEASE:-false}"
ONLY_IMAGE="${ONLY_IMAGE:-}"
MANIFEST_OUTPUT="${RELEASE_MANIFEST_OUTPUT:-$INFRA_ROOT/deploy/production/release-manifest.json}"

fail() {
  echo "release build: $*" >&2
  exit 1
}

for dependency in docker jq git; do
  command -v "$dependency" >/dev/null 2>&1 || fail "missing dependency: $dependency"
done

[ -n "$REGISTRY" ] || fail "IMAGE_REGISTRY is required"
[ -n "$RELEASE_TAG" ] || fail "IMAGE_TAG is required"
[ "$RELEASE_TAG" != "latest" ] || fail "IMAGE_TAG=latest is mutable and forbidden"
echo "$RELEASE_TAG" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{6,127}$' ||
  fail "IMAGE_TAG must be an immutable release identifier with at least 7 characters"

for repo_name in warptalk-backend warptalk-web warptalk-ai warptalk-infrastructure; do
  repo_dir="$WORKSPACE_ROOT/$repo_name"
  [ -d "$repo_dir/.git" ] || fail "missing Git repository: $repo_dir"
  if [ "$ALLOW_DIRTY_RELEASE" != "true" ] && [ -n "$(git -C "$repo_dir" status --porcelain)" ]; then
    fail "$repo_name has uncommitted changes; commit them or explicitly set ALLOW_DIRTY_RELEASE=true"
  fi
done

platform="$(jq -r '.platform' "$MATRIX_FILE")"
metadata_tmp="$(mktemp)"
images_tmp="$(mktemp)"
trap 'rm -f "$metadata_tmp" "$images_tmp"' EXIT

jq -n \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg registry "$REGISTRY" \
  --arg tag "$RELEASE_TAG" \
  --arg platform "$platform" \
  '{
    schemaVersion: 1,
    generatedAt: $generated_at,
    registry: $registry,
    tag: $tag,
    platform: $platform,
    repositories: {},
    images: []
  }' > "$metadata_tmp"

for repo_name in warptalk-backend warptalk-web warptalk-ai warptalk-infrastructure; do
  repo_dir="$WORKSPACE_ROOT/$repo_name"
  repo_commit="$(git -C "$repo_dir" rev-parse HEAD)"
  if [ -n "$(git -C "$repo_dir" status --porcelain)" ]; then
    repo_dirty=true
  else
    repo_dirty=false
  fi

  jq \
    --arg repo "$repo_name" \
    --arg commit "$repo_commit" \
    --argjson dirty "$repo_dirty" \
    '.repositories[$repo] = { commit: $commit, dirty: $dirty }' \
    "$metadata_tmp" > "$images_tmp"
  mv "$images_tmp" "$metadata_tmp"
done

jq -c '.images[]' "$MATRIX_FILE" | while IFS= read -r image_entry; do
  image_name="$(echo "$image_entry" | jq -r '.name')"
  if [ -n "$ONLY_IMAGE" ] && [ "$image_name" != "$ONLY_IMAGE" ]; then
    continue
  fi

  context_rel="$(echo "$image_entry" | jq -r '.context')"
  dockerfile_rel="$(echo "$image_entry" | jq -r '.dockerfile')"
  target="$(echo "$image_entry" | jq -r '.target // empty')"
  context_dir="$WORKSPACE_ROOT/$context_rel"
  image_ref="$REGISTRY/$image_name:$RELEASE_TAG"

  set -- docker buildx build \
    --platform "$platform" \
    --file "$context_dir/$dockerfile_rel" \
    --tag "$image_ref" \
    --label "org.opencontainers.image.revision=$RELEASE_TAG"

  if [ -n "$target" ]; then
    set -- "$@" --target "$target"
  fi

  for arg_name in $(echo "$image_entry" | jq -r '.buildArgs[]? // empty'); do
    arg_value="$(printenv "$arg_name" 2>/dev/null || true)"
    [ -n "$arg_value" ] || fail "$arg_name is required to build $image_name"
  done

  for arg_name in $(echo "$image_entry" | jq -r '.buildArgs[]? // empty'); do
    arg_value="$(printenv "$arg_name" 2>/dev/null || true)"
    set -- "$@" --build-arg "$arg_name=$arg_value"
  done

  if [ "$PUSH_IMAGES" = "true" ]; then
    set -- "$@" --push
  else
    set -- "$@" --load
  fi

  echo "release build: building $image_ref for $platform"
  "$@" "$context_dir"

  if [ "$PUSH_IMAGES" = "true" ]; then
    digest="$(docker buildx imagetools inspect "$image_ref" --format '{{json .Manifest}}' | jq -r '.digest')"
    echo "$digest" | grep -Eq '^sha256:[a-f0-9]{64}$' ||
      fail "registry did not return an immutable digest for $image_ref"
  else
    digest="$(docker image inspect "$image_ref" --format '{{.Id}}')"
  fi

  service_name="$(echo "$image_entry" | jq -r '.service')"
  jq -n \
    --arg name "$image_name" \
    --arg service "$service_name" \
    --arg ref "$image_ref" \
    --arg digest "$digest" \
    '{name: $name, service: $service, ref: $ref, digest: $digest}'
done | jq -s '.' > "$images_tmp"

jq --slurpfile images "$images_tmp" '.images = $images[0]' "$metadata_tmp" > "$MANIFEST_OUTPUT"
echo "release build: manifest written to $MANIFEST_OUTPUT"
