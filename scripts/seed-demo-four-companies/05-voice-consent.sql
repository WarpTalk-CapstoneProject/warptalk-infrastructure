-- Demo seed, four companies — PART 5/5: voice-clone consent (warptalk_auth). GENERATED.
-- Flow 2 accounts only. Insert a GRANTED row only where the latest row is not already GRANTED.
\set ON_ERROR_STOP on
BEGIN;

CREATE TEMP TABLE demo_consent_users (user_id uuid PRIMARY KEY) ON COMMIT DROP;
INSERT INTO demo_consent_users VALUES
    ('019f2b00-0de0-7000-9300-000000000301'),
    ('019f2b00-0de0-7000-9300-000000000302'),
    ('019f2b00-0de0-7000-9300-000000000303'),
    ('019f2b00-0de0-7000-9300-000000000304'),
    ('019f2b00-0de0-7000-9300-000000000305'),
    ('019f2b00-0de0-7000-9300-000000000306'),
    ('019f2b00-0de0-7000-9300-000000000307'),
    ('019f2b00-0de0-7000-9300-000000000308'),
    ('019f2b00-0de0-7000-9300-000000000309'),
    ('019f2b00-0de0-7000-9300-000000000401'),
    ('019f2b00-0de0-7000-9300-000000000402'),
    ('019f2b00-0de0-7000-9300-000000000403'),
    ('019f2b00-0de0-7000-9300-000000000404'),
    ('019f2b00-0de0-7000-9300-000000000405'),
    ('019f2b00-0de0-7000-9300-000000000406'),
    ('019f2b00-0de0-7000-9300-000000000407'),
    ('019f2b00-0de0-7000-9300-000000000408'),
    ('019f2b00-0de0-7000-9300-000000000409');

INSERT INTO voice.voice_consents (
    id, user_id, voice_profile_id, consent_type, consent_status, consent_text_version,
    granted_at, revoked_at, ip_address, user_agent, created_at
)
SELECT uuidv7(), u.user_id, NULL, 'VOICE_CLONE', 'GRANTED', '2026-09-29.v2',
       NOW(), NULL, NULL, 'seed: demo prep, recorded at the workspace owner''s request', NOW()
FROM demo_consent_users AS u
WHERE COALESCE((
    SELECT c.consent_status FROM voice.voice_consents AS c
    WHERE c.user_id = u.user_id AND c.consent_type = 'VOICE_CLONE'
    ORDER BY c.created_at DESC LIMIT 1
), '') <> 'GRANTED';

DO $$
DECLARE v int;
BEGIN
    SELECT count(*) INTO v FROM demo_consent_users AS u
    WHERE (SELECT c.consent_status FROM voice.voice_consents AS c
           WHERE c.user_id = u.user_id AND c.consent_type = 'VOICE_CLONE'
           ORDER BY c.created_at DESC LIMIT 1) = 'GRANTED';
    IF v <> 18 THEN RAISE EXCEPTION 'Expected 18 granted, found %', v; END IF;
END $$;

COMMIT;
