#!/usr/bin/env bash
# ====================================================================
# WarpTalk — Stop Full Stack
# Usage: ./stop-all.sh [--clean]
#   --clean: also remove volumes (data will be lost!)
# ====================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

cd "$INFRA_DIR"

echo -e "${YELLOW}⏹  Stopping WarpTalk services...${NC}"

if [[ "${1:-}" == "--clean" ]]; then
    echo -e "${RED}   ⚠  --clean flag: volumes will be removed!${NC}"
    docker compose -f docker-compose.yml -f docker-compose.dev.yml down -v 2>/dev/null || \
    docker compose -f docker-compose.yml -f docker-compose.prod.yml down -v 2>/dev/null || true
else
    docker compose -f docker-compose.yml -f docker-compose.dev.yml down 2>/dev/null || \
    docker compose -f docker-compose.yml -f docker-compose.prod.yml down 2>/dev/null || true
fi

echo -e "${GREEN}✅ All services stopped.${NC}"
