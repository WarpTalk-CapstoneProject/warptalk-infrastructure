-- Migration: 048-30-07-2026-gate-google-meet-enterprise-integration
-- Description:
--   External meeting integration scope for the capstone demo is Google Meet only.
--   The Enterprise plan exposes that capability explicitly; integration tables
--   reject other provider rows until those platforms have real product support.

BEGIN;

UPDATE subscription.plans
SET
    features = jsonb_set(
        jsonb_set(
            COALESCE(features, '{}'::jsonb),
            '{external_integrations}',
            '{"google_meet": true}'::jsonb,
            true
        ),
        '{supported_external_platforms}',
        '["google_meet"]'::jsonb,
        true
    ),
    updated_at = now()
WHERE slug = 'enterprise';

DO $$
BEGIN
    IF to_regclass('integration.external_platform_accounts') IS NOT NULL
       AND NOT EXISTS (
           SELECT 1
           FROM pg_constraint
           WHERE conname = 'external_platform_accounts_google_meet_only_chk'
             AND conrelid = 'integration.external_platform_accounts'::regclass
       ) THEN
        ALTER TABLE integration.external_platform_accounts
            ADD CONSTRAINT external_platform_accounts_google_meet_only_chk
            CHECK (lower(provider) = 'google_meet')
            NOT VALID;
    END IF;

    IF to_regclass('integration.external_meeting_sessions') IS NOT NULL
       AND NOT EXISTS (
           SELECT 1
           FROM pg_constraint
           WHERE conname = 'external_meeting_sessions_google_meet_only_chk'
             AND conrelid = 'integration.external_meeting_sessions'::regclass
       ) THEN
        ALTER TABLE integration.external_meeting_sessions
            ADD CONSTRAINT external_meeting_sessions_google_meet_only_chk
            CHECK (lower(provider) = 'google_meet')
            NOT VALID;
    END IF;
END $$;

COMMIT;
