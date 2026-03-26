-- ====================================================================
-- WarpTalk — Database Initialization
-- Creates schemas and per-service DB users
-- Auto-runs on first PostgreSQL start via docker-entrypoint-initdb.d
-- ====================================================================

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ── Create Schemas ──────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS meeting;
CREATE SCHEMA IF NOT EXISTS transcript;
CREATE SCHEMA IF NOT EXISTS subscription;
CREATE SCHEMA IF NOT EXISTS notification;

-- ── Per-Service Users (least privilege) ─────────────────────────────
DO $$
BEGIN
    -- Auth service user
    -- Password injected at runtime via init-db.sh (from .env)
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'auth_svc') THEN
        CREATE USER auth_svc WITH PASSWORD :'AUTH_DB_PASSWORD';
    END IF;
    GRANT USAGE ON SCHEMA auth TO auth_svc;
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA auth TO auth_svc;
    ALTER DEFAULT PRIVILEGES IN SCHEMA auth GRANT ALL ON TABLES TO auth_svc;
    ALTER DEFAULT PRIVILEGES IN SCHEMA auth GRANT ALL ON SEQUENCES TO auth_svc;

    -- Meeting service user
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'meeting_svc') THEN
        CREATE USER meeting_svc WITH PASSWORD :'MEETING_DB_PASSWORD';
    END IF;
    GRANT USAGE ON SCHEMA meeting TO meeting_svc;
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA meeting TO meeting_svc;
    ALTER DEFAULT PRIVILEGES IN SCHEMA meeting GRANT ALL ON TABLES TO meeting_svc;
    ALTER DEFAULT PRIVILEGES IN SCHEMA meeting GRANT ALL ON SEQUENCES TO meeting_svc;

    -- Transcript service user
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'transcript_svc') THEN
        CREATE USER transcript_svc WITH PASSWORD :'TRANSCRIPT_DB_PASSWORD';
    END IF;
    GRANT USAGE ON SCHEMA transcript TO transcript_svc;
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA transcript TO transcript_svc;
    ALTER DEFAULT PRIVILEGES IN SCHEMA transcript GRANT ALL ON TABLES TO transcript_svc;
    ALTER DEFAULT PRIVILEGES IN SCHEMA transcript GRANT ALL ON SEQUENCES TO transcript_svc;

    -- Subscription service user
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'sub_svc') THEN
        CREATE USER sub_svc WITH PASSWORD :'SUBSCRIPTION_DB_PASSWORD';
    END IF;
    GRANT USAGE ON SCHEMA subscription TO sub_svc;
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA subscription TO sub_svc;
    ALTER DEFAULT PRIVILEGES IN SCHEMA subscription GRANT ALL ON TABLES TO sub_svc;
    ALTER DEFAULT PRIVILEGES IN SCHEMA subscription GRANT ALL ON SEQUENCES TO sub_svc;

    -- Notification service user
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'notif_svc') THEN
        CREATE USER notif_svc WITH PASSWORD :'NOTIFICATION_DB_PASSWORD';
    END IF;
    GRANT USAGE ON SCHEMA notification TO notif_svc;
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA notification TO notif_svc;
    ALTER DEFAULT PRIVILEGES IN SCHEMA notification GRANT ALL ON TABLES TO notif_svc;
    ALTER DEFAULT PRIVILEGES IN SCHEMA notification GRANT ALL ON SEQUENCES TO notif_svc;
END
$$;

-- ── Grant the main postgres user access to all schemas ──────────────
GRANT ALL ON SCHEMA auth, meeting, transcript, subscription, notification TO postgres;

RAISE NOTICE '✅ WarpTalk database initialized: 5 schemas, 5 service users';
