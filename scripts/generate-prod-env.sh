#!/bin/bash

# ====================================================================
# Enterprise Secure .env Generator
# This script generates cryptographically secure random passwords 
# and creates a .env file for production deployment.
# ====================================================================

ENV_FILE="../.env"

if [ -f "$ENV_FILE" ]; then
    echo "⚠️  $ENV_FILE already exists! Backing it up to .env.backup"
    cp "$ENV_FILE" "${ENV_FILE}.backup"
fi

# Function to generate a secure random 32-character string
generate_secret() {
    # Uses openssl to generate secure random bytes, then converts to base64, cleans it, and takes 32 chars
    openssl rand -base64 32 | tr -d '\n+/=' | head -c 32
}

echo "Generating secure passwords..."

cat <<EOF > "$ENV_FILE"
# ====================================================================
# WarpTalk Infrastructure — Environment Variables (PRODUCTION)
# Generated on: $(date)
# ====================================================================

# ── PostgreSQL ───────────────────────────────────────────────────────
POSTGRES_DB=warptalk
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$(generate_secret)

# ── Per-Service DB Users ─────────────────────────────────────────────
AUTH_DB_PASSWORD=$(generate_secret)
MEETING_DB_PASSWORD=$(generate_secret)
TRANSCRIPT_DB_PASSWORD=$(generate_secret)
SUBSCRIPTION_DB_PASSWORD=$(generate_secret)
NOTIFICATION_DB_PASSWORD=$(generate_secret)
TRANSLATION_ROOM_DB_PASSWORD=$(generate_secret)

# ── Redis ────────────────────────────────────────────────────────────
REDIS_PASSWORD=$(generate_secret)

# ── JWT ──────────────────────────────────────────────────────────────
# Recommended length is 64 chars for JWT secret
JWT_SECRET=$(openssl rand -base64 64 | tr -d '\n+/=' | head -c 64)
JWT_ISSUER=WarpTalk.AuthService
JWT_AUDIENCE=WarpTalk

# ── COTURN (TURN/STUN) ──────────────────────────────────────────────
TURN_SECRET=$(generate_secret)
TURN_REALM=warptalk.vn

# ── CORS ─────────────────────────────────────────────────────────────
# Update this with your actual production frontend URL
ALLOWED_ORIGINS=https://warptalk.vn,https://admin.warptalk.vn

# ── Observability ────────────────────────────────────────────────────
SEQ_API_KEY=$(generate_secret)
SEQ_ADMIN_PASSWORD=$(generate_secret)
GRAFANA_ADMIN_PASSWORD=$(generate_secret)

# ── Backup (S3/MinIO) ───────────────────────────────────────────────
BACKUP_S3_BUCKET=warptalk-backups
BACKUP_S3_ENDPOINT=http://minio:9000
BACKUP_S3_ACCESS_KEY=$(generate_secret)
BACKUP_S3_SECRET_KEY=$(generate_secret)
EOF

echo "✅ Successfully generated production secrets into $ENV_FILE!"
echo "⚠️  IMPORTANT: Copy the REDIS_PASSWORD from $ENV_FILE and place it into the warptalk-ai/.env file!"
