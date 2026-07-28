#!/bin/sh
# Restore all logical databases and Qdrant collection snapshots into disposable containers.
set -eu

: "${BACKUP_SET:?BACKUP_SET is required}"

command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

test -d "$BACKUP_SET" || { echo "Backup set does not exist: $BACKUP_SET" >&2; exit 1; }
case "$BACKUP_SET" in /|""|/tmp) echo "Unsafe BACKUP_SET: $BACKUP_SET" >&2; exit 1 ;; esac

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
postgres_image="${POSTGRES_RESTORE_IMAGE:-postgres:18-alpine}"
qdrant_image="${QDRANT_RESTORE_IMAGE:-qdrant/qdrant:v1.15.3}"
run_id="warptalk-restore-$$"
postgres_container="$run_id-postgres"
qdrant_container="$run_id-qdrant"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/warptalk-restore.XXXXXX")"
report="${RESTORE_REPORT:-${TMPDIR:-/tmp}/warptalk-restore-drill-$(basename "$BACKUP_SET").json}"

cleanup() {
  docker rm -f "$postgres_container" "$qdrant_container" >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT INT TERM

if [ -f "$BACKUP_SET/encrypted-files.sha256" ]; then
  (cd "$BACKUP_SET" && sha256sum -c encrypted-files.sha256)
fi

materialize() {
  source="$1"
  target="$2"
  mkdir -p "$(dirname "$target")"
  case "$source" in
    *.age)
      : "${AGE_IDENTITY_FILE:?AGE_IDENTITY_FILE is required for encrypted backups}"
      "$script_dir/age-file.sh" decrypt "$AGE_IDENTITY_FILE" "$source" "$target"
      ;;
    *) cp "$source" "$target" ;;
  esac
}

find "$BACKUP_SET" -type f \( -name '*.dump' -o -name '*.dump.age' \) -print |
while IFS= read -r dump; do
  target="$work_dir/$(basename "${dump%.age}")"
  materialize "$dump" "$target"
done

expected_databases="
warptalk_auth
warptalk_workspace
warptalk_translation_room
warptalk_transcript
warptalk_notification
warptalk_meeting
warptalk_assistant
warptalk_billing
"

docker run -d --name "$postgres_container" \
  -e POSTGRES_PASSWORD=restore-drill-only \
  "$postgres_image" >/dev/null

attempt=0
until docker exec "$postgres_container" pg_isready -U postgres >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 60 ] || { echo "Disposable PostgreSQL did not become ready" >&2; exit 1; }
  sleep 1
done

database_results="$work_dir/database-results.jsonl"
: > "$database_results"
printf '%s\n' "$expected_databases" | sed '/^$/d' | while IFS= read -r database; do
  dump="$(find "$work_dir" -maxdepth 1 -type f -name "$database-*.dump" | head -n 1)"
  test -n "$dump" || { echo "Missing dump for $database" >&2; exit 1; }
  test -s "$dump"

  docker cp "$dump" "$postgres_container:/tmp/$database.dump" >/dev/null
  docker exec "$postgres_container" pg_restore --list "/tmp/$database.dump" >/dev/null
  docker exec "$postgres_container" createdb -U postgres "$database"
  docker exec "$postgres_container" \
    pg_restore -U postgres --exit-on-error --no-owner --no-acl \
    -d "$database" "/tmp/$database.dump"
  table_count="$(
    docker exec "$postgres_container" psql -X -U postgres -d "$database" -Atc \
      "SELECT count(*) FROM information_schema.tables
       WHERE table_schema NOT IN ('pg_catalog','information_schema');"
  )"
  [ "$table_count" -gt 0 ] || { echo "Restored database $database has no domain tables" >&2; exit 1; }
  jq -nc --arg database "$database" --argjson tables "$table_count" \
    '{database:$database,tables:$tables,status:"restored"}' >> "$database_results"
done

qdrant_results="$work_dir/qdrant-results.jsonl"
: > "$qdrant_results"
qdrant_manifest="$(find "$BACKUP_SET" -type f -name 'collections-*.jsonl' | head -n 1)"
if [ -n "$qdrant_manifest" ] && [ -s "$qdrant_manifest" ]; then
  docker run -d --name "$qdrant_container" -p 127.0.0.1::6333 "$qdrant_image" >/dev/null
  qdrant_port="$(docker port "$qdrant_container" 6333/tcp | sed 's/.*://')"
  attempt=0
  until curl --fail --silent "http://127.0.0.1:$qdrant_port/readyz" >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 60 ] || { echo "Disposable Qdrant did not become ready" >&2; exit 1; }
    sleep 1
  done

  while IFS= read -r item; do
    collection="$(printf '%s' "$item" | jq -er '.collection')"
    file="$(printf '%s' "$item" | jq -er '.file')"
    expected_points="$(printf '%s' "$item" | jq -er '.points_count')"
    source="$(find "$BACKUP_SET" -type f \( -name "$file" -o -name "$file.age" \) | head -n 1)"
    test -n "$source" || { echo "Missing Qdrant snapshot: $file" >&2; exit 1; }
    snapshot="$work_dir/$file"
    materialize "$source" "$snapshot"

    curl --fail --silent --show-error \
      -X POST \
      "http://127.0.0.1:$qdrant_port/collections/$collection/snapshots/upload?priority=snapshot" \
      -F "snapshot=@$snapshot" >/dev/null
    actual_points="$(
      curl --fail --silent "http://127.0.0.1:$qdrant_port/collections/$collection" |
        jq -er '.result.points_count'
    )"
    [ "$actual_points" = "$expected_points" ] ||
      { echo "Qdrant point-count mismatch for $collection" >&2; exit 1; }
    jq -nc \
      --arg collection "$collection" \
      --argjson points "$actual_points" \
      '{collection:$collection,points:$points,status:"restored"}' >> "$qdrant_results"
  done < "$qdrant_manifest"
fi

jq -n \
  --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --slurpfile databases "$database_results" \
  --slurpfile qdrant "$qdrant_results" \
  '{
    status:"passed",
    completed_at:$completed_at,
    databases:$databases,
    qdrant_collections:$qdrant
  }' > "$report"

echo "Restore drill passed. Report: $report"
