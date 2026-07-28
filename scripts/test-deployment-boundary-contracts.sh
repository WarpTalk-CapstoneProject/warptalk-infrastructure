#!/bin/sh
set -eu

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
production_check="$script_dir/check-production-deployment.sh"
database_check="$script_dir/check-database-boundaries.sh"

grep -q "internal Warptalk image" "$production_check"
if grep -q "any(.images\\[\\].*compose" "$production_check"; then
  echo "production image comparison still filters unknown images through the matrix" >&2
  exit 1
fi

grep -q "regexp_matches" "$database_check"
grep -q "<> view_definition.schemaname" "$database_check"
if grep -q "definition !~" "$database_check"; then
  echo "cross-schema view check still ignores mixed local/foreign references" >&2
  exit 1
fi

echo "deployment image and database boundary contracts passed"
