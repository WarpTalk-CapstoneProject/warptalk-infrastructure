#!/usr/bin/env bash
# ====================================================================
# WarpTalk — Seed Sample Data
# Inserts test/demo data into the database for development
# ====================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PG_HOST="${PG_HOST:-localhost}"
PG_PORT="${PG_PORT:-5432}"
PG_USER="${PG_USER:-postgres}"
PG_DB="${PG_DB:-warptalk}"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}🌱 Seeding WarpTalk database...${NC}"

run_sql() {
    if [[ "${1:-}" == "--docker" ]]; then
        docker exec -i warptalk-postgres psql -U "$PG_USER" -d "$PG_DB"
    else
        PGPASSWORD="${POSTGRES_PASSWORD:-postgres}" psql \
            -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB"
    fi
}

run_sql "${1:-}" <<'SQL'
-- ── Seed Roles ──────────────────────────────────────────────────────
INSERT INTO auth.roles (id, name, description, created_at)
VALUES
    (gen_random_uuid(), 'admin', 'System administrator', NOW()),
    (gen_random_uuid(), 'user', 'Regular user', NOW()),
    (gen_random_uuid(), 'moderator', 'Content moderator', NOW())
ON CONFLICT DO NOTHING;

-- ── Seed Subscription Plans ─────────────────────────────────────────
-- (add when subscription schema is ready)

RAISE NOTICE '✅ Seed data inserted';
SQL

echo -e "${GREEN}✅ Database seeded successfully!${NC}"
