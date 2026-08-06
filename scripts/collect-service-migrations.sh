#!/bin/sh
set -eu

backend_root="${1:-../warptalk-backend}"
destination_root="${2:-./scripts/service-migrations}"

[ -d "$backend_root" ] || {
  echo "Backend root does not exist: $backend_root" >&2
  exit 1
}

case "$destination_root" in
  */service-migrations|*/service-migrations/) ;;
  *)
    echo "Refusing to stage outside a service-migrations directory: $destination_root" >&2
    exit 1
    ;;
esac

stage_service() {
  service="$1"
  source_dir="$backend_root/$service/database/migrations"
  destination_dir="$destination_root/$service"

  [ -d "$source_dir" ] || {
    echo "Missing migration source directory: $source_dir" >&2
    exit 1
  }

  mkdir -p "$destination_dir"
  find "$destination_dir" -maxdepth 1 -type f -name '*.sql' -delete
  source_files="$(find "$source_dir" -maxdepth 1 -type f -name '*.sql' -print)"
  [ -n "$source_files" ] || {
    # WT-294: an empty set still has to materialise its directory. Git cannot
    # track an empty directory, so without the marker the path is absent from
    # the release bundle and run-logical-database-migrations.sh takes its
    # `[ -d "$dir" ] || return 0` branch — the service is skipped in silence and
    # the first migration it ever gets has nowhere to land.
    echo "No service-owned migrations in $source_dir; staging an empty set for $service."
    : > "$destination_dir/.gitkeep"
    return 0
  }

  rm -f "$destination_dir/.gitkeep"
  printf '%s\n' "$source_files" | while IFS= read -r migration; do
    cp "$migration" "$destination_dir/"
  done
}

stage_service auth
stage_service workspace
stage_service translation-room
stage_service transcript
stage_service notification
stage_service meeting
stage_service assistant
stage_service billing

echo "Service-owned migrations staged in $destination_root."
