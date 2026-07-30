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
echo "build-release output contract: PASS"
