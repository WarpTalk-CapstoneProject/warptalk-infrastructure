#!/bin/sh
set -eu

INFRA_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
WORKSPACE_ROOT="$(CDPATH='' cd -- "$INFRA_ROOT/.." && pwd)"
MATRIX_FILE="${RELEASE_IMAGE_MATRIX:-$INFRA_ROOT/deploy/production/image-matrix.json}"

REGISTRY="${IMAGE_REGISTRY:-}"
RELEASE_TAG="${IMAGE_TAG:-}"
PUSH_IMAGES="${PUSH_IMAGES:-true}"
ALLOW_DIRTY_RELEASE="${ALLOW_DIRTY_RELEASE:-false}"
ONLY_IMAGE="${ONLY_IMAGE:-}"
REUSE_IMAGES="${REUSE_IMAGES:-$PUSH_IMAGES}"
VERIFY_REUSED_IMAGES="${VERIFY_REUSED_IMAGES:-false}"
CACHE_REGISTRY="${BUILD_CACHE_REGISTRY:-$REGISTRY/build-cache}"
BUILD_PARALLELISM="${BUILD_PARALLELISM:-4}"
MANIFEST_OUTPUT="${RELEASE_MANIFEST_OUTPUT:-$INFRA_ROOT/deploy/production/release-manifest.json}"

fail() {
  echo "release build: $*" >&2
  exit 1
}

inspect_remote_digest() {
  image_ref="$1"
  attempt=1
  while [ "$attempt" -le 5 ]; do
    if manifest_json="$(docker buildx imagetools inspect "$image_ref" --format '{{json .Manifest}}')" &&
      digest="$(printf '%s\n' "$manifest_json" | jq -er '.digest')" &&
      echo "$digest" | grep -Eq '^sha256:[a-f0-9]{64}$'; then
      printf '%s\n' "$digest"
      return 0
    fi
    if [ "$attempt" -eq 5 ]; then
      return 1
    fi
    echo "release build: digest lookup failed for $image_ref; retrying ($attempt/5)" >&2
    sleep "$attempt"
    attempt=$((attempt + 1))
  done
}

inspect_existing_digest() {
  image_ref="$1"
  manifest_json="$(docker buildx imagetools inspect "$image_ref" --format '{{json .Manifest}}' 2>/dev/null)" ||
    return 1
  digest="$(printf '%s\n' "$manifest_json" | jq -er '.digest')" || return 1
  echo "$digest" | grep -Eq '^sha256:[a-f0-9]{64}$' || return 1
  printf '%s\n' "$digest"
}

# Run one `docker buildx build --push` so that the BuildKit registry cache can
# never fail the release.
#
# The cache lives in its own GHCR repository ($REGISTRY/build-cache/<image>),
# and release v20 died entirely inside it: `failed to configure registry cache
# importer: failed to fetch oauth token: denied`, a 403 on a build-cache
# manifest HEAD, and `error writing layer blob: permission_denied ... 403` on
# the export. GHCR was throttling; nothing about the code being released was
# wrong. retry_registry in secure-release-images.sh covers the SBOM pull and
# does not reach here. A cache miss must cost build minutes, never a release.
#
# Three layers, cheapest first:
#   1. Import only when the cache manifest is readable right now. BuildKit has
#      no ignore-error for cache IMPORT -- a failed importer aborts the whole
#      solve -- so the decision has to be made before the build starts.
#   2. Export with ignore-error=true, which turns a rejected cache write into a
#      BuildKit warning instead of `failed to solve`.
#   3. If a cached build still fails, rebuild once with no cache flags at all.
#      That is the only cover for a throttle that begins *during* the build,
#      and it absorbs one transient 403 on --push as well. Bounded to one extra
#      attempt: a genuine compile error costs one repeat build and then fails.
build_with_cache() {
  cache_ref="$1"
  build_context="$2"
  shift 2

  if docker buildx imagetools inspect "$cache_ref" >/dev/null 2>&1; then
    if "$@" \
      --cache-from "type=registry,ref=$cache_ref" \
      --cache-to "type=registry,ref=$cache_ref,mode=max,ignore-error=true" \
      "$build_context"; then
      return 0
    fi
    echo "release build: cached build failed for $cache_ref; retrying once without the registry cache" >&2
  else
    echo "release build: $cache_ref is unreadable or absent; building without cache import" >&2
    if "$@" \
      --cache-to "type=registry,ref=$cache_ref,mode=max,ignore-error=true" \
      "$build_context"; then
      return 0
    fi
    echo "release build: build failed for $cache_ref; retrying once without the registry cache" >&2
  fi

  "$@" "$build_context"
}

sha256_text() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

verify_reusable_image() {
  subject="$1"
  expected_repository="$2"
  expected_commit="$3"
  expected_fingerprint="$4"
  cosign verify \
    --certificate-identity-regexp "$COSIGN_CERTIFICATE_IDENTITY_REGEXP" \
    --certificate-oidc-issuer "$COSIGN_CERTIFICATE_OIDC_ISSUER" \
    "$subject" >/dev/null 2>&1 &&
    cosign verify-attestation \
      --type spdxjson \
      --certificate-identity-regexp "$COSIGN_CERTIFICATE_IDENTITY_REGEXP" \
      --certificate-oidc-issuer "$COSIGN_CERTIFICATE_OIDC_ISSUER" \
      "$subject" >/dev/null 2>&1 &&
    provenance_output="$(cosign verify-attestation \
      --type custom \
      --certificate-identity-regexp "$COSIGN_CERTIFICATE_IDENTITY_REGEXP" \
      --certificate-oidc-issuer "$COSIGN_CERTIFICATE_OIDC_ISSUER" \
      "$subject" 2>/dev/null)" &&
    printf '%s\n' "$provenance_output" | jq -s -e \
      --arg sourceRepository "$expected_repository" \
      --arg sourceCommit "$expected_commit" \
      --arg buildFingerprint "$expected_fingerprint" '
      any((.[] | if type == "array" then .[] else . end | .payload);
        (@base64d | fromjson | .predicate) as $predicate |
        $predicate.sourceRepository == $sourceRepository and
        $predicate.sourceCommit == $sourceCommit and
        $predicate.buildFingerprint == $buildFingerprint
      )
    ' >/dev/null 2>&1
}

for dependency in docker jq git; do
  command -v "$dependency" >/dev/null 2>&1 || fail "missing dependency: $dependency"
done

[ -n "$REGISTRY" ] || fail "IMAGE_REGISTRY is required"
[ -n "$RELEASE_TAG" ] || fail "IMAGE_TAG is required"
[ "$RELEASE_TAG" != "latest" ] || fail "IMAGE_TAG=latest is mutable and forbidden"
echo "$RELEASE_TAG" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{6,127}$' ||
  fail "IMAGE_TAG must be an immutable release identifier with at least 7 characters"
case "$REUSE_IMAGES" in
  true|false) ;;
  *) fail "REUSE_IMAGES must be true or false" ;;
esac
case "$VERIFY_REUSED_IMAGES" in
  true|false) ;;
  *) fail "VERIFY_REUSED_IMAGES must be true or false" ;;
esac
case "$BUILD_PARALLELISM" in
  ''|*[!0-9]*|0) fail "BUILD_PARALLELISM must be a positive integer" ;;
esac
if [ "$VERIFY_REUSED_IMAGES" = "true" ]; then
  command -v cosign >/dev/null 2>&1 || fail "cosign is required to verify reusable images"
  : "${COSIGN_CERTIFICATE_IDENTITY_REGEXP:?COSIGN_CERTIFICATE_IDENTITY_REGEXP is required}"
  : "${COSIGN_CERTIFICATE_OIDC_ISSUER:?COSIGN_CERTIFICATE_OIDC_ISSUER is required}"
fi

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
image_entries_tmp="$(mktemp)"
image_records_dir="$(mktemp -d)"
trap 'rm -f "$metadata_tmp" "$images_tmp" "$image_entries_tmp"; rm -rf "$image_records_dir"' EXIT

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

jq -c '.images[]' "$MATRIX_FILE" >"$image_entries_tmp"

process_image() {
  image_entry="$1"
  image_record="$2"
  image_name="$(echo "$image_entry" | jq -r '.name')"
  context_rel="$(echo "$image_entry" | jq -r '.context')"
  dockerfile_rel="$(echo "$image_entry" | jq -r '.dockerfile')"
  target="$(echo "$image_entry" | jq -r '.target // empty')"
  source_repository="$(echo "$image_entry" | jq -r '.repository')"
  source_commit="$(jq -r --arg repository "$source_repository" \
    '.repositories[$repository].commit' "$metadata_tmp")"
  context_dir="$WORKSPACE_ROOT/$context_rel"
  fingerprint_material="$source_commit|$platform|$(printf '%s' "$image_entry" | jq -cS .)"

  for arg_name in $(echo "$image_entry" | jq -r '.buildArgs[]? // empty'); do
    arg_value="$(printenv "$arg_name" 2>/dev/null || true)"
    [ -n "$arg_value" ] || fail "$arg_name is required to build $image_name"
    fingerprint_material="$fingerprint_material|$arg_name=$arg_value"
  done

  build_fingerprint="$(printf '%s' "$fingerprint_material" | sha256_text)"
  image_ref="$REGISTRY/$image_name:src-$build_fingerprint"
  reused=false

  if [ "$PUSH_IMAGES" = "true" ] && [ "$REUSE_IMAGES" = "true" ]; then
    if digest="$(inspect_existing_digest "$image_ref")"; then
      if [ "$VERIFY_REUSED_IMAGES" = "false" ] ||
        verify_reusable_image \
          "$image_ref@$digest" \
          "$source_repository" \
          "$source_commit" \
          "$build_fingerprint"; then
        reused=true
        echo "release build: reusing verified $image_ref@$digest" >&2
      else
        echo "release build: cached digest is unsigned or untrusted; rebuilding $image_ref" >&2
      fi
    fi
  fi

  if [ "$reused" = "false" ]; then
    set -- docker buildx build \
      --platform "$platform" \
      --file "$context_dir/$dockerfile_rel" \
      --tag "$image_ref" \
      --label "org.opencontainers.image.revision=$source_commit"

    if [ -n "$target" ]; then
      set -- "$@" --target "$target"
    fi

    for arg_name in $(echo "$image_entry" | jq -r '.buildArgs[]? // empty'); do
      arg_value="$(printenv "$arg_name" 2>/dev/null || true)"
      set -- "$@" --build-arg "$arg_name=$arg_value"
    done

    if [ "$PUSH_IMAGES" = "true" ]; then
      cache_ref="$CACHE_REGISTRY/$image_name:buildkit"
      set -- "$@" --push
      echo "release build: building $image_ref for $platform" >&2
      build_with_cache "$cache_ref" "$context_dir" "$@" ||
        fail "failed to build $image_ref"
    else
      set -- "$@" --load
      echo "release build: building $image_ref for $platform" >&2
      "$@" "$context_dir"
    fi

    if [ "$PUSH_IMAGES" = "true" ]; then
      digest="$(inspect_remote_digest "$image_ref")" ||
        fail "registry did not return an immutable digest for $image_ref"
    else
      digest="$(docker image inspect "$image_ref" --format '{{.Id}}')"
    fi
  fi

  service_name="$(echo "$image_entry" | jq -r '.service')"
  jq -n \
    --arg name "$image_name" \
    --arg service "$service_name" \
    --arg ref "$image_ref" \
    --arg digest "$digest" \
    --arg source_repository "$source_repository" \
    --arg source_commit "$source_commit" \
    --arg build_fingerprint "$build_fingerprint" \
    --argjson reused "$reused" \
    '{
      name: $name,
      service: $service,
      ref: $ref,
      digest: $digest,
      sourceRepository: $source_repository,
      sourceCommit: $source_commit,
      buildFingerprint: $build_fingerprint,
      reused: $reused
    }' \
    >"$image_record"
}

wait_for_batch() {
  batch_failed=false
  for worker_pid in $batch_pids; do
    if ! wait "$worker_pid"; then
      batch_failed=true
    fi
  done
  [ "$batch_failed" = "false" ] || fail "one or more image builds failed"
}

batch_pids=""
batch_count=0
image_index=0
while IFS= read -r image_entry; do
  image_name="$(echo "$image_entry" | jq -r '.name')"
  if [ -n "$ONLY_IMAGE" ] && [ "$image_name" != "$ONLY_IMAGE" ]; then
    continue
  fi

  image_index=$((image_index + 1))
  image_record="$(printf '%s/%04d.json' "$image_records_dir" "$image_index")"
  process_image "$image_entry" "$image_record" &
  batch_pids="$batch_pids $!"
  batch_count=$((batch_count + 1))
  if [ "$batch_count" -eq "$BUILD_PARALLELISM" ]; then
    wait_for_batch
    batch_pids=""
    batch_count=0
  fi
done <"$image_entries_tmp"

if [ "$batch_count" -gt 0 ]; then
  wait_for_batch
fi

if [ "$image_index" -eq 0 ]; then
  printf '[]\n' >"$images_tmp"
else
  jq -s '.' "$image_records_dir"/*.json >"$images_tmp"
fi

jq --slurpfile images "$images_tmp" '.images = $images[0]' "$metadata_tmp" > "$MANIFEST_OUTPUT"
echo "release build: manifest written to $MANIFEST_OUTPUT"
