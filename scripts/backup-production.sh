#!/bin/sh
# Encrypted, tiered, offsite production backup for all WarpTalk-owned data.
set -eu

: "${BACKUP_ROOT:?BACKUP_ROOT is required}"
: "${AGE_RECIPIENT:?AGE_RECIPIENT is required}"
: "${PGHOST:?PGHOST is required}"
: "${PGPORT:?PGPORT is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"
: "${QDRANT_URL:?QDRANT_URL is required}"

case "$BACKUP_ROOT" in
  /|""|/tmp) echo "BACKUP_ROOT is too broad: $BACKUP_ROOT" >&2; exit 1 ;;
esac

for command_name in age sha256sum; do
  command -v "$command_name" >/dev/null 2>&1 ||
    { echo "$command_name is required" >&2; exit 1; }
done

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
staging="$(mktemp -d "${TMPDIR:-/tmp}/warptalk-backup.XXXXXX")"
daily_dir="$BACKUP_ROOT/daily/$stamp"

cleanup() {
  rm -rf "$staging"
}
trap cleanup EXIT INT TERM

mkdir -p "$daily_dir" "$BACKUP_ROOT/weekly" "$BACKUP_ROOT/monthly"

BACKUP_DIR="$staging" "$script_dir/backup-logical-databases.sh"
logical_dump_count="$(
  find "$staging" -maxdepth 1 -type f -name '*.dump' |
    wc -l |
    tr -d ' '
)"
[ "$logical_dump_count" -eq 8 ] || {
  echo "Refusing to continue: expected 8 logical database dumps, found $logical_dump_count" >&2
  exit 1
}

BACKUP_DIR="$staging" BACKUP_STAMP="$stamp" \
  "$script_dir/../backup/qdrant-backup.sh"

find "$staging" -type f \( -name '*.dump' -o -name '*.snapshot' \) -print |
while IFS= read -r source; do
  relative="${source#"$staging"/}"
  target="$daily_dir/$relative.age"
  mkdir -p "$(dirname "$target")"
  "$script_dir/age-file.sh" encrypt "$AGE_RECIPIENT" "$source" "$target"
done

# Manifests contain no secrets and remain readable during an incident.
find "$staging" -type f ! \( -name '*.dump' -o -name '*.snapshot' \) -print |
while IFS= read -r source; do
  relative="${source#"$staging"/}"
  target="$daily_dir/$relative"
  mkdir -p "$(dirname "$target")"
  cp "$source" "$target"
done

(
  cd "$daily_dir"
  find . -type f ! -name encrypted-files.sha256 -print0 |
    sort -z |
    xargs -0 sha256sum
) > "$daily_dir/encrypted-files.sha256"

date -u +%u | grep -q '^7$' && cp -al "$daily_dir" "$BACKUP_ROOT/weekly/$stamp"
date -u +%d | grep -q '^01$' && cp -al "$daily_dir" "$BACKUP_ROOT/monthly/$stamp"

prune_tier() {
  tier="$1"
  keep="$2"
  directory="$BACKUP_ROOT/$tier"
  count="$(find "$directory" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
  remove_count=$((count - keep))
  [ "$remove_count" -gt 0 ] || return 0

  prune_list="$(mktemp)"
  find "$directory" -mindepth 1 -maxdepth 1 -type d -print |
    sort |
    head -n "$remove_count" >"$prune_list"
  while IFS= read -r old; do
    case "$old" in
      "$directory"/20????????T??????Z) rm -rf "$old" ;;
      *)
        rm -f "$prune_list"
        echo "Refusing to prune unsafe path: $old" >&2
        return 1
        ;;
    esac
  done <"$prune_list"
  rm -f "$prune_list"
}

prune_tier daily 7
prune_tier weekly 4
prune_tier monthly 3

if [ -n "${BACKUP_S3_BUCKET:-}" ]; then
  command -v aws >/dev/null 2>&1 || { echo "aws CLI is required for offsite backup" >&2; exit 1; }
  endpoint_args=""
  if [ -n "${BACKUP_S3_ENDPOINT:-}" ]; then
    endpoint_args="--endpoint-url $BACKUP_S3_ENDPOINT"
  fi

  # shellcheck disable=SC2086
  versioning="$(
    aws $endpoint_args s3api get-bucket-versioning \
      --bucket "$BACKUP_S3_BUCKET" \
      --query Status \
      --output text
  )"
  [ "$versioning" = "Enabled" ] ||
    { echo "Offsite bucket versioning must be Enabled" >&2; exit 1; }

  # shellcheck disable=SC2086
  aws $endpoint_args s3 cp \
    "$daily_dir" "s3://$BACKUP_S3_BUCKET/warptalk/daily/$stamp/" \
    --recursive --only-show-errors
fi

echo "Encrypted WarpTalk backup completed: $daily_dir"
