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
  find "$source_dir" -maxdepth 1 -type f -name '*.sql' -exec cp '{}' "$destination_dir/" ';'
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
