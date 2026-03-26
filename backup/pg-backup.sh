#!/usr/bin/env bash
# ====================================================================
# WarpTalk — PostgreSQL Backup Script
# Daily pg_dump → compressed file → optional S3/MinIO upload
#
# Usage:
#   ./pg-backup.sh                # Backup to local ./backups/
#   ./pg-backup.sh --upload-s3    # Backup + upload to S3
#
# Crontab (daily at 2 AM):
#   0 2 * * * /path/to/pg-backup.sh --upload-s3 >> /var/log/warptalk-backup.log 2>&1
# ====================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/../backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="warptalk_${TIMESTAMP}.sql.gz"
RETENTION_DAYS=30

# Database config (override via environment)
PG_HOST="${PG_HOST:-localhost}"
PG_PORT="${PG_PORT:-5432}"
PG_USER="${PG_USER:-postgres}"
PG_DB="${PG_DB:-warptalk}"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

mkdir -p "$BACKUP_DIR"

echo "[$(date)] Starting PostgreSQL backup..."

# Dump all schemas
PGPASSWORD="${POSTGRES_PASSWORD:-postgres}" pg_dump \
    -h "$PG_HOST" \
    -p "$PG_PORT" \
    -U "$PG_USER" \
    -d "$PG_DB" \
    --no-owner \
    --no-acl \
    --verbose \
    2>/dev/null | gzip > "$BACKUP_DIR/$BACKUP_FILE"

FILE_SIZE=$(du -sh "$BACKUP_DIR/$BACKUP_FILE" | cut -f1)
echo -e "[$(date)] ${GREEN}✅ Backup created: $BACKUP_FILE ($FILE_SIZE)${NC}"

# Upload to S3/MinIO if requested
if [[ "${1:-}" == "--upload-s3" ]]; then
    if command -v aws &>/dev/null; then
        aws s3 cp "$BACKUP_DIR/$BACKUP_FILE" \
            "s3://${BACKUP_S3_BUCKET:-warptalk-backups}/postgres/$BACKUP_FILE" \
            --endpoint-url "${BACKUP_S3_ENDPOINT:-}" \
            2>/dev/null
        echo -e "[$(date)] ${GREEN}✅ Uploaded to S3${NC}"
    else
        echo -e "[$(date)] ${RED}⚠  aws CLI not found, skipping S3 upload${NC}"
    fi
fi

# Cleanup old backups
echo "[$(date)] Cleaning backups older than ${RETENTION_DAYS} days..."
find "$BACKUP_DIR" -name "warptalk_*.sql.gz" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true

echo "[$(date)] Backup complete."
