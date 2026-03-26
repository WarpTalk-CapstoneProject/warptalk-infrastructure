#!/usr/bin/env bash
# ====================================================================
# WarpTalk — Qdrant Vector DB Backup Script
# ====================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/../backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
QDRANT_URL="${QDRANT_URL:-http://localhost:6333}"
RETENTION_DAYS=30

mkdir -p "$BACKUP_DIR/qdrant"

echo "[$(date)] Starting Qdrant snapshot..."

# Create snapshot via Qdrant API
SNAPSHOT=$(curl -s -X POST "${QDRANT_URL}/snapshots" | jq -r '.result.name // empty')

if [[ -n "$SNAPSHOT" ]]; then
    # Download snapshot
    curl -s "${QDRANT_URL}/snapshots/${SNAPSHOT}" -o "$BACKUP_DIR/qdrant/qdrant_${TIMESTAMP}.snapshot"
    echo "[$(date)] ✅ Qdrant snapshot saved: qdrant_${TIMESTAMP}.snapshot"

    # Cleanup old snapshots
    find "$BACKUP_DIR/qdrant" -name "qdrant_*.snapshot" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
else
    echo "[$(date)] ⚠  Qdrant snapshot failed or Qdrant not running"
fi

echo "[$(date)] Qdrant backup complete."
