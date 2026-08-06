-- Backfill: WT-263 — seed workspace self-service entitlement overrides from existing settings JSON
--
-- NOT RUN as part of the WT-263 change. Run AFTER migration 050, once, and read the assumption
-- below before you do, because it is a judgement call and not a mechanical translation.
--
-- ─────────────────────────────────────────────────────────────
-- THE AMBIGUITY, stated plainly
-- ─────────────────────────────────────────────────────────────
-- Every existing workspace stores MaxActiveRooms in workspace.workspaces.settings. The old data
-- does NOT record whether that number was CHOSEN by an owner or DEFAULTED by the code:
-- WorkspaceConstants.DefaultWorkspaceMaxActiveRooms is 5, and a workspace that never opened the
-- settings screen has 5 stored exactly as if someone had typed it.
--
-- In the new model those two cases resolve differently. A chosen value is a workspace_override; an
-- unset one resolves from the plan. So the backfill has to guess, and this script guesses one way:
--
--   ASSUMPTION: a stored value EQUAL TO 5 is treated as DEFAULTED (no override row is written).
--               Any other value is treated as DELIBERATELY CHOSEN (an override row is written).
--
-- Why that direction:
--   * It is the safe direction for the workspace. A defaulted 5 becomes "resolve from the plan", so
--     a workspace on a plan that allows more gets more — nobody is capped tighter than before by an
--     accident of the old default. The opposite guess would silently freeze every workspace in the
--     product at 5 forever, including plans sold on a higher limit.
--   * It cannot loosen anybody past what they bought, because the resolver clamps the plan value in
--     any case and the platform default is also 5.
--   * A value that is not 5 could only have been typed by a person: nothing in the code writes any
--     other number.
--
-- KNOWN FALSE NEGATIVE, accepted: an owner who deliberately typed 5 is indistinguishable from a
-- default and loses their override. The consequence is bounded — they resolve to their plan's limit
-- instead of 5, which is >= 5 for every plan — and they can re-save the setting to restore it. The
-- alternative error (treating every default as a deliberate cap) has no such ceiling.
--
-- Requires the resolver's tighten-not-loosen rule to hold afterwards: rows written here that EXCEED
-- the workspace's plan ceiling are simply not applied at resolution time (they are dropped, not
-- clamped), so an over-permissive row cannot grant anything. The SELECT at the bottom lists them.

BEGIN;

INSERT INTO subscription.workspace_entitlement_overrides (workspace_id, entitlement_key, value, set_by, updated_at)
SELECT
    w.id,
    'max_active_rooms',
    (w.settings ->> 'MaxActiveRooms'),
    NULL,                       -- no historical record of who set it; deliberately not invented
    NOW()
FROM workspace.workspaces AS w
WHERE w.deleted_at IS NULL
  AND w.settings ? 'MaxActiveRooms'
  AND (w.settings ->> 'MaxActiveRooms') ~ '^[0-9]+$'
  AND (w.settings ->> 'MaxActiveRooms')::int BETWEEN 1 AND 50   -- the validated range (1..50)
  AND (w.settings ->> 'MaxActiveRooms')::int <> 5               -- 5 == the old default: treat as unset
ON CONFLICT (workspace_id, entitlement_key) DO NOTHING;         -- never overwrite a real setting

COMMIT;

-- ─────────────────────────────────────────────────────────────
-- Post-run report. Neither query changes anything.
-- ─────────────────────────────────────────────────────────────

-- What was written.
SELECT entitlement_key, COUNT(*) AS rows_written
FROM subscription.workspace_entitlement_overrides
GROUP BY entitlement_key;

-- Rows that will be DROPPED by the resolver because they exceed the plan ceiling. These are not
-- errors and need no correction — they are workspaces whose stored setting was looser than the plan
-- they are on, which the old code never checked. They will resolve to their plan's limit.
SELECT o.workspace_id, o.value AS requested, p.max_active_rooms AS plan_ceiling, p.slug AS plan
FROM subscription.workspace_entitlement_overrides AS o
JOIN subscription.subscriptions AS s
  ON s.workspace_id = o.workspace_id AND s.deleted_at IS NULL
JOIN subscription.plans AS p
  ON p.id = s.plan_id AND p.deleted_at IS NULL
WHERE o.entitlement_key = 'max_active_rooms'
  AND o.value ~ '^[0-9]+$'
  AND o.value::int > p.max_active_rooms;

-- After this backfill, publish a fresh snapshot for every workspace so consumers leave cold start
-- without waiting for an unrelated billing event. BillingService has no bulk re-resolve endpoint
-- today (see RISKS in the WT-263 report); until it does, the snapshots arrive on the next
-- subscription, plan or override change for each workspace, and cold start is not-enforced in the
-- meantime.
