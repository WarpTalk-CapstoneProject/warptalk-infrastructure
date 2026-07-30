#!/bin/sh
set -eu

mode="${1:-}"
key="${2:-}"
source="${3:-}"
target="${4:-}"

[ -n "$key" ] || { echo "age-file: recipient or identity is required" >&2; exit 1; }
[ -f "$source" ] || { echo "age-file: source file does not exist" >&2; exit 1; }
[ -n "$target" ] || { echo "age-file: target file is required" >&2; exit 1; }
command -v age >/dev/null 2>&1 || { echo "age-file: age is required" >&2; exit 1; }

case "$mode" in
  encrypt)
    age --encrypt --recipient "$key" --output "$target" "$source"
    ;;
  decrypt)
    [ -f "$key" ] || { echo "age-file: identity file does not exist" >&2; exit 1; }
    age --decrypt --identity "$key" --output "$target" "$source"
    ;;
  *)
    echo "usage: age-file.sh encrypt RECIPIENT SOURCE TARGET" >&2
    echo "       age-file.sh decrypt IDENTITY_FILE SOURCE TARGET" >&2
    exit 1
    ;;
esac

test -s "$target"
