\set ON_ERROR_STOP on
BEGIN;
-- Bridge until billing's hourly EntitlementReconcileWorker resolves these four itself: copy the
-- snapshot billing resolved for the main demo workspace (same `enterprise` plan, same
-- MaxActiveRooms 20 override). The next sweep overwrites these rows with its own answer.
INSERT INTO workspace.workspace_entitlement_snapshots
    (workspace_id, entitlements, plan_slug, has_active_subscription, resolved_at, last_event_id, updated_at)
SELECT w.id, t.entitlements, t.plan_slug, t.has_active_subscription, t.resolved_at, gen_random_uuid(), NOW()
FROM workspace.workspaces AS w
CROSS JOIN (SELECT entitlements, plan_slug, has_active_subscription, resolved_at
            FROM workspace.workspace_entitlement_snapshots
            WHERE workspace_id = '019f0d00-0de0-7000-9000-0000000000aa'
              AND has_active_subscription AND plan_slug = 'enterprise') AS t
WHERE w.id::text LIKE '019f2b00-0de0-7000-9300-%'
ON CONFLICT (workspace_id) DO NOTHING;
DO $$
DECLARE v int;
BEGIN
    SELECT count(*) INTO v FROM workspace.workspace_entitlement_snapshots
    WHERE workspace_id::text LIKE '019f2b00-0de0-7000-9300-%' AND has_active_subscription
      AND entitlements->'voice_clone'->>'value' = 'true' AND entitlements->'max_participants'->>'value' = '500';
    IF v <> 4 THEN RAISE EXCEPTION 'Expected 4 enterprise snapshots, found %', v; END IF;
END $$;
COMMIT;
