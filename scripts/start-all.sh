#!/usr/bin/env bash
# ====================================================================
# WarpTalk — Start Full Stack
# Usage:
#   ./start-all.sh          # Start in dev mode
#   ./start-all.sh --prod   # Start in production mode
#   ./start-all.sh --build  # Force rebuild images
# ====================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║           🚀 WarpTalk Full Stack                    ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

cd "$INFRA_DIR"

# Check .env exists
if [[ ! -f .env ]]; then
    echo "⚠  No .env found. Copying from .env.example..."
    cp .env.example .env
    echo "   Please edit .env with real values, then re-run."
    exit 1
fi

BUILD_FLAG=""
COMPOSE_FILES="-f docker-compose.yml -f docker-compose.dev.yml"

for arg in "$@"; do
    case "$arg" in
        --prod)
            COMPOSE_FILES="-f docker-compose.yml -f docker-compose.prod.yml"
            echo "   Mode: Production"
            ;;
        --build)
            BUILD_FLAG="--build"
            echo "   Forcing image rebuild"
            ;;
    esac
done

echo -e "${CYAN}Starting services...${NC}"
docker compose $COMPOSE_FILES up $BUILD_FLAG -d

# Wait for DB to be healthy
echo -e "${CYAN}Waiting for PostgreSQL to be ready...${NC}"
for i in $(seq 1 30); do
    if docker exec warptalk-postgres pg_isready -U postgres -q 2>/dev/null; then
        echo -e " ${GREEN}✅ DB Ready${NC}"
        break
    fi
    echo -n "."
    sleep 1
done

# Run migrations
echo -e "${CYAN}🐘 Running PostgreSQL migrations...${NC}"
MIGRATIONS_DIR="$SCRIPT_DIR/migrations"
if [[ -d "$MIGRATIONS_DIR" ]]; then
    for file in "$MIGRATIONS_DIR"/*.sql; do
        if [[ -f "$file" ]]; then
            echo -e "   Executing $(basename "$file")..."
            docker exec -i warptalk-postgres psql -U postgres -d warptalk < "$file" || echo -e "   ${YELLOW}⚠ Failed or already executed${NC}"
        fi
    done
    echo -e "   ${GREEN}✅ Migrations completed${NC}"
fi

echo ""
echo -e "${GREEN}✅ All services started!${NC}"
echo ""
echo "   Gateway:     http://localhost:5200"
echo "   Seq Logs:    http://localhost:5341"
echo "   Grafana:     http://localhost:3001"
echo "   Prometheus:  http://localhost:9090"
echo ""
echo "   View logs:   docker compose $COMPOSE_FILES logs -f"
echo "   Stop:        ./scripts/stop-all.sh"
