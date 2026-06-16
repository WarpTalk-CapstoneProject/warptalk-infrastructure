-- ====================================================================
-- WarpTalk — Seed Demo User and System/Workspace Roles
-- Seeds a clean workspace-less user for testing/demo flows
-- Email: demo@enterprise.vn
-- Password: Password123
-- ====================================================================

DO $$ 
DECLARE
    v_user_id uuid := '019ea677-6c84-7d7b-9f48-738b3cde41a9';
    v_system_user_role_id uuid;
BEGIN
    -- 1. Seed system and workspace roles in auth.roles if they don't exist
    INSERT INTO auth.roles (id, name, description, is_system, is_active, created_at)
    VALUES 
        (gen_random_uuid(), 'admin', 'System administrator', true, true, NOW()),
        (gen_random_uuid(), 'user', 'Regular user', true, true, NOW()),
        (gen_random_uuid(), 'moderator', 'Content moderator', true, true, NOW()),
        (gen_random_uuid(), 'Owner', 'Workspace Owner', true, true, NOW()),
        (gen_random_uuid(), 'Admin', 'Workspace Administrator', true, true, NOW()),
        (gen_random_uuid(), 'Member', 'Workspace Member', true, true, NOW())
    ON CONFLICT (name) DO NOTHING;

    -- Retrieve system 'user' role ID
    SELECT id INTO v_system_user_role_id FROM auth.roles WHERE name = 'user';

    -- 2. Seed User Settings first to satisfy the FK constraint in auth.users
    -- Demo User
    INSERT INTO auth.user_settings (id, user_id, default_speak_language, default_listen_language, updated_at)
    VALUES (gen_random_uuid(), v_user_id, 'vi-VN', 'en-US', NOW())
    ON CONFLICT (user_id) DO NOTHING;

    -- Alice Smith settings (Admin)
    INSERT INTO auth.user_settings (id, user_id, default_speak_language, default_listen_language, updated_at)
    VALUES (gen_random_uuid(), '019ea677-6c84-7d7b-9f48-738b3cde41ab', 'en-US', 'vi-VN', NOW())
    ON CONFLICT (user_id) DO NOTHING;

    -- Bob Johnson settings (Member)
    INSERT INTO auth.user_settings (id, user_id, default_speak_language, default_listen_language, updated_at)
    VALUES (gen_random_uuid(), '019ea677-6c84-7d7b-9f48-738b3cde41ac', 'vi-VN', 'en-US', NOW())
    ON CONFLICT (user_id) DO NOTHING;

    -- Charlie Brown settings (Member, FPT)
    INSERT INTO auth.user_settings (id, user_id, default_speak_language, default_listen_language, updated_at)
    VALUES (gen_random_uuid(), '019ea677-6c84-7d7b-9f48-738b3cde41ad', 'en-US', 'vi-VN', NOW())
    ON CONFLICT (user_id) DO NOTHING;

    -- Diana Prince settings (Member, FPT)
    INSERT INTO auth.user_settings (id, user_id, default_speak_language, default_listen_language, updated_at)
    VALUES (gen_random_uuid(), '019ea677-6c84-7d7b-9f48-738b3cde41ae', 'vi-VN', 'en-US', NOW())
    ON CONFLICT (user_id) DO NOTHING;


    -- 3. Seed Users in auth.users
    -- Demo User
    INSERT INTO auth.users (id, email, password_hash, full_name, preferred_language, timezone, is_active, email_verified, email_verified_at, created_at)
    VALUES (
        v_user_id, 
        'demo@enterprise.vn', 
        'v2$SHA512$100000$16$jTFWzSKOXyuo/xZ+StGHwQ==$77jDm7DDcuTF57fhqikvLFBJhjrwoGuni8WcPdOhpAc=', 
        'Demo User', 
        'vi-VN', 
        'Asia/Ho_Chi_Minh', 
        true, 
        true, 
        NOW(), 
        NOW()
    )
    ON CONFLICT (email) DO NOTHING;

    -- Alice Smith
    INSERT INTO auth.users (id, email, password_hash, full_name, preferred_language, timezone, is_active, email_verified, email_verified_at, created_at)
    VALUES (
        '019ea677-6c84-7d7b-9f48-738b3cde41ab', 
        'alice.smith@enterprise.vn', 
        'v2$SHA512$100000$16$jTFWzSKOXyuo/xZ+StGHwQ==$77jDm7DDcuTF57fhqikvLFBJhjrwoGuni8WcPdOhpAc=', 
        'Alice Smith', 
        'en-US', 
        'Asia/Ho_Chi_Minh', 
        true, 
        true, 
        NOW(), 
        NOW()
    )
    ON CONFLICT (email) DO NOTHING;

    -- Bob Johnson
    INSERT INTO auth.users (id, email, password_hash, full_name, preferred_language, timezone, is_active, email_verified, email_verified_at, created_at)
    VALUES (
        '019ea677-6c84-7d7b-9f48-738b3cde41ac', 
        'bob.johnson@enterprise.vn', 
        'v2$SHA512$100000$16$jTFWzSKOXyuo/xZ+StGHwQ==$77jDm7DDcuTF57fhqikvLFBJhjrwoGuni8WcPdOhpAc=', 
        'Bob Johnson', 
        'vi-VN', 
        'Asia/Ho_Chi_Minh', 
        true, 
        true, 
        NOW(), 
        NOW()
    )
    ON CONFLICT (email) DO NOTHING;

    -- Charlie Brown
    INSERT INTO auth.users (id, email, password_hash, full_name, preferred_language, timezone, is_active, email_verified, email_verified_at, created_at)
    VALUES (
        '019ea677-6c84-7d7b-9f48-738b3cde41ad', 
        'charlie.brown@fpt.edu.vn', 
        'v2$SHA512$100000$16$jTFWzSKOXyuo/xZ+StGHwQ==$77jDm7DDcuTF57fhqikvLFBJhjrwoGuni8WcPdOhpAc=', 
        'Charlie Brown', 
        'en-US', 
        'Asia/Ho_Chi_Minh', 
        true, 
        true, 
        NOW(), 
        NOW()
    )
    ON CONFLICT (email) DO NOTHING;

    -- Diana Prince
    INSERT INTO auth.users (id, email, password_hash, full_name, preferred_language, timezone, is_active, email_verified, email_verified_at, created_at)
    VALUES (
        '019ea677-6c84-7d7b-9f48-738b3cde41ae', 
        'diana.prince@fpt.edu.vn', 
        'v2$SHA512$100000$16$jTFWzSKOXyuo/xZ+StGHwQ==$77jDm7DDcuTF57fhqikvLFBJhjrwoGuni8WcPdOhpAc=', 
        'Diana Prince', 
        'vi-VN', 
        'Asia/Ho_Chi_Minh', 
        true, 
        true, 
        NOW(), 
        NOW()
    )
    ON CONFLICT (email) DO NOTHING;


    -- 4. Assign system role 'user' to all seeded users
    IF NOT EXISTS (SELECT 1 FROM auth.user_roles WHERE user_id = v_user_id AND role_id = v_system_user_role_id) THEN
        INSERT INTO auth.user_roles (id, user_id, role_id, assigned_at)
        VALUES (gen_random_uuid(), v_user_id, v_system_user_role_id, NOW());
    END IF;

    IF NOT EXISTS (SELECT 1 FROM auth.user_roles WHERE user_id = '019ea677-6c84-7d7b-9f48-738b3cde41ab' AND role_id = v_system_user_role_id) THEN
        INSERT INTO auth.user_roles (id, user_id, role_id, assigned_at)
        VALUES (gen_random_uuid(), '019ea677-6c84-7d7b-9f48-738b3cde41ab', v_system_user_role_id, NOW());
    END IF;

    IF NOT EXISTS (SELECT 1 FROM auth.user_roles WHERE user_id = '019ea677-6c84-7d7b-9f48-738b3cde41ac' AND role_id = v_system_user_role_id) THEN
        INSERT INTO auth.user_roles (id, user_id, role_id, assigned_at)
        VALUES (gen_random_uuid(), '019ea677-6c84-7d7b-9f48-738b3cde41ac', v_system_user_role_id, NOW());
    END IF;

    IF NOT EXISTS (SELECT 1 FROM auth.user_roles WHERE user_id = '019ea677-6c84-7d7b-9f48-738b3cde41ad' AND role_id = v_system_user_role_id) THEN
        INSERT INTO auth.user_roles (id, user_id, role_id, assigned_at)
        VALUES (gen_random_uuid(), '019ea677-6c84-7d7b-9f48-738b3cde41ad', v_system_user_role_id, NOW());
    END IF;

    IF NOT EXISTS (SELECT 1 FROM auth.user_roles WHERE user_id = '019ea677-6c84-7d7b-9f48-738b3cde41ae' AND role_id = v_system_user_role_id) THEN
        INSERT INTO auth.user_roles (id, user_id, role_id, assigned_at)
        VALUES (gen_random_uuid(), '019ea677-6c84-7d7b-9f48-738b3cde41ae', v_system_user_role_id, NOW());
    END IF;


    -- 5. Seed Workspace, Verified Domains, and Members
    DECLARE
        v_workspace_id uuid := '019ea677-6c84-7d7b-9f48-738b3cde41aa';
        v_owner_role_id uuid;
        v_admin_role_id uuid;
        v_member_role_id uuid;
    BEGIN
        SELECT id INTO v_owner_role_id FROM auth.roles WHERE name = 'Owner';
        SELECT id INTO v_admin_role_id FROM auth.roles WHERE name = 'Admin';
        SELECT id INTO v_member_role_id FROM auth.roles WHERE name = 'Member';

        -- Workspace
        INSERT INTO workspace.workspaces (id, name, slug, owner_id, is_active, created_at, created_by, updated_at, updated_by)
        VALUES (v_workspace_id, 'FPT-SEP490-SU26', 'fpt-sep490-su26', v_user_id, true, NOW(), v_user_id, NOW(), v_user_id)
        ON CONFLICT (slug) DO NOTHING;

        -- Verified domain 'enterprise.vn'
        IF NOT EXISTS (SELECT 1 FROM workspace.workspace_verified_domains WHERE domain = 'enterprise.vn' AND status = 'verified') THEN
            INSERT INTO workspace.workspace_verified_domains (id, workspace_id, domain, status, verification_method, verification_token, verified_at, verified_by, created_at, created_by, updated_at, updated_by)
            VALUES (gen_random_uuid(), v_workspace_id, 'enterprise.vn', 'verified', 'dns', 'token_enterprise_9982', NOW(), v_user_id, NOW(), v_user_id, NOW(), v_user_id);
        END IF;

        -- Verified domain 'fpt.edu.vn'
        IF NOT EXISTS (SELECT 1 FROM workspace.workspace_verified_domains WHERE domain = 'fpt.edu.vn' AND status = 'verified') THEN
            INSERT INTO workspace.workspace_verified_domains (id, workspace_id, domain, status, verification_method, verification_token, verified_at, verified_by, created_at, created_by, updated_at, updated_by)
            VALUES (gen_random_uuid(), v_workspace_id, 'fpt.edu.vn', 'verified', 'dns', 'token_fpt_4481', NOW(), v_user_id, NOW(), v_user_id, NOW(), v_user_id);
        END IF;

        -- Memberships
        -- Demo User (Owner)
        INSERT INTO workspace.workspace_members (id, workspace_id, user_id, role_id, membership_type, status, can_create_meetings, joined_at)
        VALUES (gen_random_uuid(), v_workspace_id, v_user_id, v_owner_role_id, 'internal', 'active', true, NOW())
        ON CONFLICT (workspace_id, user_id) DO NOTHING;


        -- 6. Seed Sample Documents
        -- IT_Terms.csv
        IF NOT EXISTS (SELECT 1 FROM workspace.workspace_documents WHERE name = 'IT Terms Glossary' AND workspace_id = v_workspace_id) THEN
            INSERT INTO workspace.workspace_documents (id, workspace_id, uploaded_by, owner_id, name, file_name, file_extension, mime_type, size_bytes, storage_provider, storage_key, source_type, document_type, status, ingestion_status, created_at, updated_at)
            VALUES (gen_random_uuid(), v_workspace_id, v_user_id, v_user_id, 'IT Terms Glossary', 'it_terms.csv', 'csv', 'text/csv', 2048, 'local', 'seed/it_terms.csv', 'Upload', 'reference', 'Active', 'Completed', NOW(), NOW());
        END IF;

        -- Finance_Glossary.pdf
        IF NOT EXISTS (SELECT 1 FROM workspace.workspace_documents WHERE name = 'Finance Glossary Reference' AND workspace_id = v_workspace_id) THEN
            INSERT INTO workspace.workspace_documents (id, workspace_id, uploaded_by, owner_id, name, file_name, file_extension, mime_type, size_bytes, storage_provider, storage_key, source_type, document_type, status, ingestion_status, created_at, updated_at)
            VALUES (gen_random_uuid(), v_workspace_id, v_user_id, v_user_id, 'Finance Glossary Reference', 'finance_glossary.pdf', 'pdf', 'application/pdf', 1048576, 'local', 'seed/finance_glossary.pdf', 'Upload', 'reference', 'Active', 'Completed', NOW(), NOW());
        END IF;

    END;

    RAISE NOTICE '✅ Seed demo data successfully inserted';
END $$;
