#!/usr/bin/env bash
# ====================================================================
# WarpTalk — Start Full Stack
# Usage:
#   ./start-all.sh          # Start in dev mode
#   RELEASE_MANIFEST=... PRODUCTION_ENV_FILE=... ./start-all.sh --prod
#   ./start-all.sh --build  # Force rebuild images
# ====================================================================
set -eu

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

BUILD_FLAG=""
COMPOSE_FILES="-f docker-compose.yml -f docker-compose.dev.yml -f docker-compose.mac.yml"
PRODUCTION_MODE=false

for arg in "$@"; do
    case "$arg" in
        --prod)
            PRODUCTION_MODE=true
            echo "   Mode: Production"
            ;;
        --build)
            BUILD_FLAG="--build"
            echo "   Forcing image rebuild"
            ;;
    esac
done

if [[ "$PRODUCTION_MODE" == true ]]; then
    if [[ -n "$BUILD_FLAG" ]]; then
        echo "Production images must be built by scripts/build-release.sh; --build is not allowed." >&2
        exit 1
    fi
    exec "$INFRA_DIR/scripts/deploy-release.sh"
fi

# Local Compose alone uses the development environment file.
if [[ ! -f .env ]]; then
    echo "⚠  No .env found. Copying from .env.example..."
    cp .env.example .env
    echo "   Please edit .env with real values, then re-run."
    exit 1
fi

echo -e "${CYAN}Starting services...${NC}"
# The migrator service (base docker-compose.yml) applies scripts/migrations/*.sql
# in chronological order and exits; every service that needs the DB declares
# `depends_on: migrator: condition: service_completed_successfully`, so compose
# itself blocks them until migrations finish — no separate step needed here.
docker compose $COMPOSE_FILES up $BUILD_FLAG -d

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
