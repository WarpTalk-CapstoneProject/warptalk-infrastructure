#!/bin/sh
set -eu

repo_root="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
fixture_bin="$repo_root/scripts/test-fixtures/build-release-bin"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

if ! PATH="$fixture_bin:$PATH" \
  IMAGE_REGISTRY=example.invalid/warptalk \
  IMAGE_TAG=test-release \
  PUSH_IMAGES=false \
  ALLOW_DIRTY_RELEASE=true \
  ONLY_IMAGE=auth-service \
  RELEASE_MANIFEST_OUTPUT="$tmp_dir/release-manifest.json" \
  "$repo_root/scripts/build-release.sh" \
  >"$tmp_dir/stdout.log" \
  2>"$tmp_dir/stderr.log"; then
  echo "build-release output contract failed: release build did not complete" >&2
  exit 1
fi

jq -e '
  .tag == "test-release" and
  (.images | length) == 1 and
  .images[0].service == "auth-service" and
  .images[0].digest == "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
' "$tmp_dir/release-manifest.json" >/dev/null

if grep -Fq 'release build: building ' "$tmp_dir/stdout.log"; then
  echo "build-release output contract failed: progress log polluted JSON stdout" >&2
  exit 1
fi

grep -Fq 'release build: building ' "$tmp_dir/stderr.log"

if ! PATH="$fixture_bin:$PATH" \
  IMAGE_REGISTRY=example.invalid/warptalk \
  IMAGE_TAG=test-release \
  PUSH_IMAGES=true \
  ALLOW_DIRTY_RELEASE=true \
  ONLY_IMAGE=auth-service \
  BUILD_RELEASE_INSPECT_STATE="$tmp_dir/inspect-attempts" \
  RELEASE_MANIFEST_OUTPUT="$tmp_dir/pushed-release-manifest.json" \
  "$repo_root/scripts/build-release.sh" \
  >"$tmp_dir/pushed-stdout.log" \
  2>"$tmp_dir/pushed-stderr.log"; then
  echo "build-release output contract failed: transient digest lookup was not retried" >&2
  exit 1
fi

[ "$(cat "$tmp_dir/inspect-attempts")" -eq 3 ] || {
  echo "build-release output contract failed: unexpected digest lookup attempt count" >&2
  exit 1
}

jq -e '
  (.images | length) == 1 and
  .images[0].digest == "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
' "$tmp_dir/pushed-release-manifest.json" >/dev/null

rm -f "$tmp_dir/release-manifest.json"
if PATH="$fixture_bin:$PATH" \
  IMAGE_REGISTRY=example.invalid/warptalk \
  IMAGE_TAG=test-release \
  PUSH_IMAGES=false \
  ALLOW_DIRTY_RELEASE=true \
  ONLY_IMAGE=frontend \
  RELEASE_MANIFEST_OUTPUT="$tmp_dir/release-manifest.json" \
  "$repo_root/scripts/build-release.sh" \
  >"$tmp_dir/missing-arg-stdout.log" \
  2>"$tmp_dir/missing-arg-stderr.log"; then
  echo "build-release output contract failed: missing build arg returned success" >&2
  exit 1
fi

if [ -e "$tmp_dir/release-manifest.json" ]; then
  echo "build-release output contract failed: incomplete manifest was written" >&2
  exit 1
fi

echo "build-release output contract: PASS"
