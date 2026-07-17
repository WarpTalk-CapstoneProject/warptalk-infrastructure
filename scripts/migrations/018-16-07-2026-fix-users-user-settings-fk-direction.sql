-- Migration: 018-16-07-2026-fix-users-user-settings-fk-direction
-- Description:
--   auth.users.id has held a FOREIGN KEY pointing AT auth.user_settings(user_id) since the
--   very first bootstrap script (init-db.sql:2210, also present in the stale
--   008-18-05-2026-full-schema.sql snapshot). That is backwards: it requires a matching
--   user_settings row to exist BEFORE a users row can be inserted, which is impossible for
--   a brand new user — auth.users is the parent, auth.user_settings is the child.
--
--   Effect in production: AuthService.RegisterAsync (POST /api/v1/auth/register) inserts
--   only into auth.users, not auth.user_settings, in a single SaveChangesAsync — so this
--   FK fails immediately (DEFERRABLE INITIALLY IMMEDIATE) and registration is impossible
--   for any user through the real API. The only reason seed-e2e-data.sql worked is that it
--   explicitly runs `SET CONSTRAINTS ALL DEFERRED` and inserts both auth.users and
--   auth.user_settings for the same ids inside one transaction before commit — masking the
--   bug rather than avoiding it.
--
-- Fix: drop the backwards constraint, add the correct one in the normal parent->child
-- direction, and backfill user_settings for any existing user that is missing one (so the
-- new correctly-directed constraint doesn't immediately fail on current data).

BEGIN;

ALTER TABLE auth.users DROP CONSTRAINT IF EXISTS users_id_fkey;

INSERT INTO auth.user_settings (user_id)
SELECT u.id
FROM auth.users u
LEFT JOIN auth.user_settings s ON s.user_id = u.id
WHERE s.user_id IS NULL
ON CONFLICT (user_id) DO NOTHING;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'user_settings_user_id_fkey'
    ) THEN
        ALTER TABLE auth.user_settings
          ADD CONSTRAINT user_settings_user_id_fkey
          FOREIGN KEY (user_id) REFERENCES auth.users (id)
          DEFERRABLE INITIALLY IMMEDIATE;
    END IF;
END $$;

COMMIT;

-- NOTE: this does not by itself make AuthService.RegisterAsync create a user_settings row
-- for newly registered users — it only fixes the FK direction so registration is no longer
-- structurally impossible. Whether RegisterAsync should also create a default
-- auth.user_settings row in the same transaction is an application-layer decision, tracked
-- separately (auth.user_settings has sensible column defaults, so a bare
-- INSERT INTO auth.user_settings (user_id) VALUES (:newUserId) would be enough).
