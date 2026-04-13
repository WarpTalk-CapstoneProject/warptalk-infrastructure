#!/usr/bin/env bash
# ====================================================================
# WarpTalk — Initialize Database
# Runs init-db.sql against a running PostgreSQL instance
# Passwords are read from .env (never hardcoded in SQL)
#
# Usage:
#   ./init-db.sh                 # uses default localhost:5432
#   ./init-db.sh --docker        # runs against warptalk-postgres container
# ====================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
SQL_FILE="$SCRIPT_DIR/init-db.sql"

# Load .env if it exists
if [[ -f "$INFRA_DIR/.env" ]]; then
    set -a
    source "$INFRA_DIR/.env"
    set +a
fi

PG_HOST="${PG_HOST:-localhost}"
PG_PORT="${PG_PORT:-5432}"
PG_USER="${PG_USER:-postgres}"
PG_DB="${PG_DB:-warptalk}"

# Default passwords (override via .env in production!)
AUTH_DB_PASSWORD="${AUTH_DB_PASSWORD:-changeme_auth}"
TRANSLATION_ROOM_DB_PASSWORD="${TRANSLATION_ROOM_DB_PASSWORD:-changeme_translation_room}"
TRANSCRIPT_DB_PASSWORD="${TRANSCRIPT_DB_PASSWORD:-changeme_transcript}"
SUBSCRIPTION_DB_PASSWORD="${SUBSCRIPTION_DB_PASSWORD:-changeme_subscription}"
NOTIFICATION_DB_PASSWORD="${NOTIFICATION_DB_PASSWORD:-changeme_notification}"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}🐘 Initializing WarpTalk database...${NC}"

PSQL_VARS=(
    -v "AUTH_DB_PASSWORD=$AUTH_DB_PASSWORD"
    -v "TRANSLATION_ROOM_DB_PASSWORD=$TRANSLATION_ROOM_DB_PASSWORD"
    -v "TRANSCRIPT_DB_PASSWORD=$TRANSCRIPT_DB_PASSWORD"
    -v "SUBSCRIPTION_DB_PASSWORD=$SUBSCRIPTION_DB_PASSWORD"
    -v "NOTIFICATION_DB_PASSWORD=$NOTIFICATION_DB_PASSWORD"
)

if [[ "${1:-}" == "--docker" ]]; then
    echo "   Running via Docker container: warptalk-postgres"
    docker exec -i warptalk-postgres psql -U "$PG_USER" -d "$PG_DB" \
        "${PSQL_VARS[@]}" < "$SQL_FILE"
else
    echo "   Running against ${PG_HOST}:${PG_PORT}"
    PGPASSWORD="${POSTGRES_PASSWORD:-postgres}" psql \
        -h "$PG_HOST" \
        -p "$PG_PORT" \
        -U "$PG_USER" \
        -d "$PG_DB" \
        "${PSQL_VARS[@]}" \
        -f "$SQL_FILE"
fi

echo -e "${GREEN}✅ Database initialized successfully!${NC}"
