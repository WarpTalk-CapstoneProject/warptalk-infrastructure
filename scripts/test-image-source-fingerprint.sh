#!/bin/sh
# Behavioural contract for scripts/image-source-fingerprint.py: an image's fingerprint follows its
# OWN sources, so a release rebuilds and restarts only the services whose code changed.
#
#   1. a commit that touches another service leaves this service's fingerprint unchanged;
#   2. a commit to a shared path changes every service that declares it;
#   3. a project reference or import reaching outside the declared paths refuses the release
#      (a stale image must never be reused because a dependency was not declared);
#   4. every image in the real matrix that declares sourcePaths is well-formed.
set -eu

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
infra_root="$(CDPATH='' cd -- "$script_dir/.." && pwd)"
fingerprint="$script_dir/image-source-fingerprint.py"
work="$(mktemp -d "${TMPDIR:-/tmp}/warptalk-fingerprint.XXXXXX")"
trap 'rm -rf "$work"' EXIT INT TERM

fail() {
  echo "image source fingerprint contract: $*" >&2
  exit 1
}

repo="$work/repo"
mkdir -p "$repo/shared/Lib" "$repo/billing/src/Api" "$repo/auth/src/Api" "$repo/worker_a" "$repo/worker_b"
git -C "$repo" init -q
git -C "$repo" config user.email contract@example.invalid
git -C "$repo" config user.name contract
printf '<Project />\n' >"$repo/shared/Lib/Lib.csproj"
printf '<Project><ItemGroup><ProjectReference Include="..\\..\\..\\shared\\Lib\\Lib.csproj" /></ItemGroup></Project>\n' \
  >"$repo/billing/src/Api/Api.csproj"
cp "$repo/billing/src/Api/Api.csproj" "$repo/auth/src/Api/Api.csproj"
printf 'FROM scratch\n' >"$repo/billing/Dockerfile"
printf 'FROM scratch\n' >"$repo/auth/Dockerfile"
printf 'import shared\n' >"$repo/worker_a/main.py"
printf 'x = 1\n' >"$repo/worker_b/main.py"
printf 'FROM scratch\n' >"$repo/Dockerfile"
git -C "$repo" add -A
git -C "$repo" commit -q -m one

billing='{"name":"billing-service","dockerfile":"billing/Dockerfile","sourcePaths":["billing/","shared/"]}'
auth='{"name":"auth-service","dockerfile":"auth/Dockerfile","sourcePaths":["auth/","shared/"]}'
fp() { python3 "$fingerprint" "$repo" "$(git -C "$repo" rev-parse HEAD)" "$1"; }

billing_1="$(fp "$billing")"
auth_1="$(fp "$auth")"

printf 'changed\n' >"$repo/billing/src/Api/Program.cs"
git -C "$repo" add -A
git -C "$repo" commit -q -m billing-only
[ "$(fp "$auth")" = "$auth_1" ] || fail "a billing-only commit changed auth-service's fingerprint"
[ "$(fp "$billing")" != "$billing_1" ] || fail "a billing commit did not change billing-service's fingerprint"
billing_2="$(fp "$billing")"

printf 'changed\n' >"$repo/shared/Lib/Shared.cs"
git -C "$repo" add -A
git -C "$repo" commit -q -m shared
[ "$(fp "$auth")" != "$auth_1" ] || fail "a shared/ commit did not change auth-service's fingerprint"
[ "$(fp "$billing")" != "$billing_2" ] || fail "a shared/ commit did not change billing-service's fingerprint"

if fp '{"name":"narrow","dockerfile":"billing/Dockerfile","sourcePaths":["billing/"]}' 2>/dev/null; then
  fail "a project reference outside sourcePaths was accepted"
fi

printf 'from worker_b import x\n' >"$repo/worker_a/extra.py"
git -C "$repo" add -A
git -C "$repo" commit -q -m cross-import
if fp '{"name":"ai-a","dockerfile":"Dockerfile","sourcePaths":["worker_a/","shared/"]}' 2>/dev/null; then
  fail "an import of an undeclared sibling package was accepted"
fi
fp '{"name":"ai-a","dockerfile":"Dockerfile","sourcePaths":["worker_a/","worker_b/","shared/"]}' >/dev/null ||
  fail "declaring the imported package did not satisfy the guard"

if fp '{"name":"missing","dockerfile":"Dockerfile","sourcePaths":["nope/"]}' 2>/dev/null; then
  fail "a source path that does not exist was accepted"
fi

jq -e '
  [.images[] | select(.sourcePaths) |
    (.sourcePaths | type == "array" and length > 0 and all(type == "string" and length > 0))]
  | all
' "$infra_root/deploy/production/image-matrix.json" >/dev/null ||
  fail "an image-matrix sourcePaths entry is malformed"

echo "Image source fingerprint contract: PASS"
