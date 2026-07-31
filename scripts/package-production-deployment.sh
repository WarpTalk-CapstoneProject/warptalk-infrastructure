#!/bin/sh
set -eu

OUTPUT="${OUTPUT:-}"

fail() {
  echo "package-production-deployment: $*" >&2
  exit 1
}

[ -n "$OUTPUT" ] || fail "OUTPUT is required"
case "$OUTPUT" in
  /*.tar.gz) ;;
  *) fail "OUTPUT must be an absolute .tar.gz path" ;;
esac

repo_root="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
output_parent="$(dirname "$OUTPUT")"
[ -d "$output_parent" ] || fail "OUTPUT parent directory does not exist"
[ ! -e "$OUTPUT" ] || fail "OUTPUT already exists"
[ ! -e "$OUTPUT.sha256" ] || fail "checksum output already exists"

for path in deploy/production scripts observability pgbouncer; do
  [ -e "$repo_root/$path" ] || fail "required package path is missing: $path"
done

COPYFILE_DISABLE=1 tar \
  --no-xattrs \
  --exclude='deploy/production/.env.production' \
  --exclude='deploy/production/release-manifest.json' \
  --exclude='deploy/production/backup.env' \
  -C "$repo_root" \
  -czf "$OUTPUT" \
  deploy/production scripts observability pgbouncer

if tar -tzf "$OUTPUT" |
  grep -Eq '(^|/)(\.env\.production|release-manifest\.json|backup\.env)$'; then
  fail "package contains a runtime secret or release file"
fi

shasum -a 256 "$OUTPUT" >"$OUTPUT.sha256"
echo "package-production-deployment: PASS output=$OUTPUT"
