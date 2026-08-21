-- ====================================================================
-- WarpTalk capstone demo seed — PART 2/5: workspace
-- Target database: warptalk_workspace
-- Run PART 1 (warptalk_auth) first.
--
-- Cross-service FKs from workspace.* to auth.* were dropped in migrations
-- 043/044, so the user ids below are plain uuids with nothing enforcing them.
-- That is exactly why PART 1 must succeed first.
--
-- Idempotent: safe to re-run.
-- ====================================================================

\set ON_ERROR_STOP on

-- Live production role ids, read from warptalk_auth.auth.roles on 2026-08-19.
-- The assertion at the end catches a mismatch either way.
\if :{?owner_role_id}
\else
\set owner_role_id '6ed77306-70aa-4ece-a00e-30dd3763035a'
\endif
\if :{?admin_role_id}
\else
\set admin_role_id 'a737aee0-9423-4dd7-8809-8e898f4b5317'
\endif
\if :{?member_role_id}
\else
\set member_role_id 'fdb38f47-1191-4730-a3d9-eade73a75527'
\endif

\set workspace_id '019f1a00-0de0-7000-9200-0000000000aa'
\set owner_id     '019f1a00-0de0-7000-9200-000000000001'

BEGIN;

-- ── 1. Workspace ────────────────────────────────────────────────────
-- require_verified_domain_for_internal = FALSE makes all four members Internal
-- without standing up DNS verification for a demo domain. This COLUMN is the
-- policy the membership classifier reads; the same-named key in the settings
-- JSON is not policy and is written only so the Settings page renders it.
--
-- The settings JSON mirrors the shape the live workspace service writes
-- (PascalCase keys, BARE language codes) — read off prod 2026-08-19. Do not
-- switch these to locale codes: the room/transcript side uses bare codes too.
INSERT INTO workspace.workspaces (
    id, name, slug, owner_id, logo_url,
    allow_external_collaboration, require_verified_domain_for_internal, allow_subdomains,
    settings, is_active, created_at, created_by, updated_at, updated_by
)
VALUES (
    :'workspace_id',
    'WarpTalk Capstone Demo',
    'warptalk-capstone-demo',
    :'owner_id',
    NULL,
    true, false, false,
    jsonb_build_object(
        'DefaultLanguage',                  'vi',
        'Timezone',                         'Asia/Ho_Chi_Minh',
        'MaxActiveRooms',                   20,
        'ArtifactRetentionDays',            30,
        'InvitationExpiryDays',             7,
        'VoiceCloningEnabled',              true,
        'IsProfanityFilterEnabled',         true,
        'AllowedTargetLanguages',           jsonb_build_array('vi', 'en', 'ja'),
        'VerifiedDomains',                  jsonb_build_array(),
        'AllowExternalCollaboration',       true,
        'RequireVerifiedDomainForInternal', false,
        'ExternalGracePeriodHours',         NULL,
        'AiUsagePolicy', jsonb_build_object(
            'AllowExternalLlm',  true,
            'UseGlobalGlossary', true,
            'RedactPii',         jsonb_build_object('Enabled', true),
            'Dlp',               jsonb_build_object(
                'Enabled',           true,
                'KeywordsBlacklist', jsonb_build_array('Fuck', 'Shit', 'Damn')
            ),
            'TranslationProfile', jsonb_build_object(
                'TranslationTone',       'professional',
                'LanguageSpecificRules', jsonb_build_object(
                    'VietnameseHonorificStyle', 'formal_hierarchical',
                    'JapaneseHonorificStyle',   'keigo_teineigo'
                )
            )
        )
    ),
    true, NOW(), :'owner_id', NOW(), :'owner_id'
)
ON CONFLICT (id) DO UPDATE SET
    name                                 = EXCLUDED.name,
    slug                                 = EXCLUDED.slug,
    owner_id                             = EXCLUDED.owner_id,
    allow_external_collaboration         = EXCLUDED.allow_external_collaboration,
    require_verified_domain_for_internal = EXCLUDED.require_verified_domain_for_internal,
    settings                             = EXCLUDED.settings,
    is_active                            = true,
    deleted_at                           = NULL,
    deleted_by                           = NULL,
    updated_at                           = NOW();

-- ── 2. Members ──────────────────────────────────────────────────────
-- status is LOWERCASE 'active' and membership_type is CAPITALISED 'Internal'.
-- That asymmetry is what the live prod rows actually hold (read 2026-08-19) —
-- the older seed-prod-demo-accounts-workspace.sql writes 'Active' and is stale
-- on this point. Match the data, not the older script.
--
-- can_create_meetings = TRUE for all four so any of them can host. The
-- meeting-creation gate fails closed (WT-249), so a false here is a silent
-- backend 403 on stage, not just a hidden button.
CREATE TEMP TABLE demo_members (user_id uuid PRIMARY KEY, role_id uuid NOT NULL) ON COMMIT DROP;
INSERT INTO demo_members VALUES
    ('019f1a00-0de0-7000-9200-000000000001', :'owner_role_id'),   -- Huỳnh Thái Tú      — Owner
    ('019f1a00-0de0-7000-9200-000000000002', :'admin_role_id'),   -- Thân Thị Ngọc Vân  — Admin
    ('019f1a00-0de0-7000-9200-000000000003', :'member_role_id'),  -- Trần Mạnh Tuấn     — Member
    ('019f1a00-0de0-7000-9200-000000000004', :'member_role_id');  -- Ngô Xuân Hạnh Nhi  — Member

INSERT INTO workspace.workspace_members (
    id, workspace_id, user_id, role_id, membership_type, status, can_create_meetings, joined_at
)
SELECT gen_random_uuid(), :'workspace_id', m.user_id, m.role_id, 'Internal', 'active', true, NOW()
FROM demo_members AS m
ON CONFLICT (workspace_id, user_id) DO UPDATE SET
    role_id             = EXCLUDED.role_id,
    membership_type     = 'Internal',
    status              = 'active',
    can_create_meetings = true,
    removed_at          = NULL,
    removed_by          = NULL;

-- ── 3. Assertions ───────────────────────────────────────────────────
-- Literals, not :'workspace_id': psql does not interpolate inside
-- dollar-quoted strings.
DO $assert$
DECLARE
    v_members int;
    v_roles   int;
BEGIN
    SELECT count(*) INTO v_members
    FROM workspace.workspace_members
    WHERE workspace_id = '019f1a00-0de0-7000-9200-0000000000aa'
      AND status = 'active'
      AND removed_at IS NULL
      AND can_create_meetings;

    IF v_members <> 4 THEN
        RAISE EXCEPTION 'Expected 4 active demo members that can create meetings, found %', v_members;
    END IF;

    -- Catches the easy paste error of reusing one role id for all three.
    SELECT count(DISTINCT role_id) INTO v_roles
    FROM workspace.workspace_members
    WHERE workspace_id = '019f1a00-0de0-7000-9200-0000000000aa';

    IF v_roles <> 3 THEN
        RAISE EXCEPTION 'Expected 3 distinct roles (Owner/Admin/Member), found %. '
            'Re-check owner_role_id / admin_role_id / member_role_id.', v_roles;
    END IF;
END $assert$;

COMMIT;

\echo ''
\echo '--- Demo workspace membership (expect 4: 1 Owner, 1 Admin, 2 Member) ---'
SELECT m.user_id, m.role_id, m.membership_type, m.status, m.can_create_meetings
FROM workspace.workspace_members AS m
WHERE m.workspace_id = :'workspace_id'
ORDER BY m.user_id;

\echo '--- NOTE: no entitlement snapshot is written here on purpose. ---'
\echo '--- Run step 6 in README.md (save Workspace Settings via the API) to make ---'
\echo '--- billing publish billing.entitlements_changed and build the snapshot. ---'
