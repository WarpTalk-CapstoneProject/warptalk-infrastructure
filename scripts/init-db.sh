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
set -eu

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

# Enforce secrets are provided (no fallbacks in production!)
if [ -z "${AUTH_DB_PASSWORD:-}" ] || [ -z "${POSTGRES_PASSWORD:-}" ] || [ -z "${WORKSPACE_DB_PASSWORD:-}" ]; then
    echo -e "\033[0;31m❌ ERROR: Database passwords are not set! Please generate a .env file using scripts/generate-prod-env.sh\033[0m"
    exit 1
fi

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
    -v "WORKSPACE_DB_PASSWORD=$WORKSPACE_DB_PASSWORD"
)

if [[ "${1:-}" == "--docker" ]]; then
    echo "   Running via Docker container: warptalk-postgres"
    docker exec -i warptalk-postgres psql -U "$PG_USER" -d "$PG_DB" \
        "${PSQL_VARS[@]}" < "$SQL_FILE"
else
    echo "   Running against ${PG_HOST}:${PG_PORT}"
    PGPASSWORD="${POSTGRES_PASSWORD}" psql \
        -h "$PG_HOST" \
        -p "$PG_PORT" \
        -U "$PG_USER" \
        -d "$PG_DB" \
        "${PSQL_VARS[@]}" \
        -f "$SQL_FILE"
fi

echo -e "${GREEN}✅ Database initialized successfully!${NC}"
