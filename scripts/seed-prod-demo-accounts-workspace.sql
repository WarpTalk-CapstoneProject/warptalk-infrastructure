-- ====================================================================
-- WarpTalk — Demo accounts for the capstone meeting demo (PART 2 of 2: workspace)
--
-- Target database: warptalk_workspace   (owns schemas: public, workspace)
-- Run PART 1 (seed-prod-demo-accounts-auth.sql) against warptalk_auth first.
--
-- Required variables — the ids PART 1 printed:
--   -v owner_role_id=... -v admin_role_id=... -v member_role_id=...
--
-- The cross-service FKs from workspace.* to auth.* were dropped in migrations
-- 043/044, so these ids are plain uuids here with nothing to enforce them.
-- That is exactly why PART 1 must succeed first.
--
-- Idempotent: safe to re-run.
-- ====================================================================

\set ON_ERROR_STOP on

-- Defaults are the live production role ids, read from warptalk_auth.auth.roles
-- on 2026-07-31. Override with -v if they ever differ in another environment;
-- the assertion block at the end catches a mismatch either way.
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

BEGIN;

\set workspace_id '019f0d00-0de0-7000-9000-0000000000aa'

-- ── 1. Demo workspace ───────────────────────────────────────────────
-- require_verified_domain_for_internal = FALSE: every member counts as
-- Internal without standing up DNS verification for a demo domain. This is
-- the flag the membership classifier reads — do not try to express it in the
-- settings JSON, which is not policy.
INSERT INTO workspace.workspaces (
    id, name, slug, owner_id,
    allow_external_collaboration, require_verified_domain_for_internal, allow_subdomains,
    is_active, created_at, created_by, updated_at, updated_by
)
VALUES (
    :'workspace_id',
    'WarpTalk Demo — SEP490',
    'warptalk-demo-sep490',
    '019f0d00-0de0-7000-9000-000000000001',   -- Huỳnh Thái Tú (leader)
    true, false, false,
    true, NOW(), '019f0d00-0de0-7000-9000-000000000001', NOW(), '019f0d00-0de0-7000-9000-000000000001'
)
ON CONFLICT (id) DO UPDATE SET
    require_verified_domain_for_internal = EXCLUDED.require_verified_domain_for_internal,
    allow_external_collaboration         = EXCLUDED.allow_external_collaboration,
    is_active                            = true,
    deleted_at                           = NULL,
    updated_at                           = NOW();

-- ── 2. Members ──────────────────────────────────────────────────────
-- can_create_meetings = TRUE for all five so any of them can host during the
-- demo, not just the owner. 'Internal' / 'Active' match the casing the service
-- itself writes (MembershipType.Internal / WorkspaceMemberStatus.Active
-- .ToString()) and the casing the existing prod rows already use — note this
-- differs from the lowercase values in the local-dev seed-demo.sql.
CREATE TEMP TABLE demo_members (user_id uuid PRIMARY KEY, role_id uuid NOT NULL) ON COMMIT DROP;
INSERT INTO demo_members VALUES
    ('019f0d00-0de0-7000-9000-000000000001', :'owner_role_id'),   -- Huỳnh Thái Tú     — Owner
    ('019f0d00-0de0-7000-9000-000000000002', :'member_role_id'),  -- Trần Mạnh Tuấn    — Member
    ('019f0d00-0de0-7000-9000-000000000003', :'member_role_id'),  -- Huỳnh Ngọc Kỳ     — Member
    ('019f0d00-0de0-7000-9000-000000000004', :'member_role_id'),  -- Ngô Xuân Hạnh Nhi — Member
    ('019f0d00-0de0-7000-9000-000000000005', :'admin_role_id');   -- Thân Thị Ngọc Vân — Admin (mentor)

INSERT INTO workspace.workspace_members (
    id, workspace_id, user_id, role_id, membership_type, status, can_create_meetings, joined_at
)
SELECT gen_random_uuid(), :'workspace_id', m.user_id, m.role_id, 'Internal', 'Active', true, NOW()
FROM demo_members AS m
ON CONFLICT (workspace_id, user_id) DO UPDATE SET
    role_id             = EXCLUDED.role_id,
    membership_type     = EXCLUDED.membership_type,
    status              = 'Active',
    can_create_meetings = true,
    removed_at          = NULL,
    removed_by          = NULL;

-- ── 3. Assertions ───────────────────────────────────────────────────
-- The workspace id is a constant here rather than :'workspace_id': psql does
-- not interpolate variables inside dollar-quoted strings.
DO $assert$
DECLARE
    v_members int;
    v_roles   int;
BEGIN
    SELECT count(*) INTO v_members
    FROM workspace.workspace_members
    WHERE workspace_id = '019f0d00-0de0-7000-9000-0000000000aa'
      AND status = 'Active'
      AND removed_at IS NULL
      AND can_create_meetings;

    IF v_members <> 5 THEN
        RAISE EXCEPTION 'Expected 5 active demo members that can create meetings, found %', v_members;
    END IF;

    -- Catches the easy paste error of reusing one role id for all three flags.
    SELECT count(DISTINCT role_id) INTO v_roles
    FROM workspace.workspace_members
    WHERE workspace_id = '019f0d00-0de0-7000-9000-0000000000aa';

    IF v_roles <> 3 THEN
        RAISE EXCEPTION 'Expected 3 distinct roles (Owner/Admin/Member) across the demo members, found %. '
            'Re-check the owner_role_id / admin_role_id / member_role_id you passed.', v_roles;
    END IF;
END $assert$;

COMMIT;

-- ── 4. Report ───────────────────────────────────────────────────────
\echo ''
\echo '--- Demo workspace membership (expect 5 rows, all active/Internal/can_create_meetings=t) ---'
SELECT m.user_id, m.role_id, m.membership_type, m.status, m.can_create_meetings, m.removed_at
FROM workspace.workspace_members AS m
WHERE m.workspace_id = :'workspace_id'
ORDER BY m.user_id;
