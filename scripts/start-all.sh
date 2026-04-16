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
YELLOW='\033[0;33m'
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
    # Prepare migration tracking table and ensure it's executed first safely
    if [[ -f "$MIGRATIONS_DIR/000-init-migrations.sql" ]]; then
        docker exec -i warptalk-postgres psql -U postgres -d warptalk < "$MIGRATIONS_DIR/000-init-migrations.sql" >/dev/null 2>&1
    fi

    for file in "$MIGRATIONS_DIR"/*.sql; do
        if [[ -f "$file" ]]; then
            filename=$(basename "$file")
            
            # Skip the tracking table initialization script in the display loop
            if [[ "$filename" == "000-init-migrations.sql" ]]; then
                continue
            fi
            # Check if this migration has already been applied
            is_applied=$(docker exec -i warptalk-postgres psql -U postgres -d warptalk -tAc "SELECT 1 FROM public.schema_migrations WHERE version='$filename';" 2>/dev/null)
            
            if [[ "$is_applied" != "1" ]]; then
                echo -e "   Executing $filename..."
                docker exec -i warptalk-postgres psql -U postgres -d warptalk < "$file" && \
                docker exec -i warptalk-postgres psql -U postgres -d warptalk -c "INSERT INTO public.schema_migrations(version) VALUES ('$filename');" -q || \
                echo -e "   ${YELLOW}⚠ Failed to execute $filename${NC}"
            else
                echo -e "   Skipping $filename (already applied)"
            fi
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
