-- Migration: 020-17-07-2026-refresh-token-family-reuse-detection
-- Description:
--   auth.refresh_tokens had no concept of a "rotation family" — TokenService.RefreshTokenAsync
--   revokes the presented token and issues a brand new, unrelated one, but if an attacker ever
--   gets hold of an already-rotated-out (RevokedAt IS NOT NULL) refresh token and replays it,
--   the current code just returns "invalid token" and stops there. It never revokes the
--   legitimate session that token chain led to, so a stolen-then-rotated token gives an
--   attacker no bigger a footprint than one failed request — but it also means we have no
--   signal or containment action for the classic "refresh token reuse" attack pattern
--   (OWASP: reuse of a rotated-out token should revoke the entire token family).
--
-- Fix: add a family_id column. Every refresh_tokens row belongs to a family; rotating a token
-- (login -> refresh -> refresh -> ...) keeps the same family_id, so the whole chain can be
-- revoked in one statement the moment reuse of a stale token is detected.

BEGIN;

ALTER TABLE auth.refresh_tokens
  ADD COLUMN IF NOT EXISTS family_id UUID;

-- Backfill: existing rows have no recorded lineage, so treat each as the head of its own
-- singleton family (safe default — worst case a legitimate reuse-detection event revokes one
-- token instead of a whole chain, for tokens issued before this migration).
UPDATE auth.refresh_tokens
SET family_id = gen_random_uuid()
WHERE family_id IS NULL;

ALTER TABLE auth.refresh_tokens
  ALTER COLUMN family_id SET NOT NULL,
  ALTER COLUMN family_id SET DEFAULT gen_random_uuid();

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes WHERE schemaname = 'auth' AND indexname = 'idx_refresh_tokens_family_id'
    ) THEN
        CREATE INDEX idx_refresh_tokens_family_id ON auth.refresh_tokens (family_id);
    END IF;
END $$;

COMMIT;
