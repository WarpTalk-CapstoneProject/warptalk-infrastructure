-- ====================================================================
-- WarpTalk capstone demo seed — PART 1/5: auth
-- Target database: warptalk_auth
--
-- 4 accounts. Password for all four: Password123
-- (same PBKDF2-SHA512 hash every other WarpTalk seed uses; verified to
--  round-trip through PasswordHasher.Verify).
--
-- Language codes here are FULL LOCALES (vi-VN / en-US) because that is what
-- auth.user_settings and translation_room.supported_languages store. The
-- meeting-side tables store BARE codes (vi / en) — see PART 4 and PART 5.
-- Verified against prod 2026-08-19; do not "normalise" the two.
--
-- Idempotent: safe to re-run.
-- ====================================================================

\set ON_ERROR_STOP on

\if :{?pw_hash}
\else
\set pw_hash 'v2$SHA512$100000$16$jTFWzSKOXyuo/xZ+StGHwQ==$77jDm7DDcuTF57fhqikvLFBJhjrwoGuni8WcPdOhpAc='
\endif

BEGIN;

-- Validated in a table, not a DO block: psql does not interpolate variables
-- inside dollar-quoted strings.
CREATE TEMP TABLE demo_password (
    hash text PRIMARY KEY CHECK (hash LIKE 'v2$SHA512$100000$16$%')
) ON COMMIT DROP;
INSERT INTO demo_password VALUES (:'pw_hash');

-- ── Roster ──────────────────────────────────────────────────────────
-- speak/listen must exist in translation_room.supported_languages, which on
-- prod holds vi-VN, en-US, ja-JP, ko-KR, zh-CN, fr-FR, es-ES.
--
-- The speak/listen split is deliberate: with everyone on one language the
-- translation path has nothing to do on stage.
CREATE TEMP TABLE demo_roster (
    user_id            uuid PRIMARY KEY,
    email              text NOT NULL,
    full_name          text NOT NULL,
    preferred_language text NOT NULL,
    speak_language     text NOT NULL,
    listen_language    text NOT NULL,
    workspace_role     text NOT NULL
) ON COMMIT DROP;

INSERT INTO demo_roster VALUES
    ('019f1a00-0de0-7000-9200-000000000001', 'owner@warptalk.vn',   'Huỳnh Thái Tú',      'vi-VN', 'vi-VN', 'en-US', 'Owner'),
    ('019f1a00-0de0-7000-9200-000000000002', 'admin@warptalk.vn',   'Thân Thị Ngọc Vân',  'vi-VN', 'vi-VN', 'en-US', 'Admin'),
    ('019f1a00-0de0-7000-9200-000000000003', 'member1@warptalk.vn', 'Trần Mạnh Tuấn',     'vi-VN', 'en-US', 'vi-VN', 'Member'),
    ('019f1a00-0de0-7000-9200-000000000004', 'member2@warptalk.vn', 'Ngô Xuân Hạnh Nhi',  'vi-VN', 'en-US', 'vi-VN', 'Member');

-- ── 1. Roles ────────────────────────────────────────────────────────
-- Already present in every deployed environment; this is a no-op guard so the
-- script also works against a freshly restored database.
INSERT INTO auth.roles (id, name, description, is_system, is_active, created_at)
VALUES
    (gen_random_uuid(), 'user',   'Regular user',            true, true, NOW()),
    (gen_random_uuid(), 'Owner',  'Workspace Owner',         true, true, NOW()),
    (gen_random_uuid(), 'Admin',  'Workspace Administrator', true, true, NOW()),
    (gen_random_uuid(), 'Member', 'Workspace Member',        true, true, NOW())
ON CONFLICT (name) DO NOTHING;

-- ── 2. Users ────────────────────────────────────────────────────────
-- email_verified pre-set: these are demo logins, not real mailboxes, and the
-- verification mail loop would block the whole demo at step one.
INSERT INTO auth.users (
    id, email, password_hash, full_name, preferred_language, timezone,
    is_active, is_locked, email_verified, email_verified_at, created_at, updated_at
)
SELECT
    r.user_id, r.email, p.hash, r.full_name, r.preferred_language, 'Asia/Ho_Chi_Minh',
    true, false, true, NOW(), NOW(), NOW()
FROM demo_roster AS r
CROSS JOIN demo_password AS p
ON CONFLICT (email) DO NOTHING;

-- Guard: if one of these emails already belonged to a different account the
-- insert above was silently skipped, and PART 2 would attach a membership to a
-- user id that does not exist. Fail here rather than half-seed.
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
            'Pick different demo emails, or reuse the existing ids across all five parts.',
            v_conflict;
    END IF;
END $$;

-- ── 3. Language + meeting defaults ──────────────────────────────────
-- auto_generate_summary stays on so a live Flow 2 meeting produces the same
-- artifact shape PART 5 seeds for the pre-baked meeting.
INSERT INTO auth.user_settings (
    id, user_id, default_speak_language, default_listen_language,
    voice_clone_enabled, auto_generate_summary, default_max_participants, updated_at
)
SELECT gen_random_uuid(), r.user_id, r.speak_language, r.listen_language,
       true, true, 10, NOW()
FROM demo_roster AS r
ON CONFLICT (user_id) DO UPDATE SET
    default_speak_language  = EXCLUDED.default_speak_language,
    default_listen_language = EXCLUDED.default_listen_language,
    voice_clone_enabled     = true,
    auto_generate_summary   = true,
    updated_at              = NOW();

-- ── 4. Platform role 'user' ─────────────────────────────────────────
-- Deliberately NOT 'admin': these are meeting-demo logins and have no business
-- reaching /api/v1/admin/*. Flow 5 (admin portal) uses its own account.
INSERT INTO auth.user_roles (id, user_id, role_id, assigned_at)
SELECT gen_random_uuid(), r.user_id, sys.id, NOW()
FROM demo_roster AS r
CROSS JOIN (SELECT id FROM auth.roles WHERE name = 'user') AS sys
WHERE NOT EXISTS (
    SELECT 1 FROM auth.user_roles AS ur
    WHERE ur.user_id = r.user_id AND ur.role_id = sys.id
);

-- ── 5. Assertion ────────────────────────────────────────────────────
DO $assert$
DECLARE
    v_users int;
BEGIN
    SELECT count(*) INTO v_users
    FROM auth.users
    WHERE id::text LIKE '019f1a00-0de0-7000-9200-%'
      AND is_active AND email_verified AND password_hash IS NOT NULL;

    IF v_users <> 4 THEN
        RAISE EXCEPTION 'Expected 4 active, verified demo accounts, found %', v_users;
    END IF;
END $assert$;

COMMIT;

\echo ''
\echo '--- Workspace role ids (PART 2 defaults to these; override with -v if they differ) ---'
SELECT name, id FROM auth.roles WHERE name IN ('Owner', 'Admin', 'Member') ORDER BY name;

\echo '--- Seeded accounts (password: Password123) ---'
SELECT u.email, u.full_name, s.default_speak_language AS speak, s.default_listen_language AS listen
FROM auth.users AS u
LEFT JOIN auth.user_settings AS s ON s.user_id = u.id
WHERE u.id::text LIKE '019f1a00-0de0-7000-9200-%'
ORDER BY u.id;
