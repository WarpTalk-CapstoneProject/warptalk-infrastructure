#!/bin/sh
# WT-294. Make it impossible for a migration to pass CI while never reaching the
# database the service that reads it is connected to.
#
# THE FAILURE THIS EXISTS TO CATCH
#   scripts/migrations/ is applied by run-migrations.sh to the legacy monolith
#   database `warptalk`. No service has connected to that database since the
#   logical-database extraction; each one connects to its own warptalk_<service>.
#   A migration written only into scripts/migrations/ therefore reports
#   "Migrations complete." and changes nothing any service can see.
#
#   That is what happened to 050-05-08-2026-add-entitlement-layer.sql (billing
#   and workspace) and 051-06-08-2026-quarantine-translation-stt-confidence.sql
#   (transcript). BillingService raised eighteen 42703 undefined_column errors in
#   production and lost three periodic workers; TranscriptService was one
#   translation away from the same thing.
#
# THREE THINGS ARE CHECKED. All are static: no database is required, so this
# runs on every pull request regardless of WT-288 (CI applies scripts/migrations/
# to no real Postgres at all — it only exercises the migration framework against
# synthetic fixtures, so a check that needed a populated database would have
# nowhere to run).
#
#   1. COVERAGE.  Every schema a service's DbContext maps must be owned by that
#      service's own logical database, and that service must have a staged
#      migration set. A service whose set does not exist has no path for its
#      next migration, which is the root cause of WT-294.
#   2. MIRRORING. A post-cutover migration under scripts/migrations/ that writes
#      to an owned schema must have a counterpart in the owning service's set,
#      or be listed in scripts/migrations/LEGACY-ONLY.txt with a reason.
#   3. STAGING.   The staged copies under scripts/service-migrations/ are what
#      production actually applies (deploy/production/app.compose.yml mounts
#      ../../scripts as /scripts and run-logical-database-migrations.sh reads
#      /scripts/service-migrations). They must equal what
#      collect-service-migrations.sh produces from the backend checkout, or a
#      migration that exists in the backend never ships.
#
# Usage: ./scripts/check-service-migration-coverage.sh [backend-root]
set -eu

root_dir="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
backend_root="${1:-${BACKEND_ROOT:-$root_dir/../warptalk-backend}}"
runner="$root_dir/scripts/run-logical-database-migrations.sh"
acceptance="$root_dir/scripts/check-logical-databases.sh"
collector="$root_dir/scripts/collect-service-migrations.sh"
staged_root="$root_dir/scripts/service-migrations"
legacy_root="$root_dir/scripts/migrations"
allowlist="$legacy_root/LEGACY-ONLY.txt"

# Legacy migrations numbered below this predate the logical-database extraction
# and were applied to the monolith while it was still the only database, so they
# are present in every extracted database by construction. The gate is the
# NUMBER, not the DD-MM-YYYY in the filename, because numbering is monotonic —
# a new migration must take a number above the current maximum — whereas the
# date can be, and in 038 accidentally was, out of order.
legacy_cutover=49

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT INT TERM
: > "$work_dir/failures"

fail() {
  echo "FAIL: $*" >&2
  echo x >> "$work_dir/failures"
}

[ -f "$runner" ] || { echo "Missing $runner" >&2; exit 1; }
[ -f "$acceptance" ] || { echo "Missing $acceptance" >&2; exit 1; }

# ─────────────────────────────────────────────────────────────
# Ownership map, derived from the two scripts that already encode it
# ─────────────────────────────────────────────────────────────
# service -> database, from the runner's own dispatch table. Deriving it rather
# than restating it means a service added to the runner is automatically subject
# to every check below, and a service removed from it stops being checked — the
# map cannot drift from the thing it describes.
#   apply_service auth "${AUTH_DATABASE:-warptalk_auth}" auth warptalk_auth_runtime
sed -n 's/^apply_service \([A-Za-z0-9-]*\) "\${[A-Z_]*:-\([A-Za-z0-9_]*\)}".*/\1 \2/p' \
  "$runner" > "$work_dir/service_databases"
[ -s "$work_dir/service_databases" ] ||
  { echo "Could not parse apply_service lines from $runner" >&2; exit 1; }

# database -> owned schemas, from the extraction acceptance check. This is the
# only place `voice` is recorded as belonging to auth alongside `auth` itself.
#   check_context warptalk_auth warptalk_auth "auth voice"
sed -n 's/^check_context \([A-Za-z0-9_]*\) [A-Za-z0-9_]* "\([A-Za-z0-9_ ]*\)".*/\1 \2/p' \
  "$acceptance" > "$work_dir/database_schemas"
[ -s "$work_dir/database_schemas" ] ||
  { echo "Could not parse check_context lines from $acceptance" >&2; exit 1; }

schemas_for_database() {
  awk -v target="$1" '$1 == target { $1 = ""; sub(/^ /, ""); print }' "$work_dir/database_schemas"
}

# schema -> owning service, flattened once so lookups are a single grep.
: > "$work_dir/schema_owners"
while read -r service database; do
  for schema in $(schemas_for_database "$database"); do
    printf '%s %s\n' "$schema" "$service" >> "$work_dir/schema_owners"
  done
done < "$work_dir/service_databases"
[ -s "$work_dir/schema_owners" ] || { echo "Derived an empty schema ownership map" >&2; exit 1; }

owner_of_schema() {
  awk -v target="$1" '$1 == target { print $2; exit }' "$work_dir/schema_owners"
}

echo "Schema ownership derived from the migration runner and the extraction acceptance check:"
while read -r service database; do
  printf '  %-17s %-28s %s\n' \
    "$service" "$database" "$(schemas_for_database "$database" | tr '\n' ' ')"
done < "$work_dir/service_databases"

# ─────────────────────────────────────────────────────────────
# 1. COVERAGE — a mapped schema with no migration set is the defect
# ─────────────────────────────────────────────────────────────
if [ -d "$backend_root" ]; then
  echo
  echo "Checking DbContext schema coverage against $backend_root..."
  while read -r service database; do
    service_src="$backend_root/$service"
    if [ ! -d "$service_src" ]; then
      echo "  $service: no source tree at $service_src, skipping mapping check."
      continue
    fi

    # Every EF mapping in this codebase is inline in OnModelCreating; there are
    # no IEntityTypeConfiguration classes, so the two-argument ToTable overload
    # plus HasDefaultSchema is the exhaustive source of schema names.
    {
      grep -rhoE 'ToTable\("[^"]+",[[:space:]]*"[^"]+"' "$service_src" 2>/dev/null |
        sed -E 's/.*,[[:space:]]*"([^"]+)".*/\1/'
      grep -rhoE 'HasDefaultSchema\("[^"]+"\)' "$service_src" 2>/dev/null |
        sed -E 's/.*"([^"]+)".*/\1/'
    } | sort -u > "$work_dir/mapped"

    if [ ! -s "$work_dir/mapped" ]; then
      echo "  $service: no schema mappings found in the DbContext."
      continue
    fi

    echo "  $service ($database) maps: $(tr '\n' ' ' < "$work_dir/mapped")"
    while read -r schema; do
      [ -n "$schema" ] || continue
      owner="$(owner_of_schema "$schema")"
      if [ -z "$owner" ]; then
        fail "$service maps schema '$schema', which no logical database owns. Declare it in check-logical-databases.sh or stop mapping it."
      elif [ "$owner" != "$service" ]; then
        fail "$service maps schema '$schema', owned by $owner's database. A DbContext cannot reach across logical databases."
      elif [ ! -d "$staged_root/$owner" ]; then
        fail "$service maps schema '$schema' in $database, but scripts/service-migrations/$owner does not exist, so no migration can ever reach $database. Run ./scripts/collect-service-migrations.sh and commit the result."
      fi
    done < "$work_dir/mapped"
  done < "$work_dir/service_databases"
else
  echo
  echo "NOTE: backend root $backend_root not found; skipping the DbContext coverage check." >&2
  echo "      Pass it as \$1 or set BACKEND_ROOT to run the check that catches WT-294 at its source." >&2
fi

# ─────────────────────────────────────────────────────────────
# 2. MIRRORING — post-cutover legacy DDL must have a service-owned twin
# ─────────────────────────────────────────────────────────────
# Normalise a filename to its slug: drop the ordering prefix (NNN-DD-MM-YYYY-
# for legacy, NNN- or a UTC timestamp plus underscore for service-owned), drop
# the extension, and fold underscores to hyphens so the two naming conventions
# compare. 050-05-08-2026-add-entitlement-layer.sql and
# 20260806090000_add_entitlement_layer.sql both reduce to add-entitlement-layer.
slug_of() {
  printf '%s' "$1" |
    sed -E \
      -e 's/^[0-9]{3}-[0-9]{2}-[0-9]{2}-[0-9]{4}-//' \
      -e 's/^[0-9]{3}-//' \
      -e 's/^[0-9]{8,14}_//' \
      -e 's/\.sql$//' |
    tr 'A-Z_' 'a-z-'
}

echo
echo "Checking legacy migrations numbered >= $legacy_cutover for service-owned counterparts..."
for legacy_path in "$legacy_root"/*.sql; do
  [ -f "$legacy_path" ] || continue
  legacy_file="$(basename "$legacy_path")"

  number="$(printf '%s' "$legacy_file" | sed -n 's/^0*\([0-9][0-9]*\)-.*/\1/p')"
  [ -n "$number" ] || continue
  [ "$number" -ge "$legacy_cutover" ] || continue

  if [ -f "$allowlist" ] && grep -q "^${legacy_file}[[:space:]]*\$\|^${legacy_file}[[:space:]]" "$allowlist"; then
    echo "  $legacy_file: declared legacy-only."
    continue
  fi

  # Strip line comments before looking for schema-qualified writes: every one of
  # these files documents the schemas it touches in its header, and a header is
  # not a write.
  sed -e 's/--.*$//' "$legacy_path" > "$work_dir/body"

  : > "$work_dir/touched"
  while read -r schema _; do
    if grep -qE "(^|[^A-Za-z0-9_.\"])${schema}\." "$work_dir/body"; then
      printf '%s\n' "$schema" >> "$work_dir/touched"
    fi
  done < "$work_dir/schema_owners"
  sort -u "$work_dir/touched" -o "$work_dir/touched"

  if [ ! -s "$work_dir/touched" ]; then
    echo "  $legacy_file: writes to no extracted schema."
    continue
  fi

  slug="$(slug_of "$legacy_file")"
  while read -r schema; do
    [ -n "$schema" ] || continue
    owner="$(owner_of_schema "$schema")"
    match=''
    if [ -d "$staged_root/$owner" ]; then
      for staged_path in "$staged_root/$owner"/*.sql; do
        [ -f "$staged_path" ] || continue
        if [ "$(slug_of "$(basename "$staged_path")")" = "$slug" ]; then
          match="$(basename "$staged_path")"
        fi
      done
    fi
    if [ -n "$match" ]; then
      echo "  $legacy_file -> $schema -> $owner/$match"
    else
      fail "$legacy_file writes to schema '$schema', owned by $owner, but scripts/service-migrations/$owner has no migration with the slug '$slug'. As written it is applied only to the legacy database \`warptalk\` and reaches no service. Add <UTC timestamp>_$(printf '%s' "$slug" | tr '-' '_').sql to warptalk-backend/$owner/database/migrations/, or record $legacy_file in scripts/migrations/LEGACY-ONLY.txt with a reason."
    fi
  done < "$work_dir/touched"
done

# ─────────────────────────────────────────────────────────────
# 3. STAGING — the committed release artifact must equal the backend source
# ─────────────────────────────────────────────────────────────
if [ -d "$backend_root" ] && [ -x "$collector" ]; then
  echo
  echo "Checking the staged release artifact against the backend source..."
  mkdir -p "$work_dir/staging/service-migrations"
  "$collector" "$backend_root" "$work_dir/staging/service-migrations" >/dev/null

  while read -r service _; do
    expected="$work_dir/staging/service-migrations/$service"
    actual="$staged_root/$service"
    [ -d "$expected" ] || continue
    if [ ! -d "$actual" ]; then
      fail "scripts/service-migrations/$service is not committed, so the release bundle has no path for $service migrations. Run ./scripts/collect-service-migrations.sh and commit the result."
      continue
    fi
    if ! diff -r --exclude=README.md "$expected" "$actual" > "$work_dir/staging-diff" 2>&1; then
      fail "scripts/service-migrations/$service does not match warptalk-backend/$service/database/migrations. Production applies the committed copy, so a migration that exists only in the backend never ships."
      sed 's/^/    /' "$work_dir/staging-diff" >&2
    fi
  done < "$work_dir/service_databases"
fi

echo
failure_count="$(wc -l < "$work_dir/failures" | tr -d ' ')"
if [ "$failure_count" -gt 0 ]; then
  echo "Service migration coverage check failed with $failure_count problem(s)." >&2
  exit 1
fi
echo "Service migration coverage checks passed."
