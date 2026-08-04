-- ====================================================================
-- WarpTalk — Demo accounts for the capstone meeting demo (PART 1 of 2: auth)
--
-- Target database: warptalk_auth   (owns schemas: public, auth, voice)
-- Run PART 2 (seed-prod-demo-accounts-workspace.sql) against warptalk_workspace
-- afterwards, using the role ids this script prints at the end.
--
-- Password: Password123 — the same one every other WarpTalk seed uses, kept
-- deliberately so the demo logins match the rest of the team's fixtures. To use
-- a different one, pass -v pw_hash="$(python3 hash-demo-password.py)".
--
-- Idempotent: safe to re-run. Existing rows are left untouched.
-- ====================================================================

\set ON_ERROR_STOP on

-- Default: PBKDF2-SHA512 hash of 'Password123', identical to the one in
-- seed-demo.sql. Verified to round-trip through PasswordHasher.Verify.
\if :{?pw_hash}
\else
\set pw_hash 'v2$SHA512$100000$16$jTFWzSKOXyuo/xZ+StGHwQ==$77jDm7DDcuTF57fhqikvLFBJhjrwoGuni8WcPdOhpAc='
\endif

BEGIN;

-- Validating in the table rather than a DO block on purpose: psql does not
-- interpolate variables inside dollar-quoted strings, so :'pw_hash' would
-- arrive at a DO body verbatim.
CREATE TEMP TABLE demo_password (
    hash text PRIMARY KEY CHECK (hash LIKE 'v2$SHA512$100000$16$%')
) ON COMMIT DROP;
INSERT INTO demo_password VALUES (:'pw_hash');

-- ── Roster ──────────────────────────────────────────────────────────
-- Edit the emails to the addresses the team will actually type at the
-- login screen. The ids are fixed on purpose: PART 2 references them.
-- speak/listen codes must exist in translation_room.supported_languages —
-- verified against prod 2026-07-31, which stores full locale codes
-- (vi-VN, en-US, ja-JP, ko-KR, zh-CN, fr-FR, es-ES), not bare 'vi'/'en'.
CREATE TEMP TABLE demo_roster (
    user_id           uuid PRIMARY KEY,
    email             text NOT NULL,
    full_name         text NOT NULL,
    preferred_language text NOT NULL,
    speak_language    text NOT NULL,
    listen_language   text NOT NULL,
    workspace_role    text NOT NULL   -- Owner | Admin | Member
) ON COMMIT DROP;

INSERT INTO demo_roster VALUES
    ('019f0d00-0de0-7000-9000-000000000001', 'thaitu.demo@warptalk.vn',   'Huỳnh Thái Tú',      'vi-VN', 'vi-VN', 'en-US', 'Owner'),
    ('019f0d00-0de0-7000-9000-000000000002', 'manhtuan.demo@warptalk.vn', 'Trần Mạnh Tuấn',     'vi-VN', 'en-US', 'vi-VN', 'Member'),
    ('019f0d00-0de0-7000-9000-000000000003', 'ngocky.demo@warptalk.vn',   'Huỳnh Ngọc Kỳ',      'vi-VN', 'vi-VN', 'en-US', 'Member'),
    ('019f0d00-0de0-7000-9000-000000000004', 'hanhnhi.demo@warptalk.vn',  'Ngô Xuân Hạnh Nhi',  'vi-VN', 'en-US', 'vi-VN', 'Member'),
    ('019f0d00-0de0-7000-9000-000000000005', 'mentor.demo@warptalk.vn',   'Thân Thị Ngọc Vân',  'vi-VN', 'vi-VN', 'en-US', 'Admin');

-- ── 1. Platform + workspace roles ───────────────────────────────────
-- Present in every deployed environment already; the insert is a no-op
-- guard so this script also works against a freshly restored database.
INSERT INTO auth.roles (id, name, description, is_system, is_active, created_at)
VALUES
    (gen_random_uuid(), 'user',   'Regular user',            true, true, NOW()),
    (gen_random_uuid(), 'Owner',  'Workspace Owner',         true, true, NOW()),
    (gen_random_uuid(), 'Admin',  'Workspace Administrator', true, true, NOW()),
    (gen_random_uuid(), 'Member', 'Workspace Member',        true, true, NOW())
ON CONFLICT (name) DO NOTHING;

-- ── 2. Users ────────────────────────────────────────────────────────
-- email_verified is set so the accounts skip the verification mail loop;
-- these are demo logins, not real mailboxes.
INSERT INTO auth.users (
    id, email, password_hash, full_name, preferred_language, timezone,
    is_active, email_verified, email_verified_at, created_at
)
SELECT
    r.user_id, r.email, p.hash, r.full_name, r.preferred_language, 'Asia/Ho_Chi_Minh',
    true, true, NOW(), NOW()
FROM demo_roster AS r
CROSS JOIN demo_password AS p
ON CONFLICT (email) DO NOTHING;

-- Guard: if one of these emails already belonged to a different account,
-- the insert above was skipped and PART 2 would attach the membership to a
-- user id that does not exist. Fail here instead of half-seeding.
DO $$
DECLARE
    v_conflict text;
BEGIN
    SELECT string_agg(format('%s -> existing id %s (roster expects %s)',
                             u.email, u.id, r.user_id), E'\n')
    INTO v_conflict
    FROM demo_roster AS r
    INNER JOIN auth.users AS u ON lower(u.email) = lower(r.email)
    WHERE u.id <> r.user_id;

    IF v_conflict IS NOT NULL THEN
        RAISE EXCEPTION E'Email already in use by another account:\n%\n'
            'Pick different demo emails, or reuse the existing ids in both scripts.',
            v_conflict;
    END IF;
END $$;

-- ── 3. Language defaults ────────────────────────────────────────────
INSERT INTO auth.user_settings (id, user_id, default_speak_language, default_listen_language, updated_at)
SELECT gen_random_uuid(), r.user_id, r.speak_language, r.listen_language, NOW()
FROM demo_roster AS r
ON CONFLICT (user_id) DO NOTHING;

-- ── 4. Platform role 'user' ─────────────────────────────────────────
-- Deliberately no 'admin' role: these are meeting-demo accounts, they have
-- no business reaching /api/v1/admin/*.
INSERT INTO auth.user_roles (id, user_id, role_id, assigned_at)
SELECT gen_random_uuid(), r.user_id, sys.id, NOW()
FROM demo_roster AS r
CROSS JOIN (SELECT id FROM auth.roles WHERE name = 'user') AS sys
WHERE NOT EXISTS (
    SELECT 1 FROM auth.user_roles AS ur
    WHERE ur.user_id = r.user_id AND ur.role_id = sys.id
);

COMMIT;

-- ── 5. Hand-off to PART 2 ───────────────────────────────────────────
\echo ''
\echo '--- Workspace role ids — pass these to PART 2 ---'
SELECT name, id FROM auth.roles WHERE name IN ('Owner', 'Admin', 'Member') ORDER BY name;

\echo '--- Seeded accounts ---'
SELECT u.id, u.email, u.full_name, s.default_speak_language, s.default_listen_language
FROM auth.users AS u
LEFT JOIN auth.user_settings AS s ON s.user_id = u.id
WHERE u.id::text LIKE '019f0d00-0de0-7000-9000-%'
ORDER BY u.id;
