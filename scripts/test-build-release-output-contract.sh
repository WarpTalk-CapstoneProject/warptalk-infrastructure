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

cat >"$tmp_dir/parallel-matrix.json" <<'JSON'
{
  "schemaVersion": 1,
  "platform": "linux/amd64",
  "images": [
    {"name":"auth-service","service":"auth-service","role":"app","repository":"warptalk-backend","context":"warptalk-backend","dockerfile":"auth/Dockerfile"},
    {"name":"workspace-service","service":"workspace-service","role":"app","repository":"warptalk-backend","context":"warptalk-backend","dockerfile":"workspace/Dockerfile"}
  ]
}
JSON
if ! PATH="$fixture_bin:$PATH" \
  IMAGE_REGISTRY=example.invalid/warptalk \
  IMAGE_TAG=parallel-release \
  PUSH_IMAGES=false \
  ALLOW_DIRTY_RELEASE=true \
  BUILD_PARALLELISM=2 \
  BUILD_RELEASE_PARALLEL_LOG="$tmp_dir/parallel.log" \
  RELEASE_IMAGE_MATRIX="$tmp_dir/parallel-matrix.json" \
  RELEASE_MANIFEST_OUTPUT="$tmp_dir/parallel-release-manifest.json" \
  "$repo_root/scripts/build-release.sh" \
  >"$tmp_dir/parallel-stdout.log" \
  2>"$tmp_dir/parallel-stderr.log"; then
  echo "build-release output contract failed: bounded parallel build did not complete" >&2
  exit 1
fi

[ "$(sed -n '1p' "$tmp_dir/parallel.log" | cut -d' ' -f1)" = start ] &&
  [ "$(sed -n '2p' "$tmp_dir/parallel.log" | cut -d' ' -f1)" = start ] || {
    echo "build-release output contract failed: image builds remained sequential" >&2
    exit 1
  }
jq -e '(.images | length) == 2' "$tmp_dir/parallel-release-manifest.json" >/dev/null

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
  .images[0].digest == "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" and
  .images[0].reused == false and
  (.images[0].ref | test(":src-[a-f0-9]{64}$")) and
  (.images[0].sourceCommit | test("^[a-f0-9]{40}$"))
' "$tmp_dir/pushed-release-manifest.json" >/dev/null

# A content-addressed image already present in the registry must be reused
# without invoking a new build. The security gate verifies it later.
printf '2\n' >"$tmp_dir/reuse-inspect-attempts"
if ! PATH="$fixture_bin:$PATH" \
  IMAGE_REGISTRY=example.invalid/warptalk \
  IMAGE_TAG=another-release \
  PUSH_IMAGES=true \
  REUSE_IMAGES=true \
  ALLOW_DIRTY_RELEASE=true \
  ONLY_IMAGE=auth-service \
  BUILD_RELEASE_INSPECT_STATE="$tmp_dir/reuse-inspect-attempts" \
  RELEASE_MANIFEST_OUTPUT="$tmp_dir/reused-release-manifest.json" \
  "$repo_root/scripts/build-release.sh" \
  >"$tmp_dir/reused-stdout.log" \
  2>"$tmp_dir/reused-stderr.log"; then
  echo "build-release output contract failed: existing digest was not reused" >&2
  exit 1
fi

jq -e '
  (.images | length) == 1 and
  .images[0].reused == true and
  .images[0].digest == "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
' "$tmp_dir/reused-release-manifest.json" >/dev/null
grep -Fq 'release build: reusing ' "$tmp_dir/reused-stderr.log"
if grep -Fq 'release build: building ' "$tmp_dir/reused-stderr.log"; then
  echo "build-release output contract failed: reused digest was rebuilt" >&2
  exit 1
fi

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

if PATH="$fixture_bin:$PATH" \
  IMAGE_REGISTRY=example.invalid/warptalk \
  IMAGE_TAG=test-release \
  PUSH_IMAGES=false \
  ALLOW_DIRTY_RELEASE=true \
  ONLY_IMAGE=frontend \
  NEXT_PUBLIC_GOOGLE_CLIENT_ID=web-client.apps.googleusercontent.com \
  GOOGLE_CLIENT_ID=auth-client.apps.googleusercontent.com \
  RELEASE_MANIFEST_OUTPUT="$tmp_dir/mismatched-google-manifest.json" \
  "$repo_root/scripts/build-release.sh" \
  >"$tmp_dir/mismatched-google-stdout.log" \
  2>"$tmp_dir/mismatched-google-stderr.log"; then
  echo "build-release output contract failed: mismatched Google client IDs returned success" >&2
  exit 1
fi
grep -Fq "NEXT_PUBLIC_GOOGLE_CLIENT_ID must match GOOGLE_CLIENT_ID" \
  "$tmp_dir/mismatched-google-stderr.log"

echo "build-release output contract: PASS"
