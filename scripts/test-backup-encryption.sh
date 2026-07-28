#!/bin/sh
set -eu

for command_name in age age-keygen cmp; do
  command -v "$command_name" >/dev/null 2>&1 ||
    { echo "$command_name is required" >&2; exit 1; }
done

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/warptalk-age-test.XXXXXX")"
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT INT TERM

identity="$work_dir/identity.txt"
recipient="$(age-keygen -o "$identity" 2>&1 | sed -n 's/^Public key: //p')"
[ -n "$recipient" ] || { echo "failed to generate age recipient" >&2; exit 1; }

printf '%s\n' 'WarpTalk backup encryption acceptance fixture' >"$work_dir/plaintext"
"$script_dir/age-file.sh" \
  encrypt "$recipient" "$work_dir/plaintext" "$work_dir/plaintext.age"

if grep -q 'WarpTalk backup encryption acceptance fixture' "$work_dir/plaintext.age"; then
  echo "encrypted file contains plaintext" >&2
  exit 1
fi

"$script_dir/age-file.sh" \
  decrypt "$identity" "$work_dir/plaintext.age" "$work_dir/restored"
cmp "$work_dir/plaintext" "$work_dir/restored"

echo "backup encryption contract: PASS"
