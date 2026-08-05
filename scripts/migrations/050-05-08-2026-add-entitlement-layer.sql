-- Migration: 050-05-08-2026-add-entitlement-layer
-- Ticket: WT-263
-- Description:
--   Adds the storage the entitlement resolution layer needs. WarpTalk modelled "what you bought"
--   (plans, subscriptions) but never "what you may do", so every service either re-derived
--   entitlements or gave up — which is why every plan quota column was dead code.
--
--   Three additions, one per layer that had nowhere to live:
--     1. subscription.plans.max_active_rooms          — the plan layer for the room cap
--     2. subscription.subscriptions.entitlement_overrides — the contract layer
--     3. subscription.workspace_entitlement_overrides — the workspace self-service layer
--     4. workspace.workspace_entitlement_snapshots    — the replicated read model enforcement uses
--
--   NOT RUN as part of this change. Apply through the normal migration path before deploying the
--   services, because the EF entities map these columns and will SELECT them.

BEGIN;

-- ─────────────────────────────────────────────────────────────
-- 1. Plan layer: max_active_rooms
-- ─────────────────────────────────────────────────────────────
-- A real column, not a key in the plans.features JSON blob. Every other hard quota the plan sells
-- (max_participants, max_languages, credits_per_cycle) is a typed column; `features` is an
-- unvalidated marketing bag. A limit that is actually enforced belongs where plan CRUD validation
-- and the query planner can both see it — allow_acl is the cautionary example of what a
-- column-less entitlement costs (it had to be faked from ai_assistant_enabled, and WT-263 removed
-- it from the proto rather than keep pretending).
--
-- Default 5 matches WorkspaceConstants.DefaultWorkspaceMaxActiveRooms, which is the number every
-- existing workspace already carries in its settings JSON. That equality is what lets the backfill
-- distinguish a chosen value from a defaulted one.
ALTER TABLE subscription.plans
    ADD COLUMN IF NOT EXISTS max_active_rooms integer NOT NULL DEFAULT 5;

COMMENT ON COLUMN subscription.plans.max_active_rooms IS
    'WT-263. Plan-level ceiling on concurrently active rooms. Resolved as the max_active_rooms entitlement; a workspace may tighten below it but never above.';

-- Keep the seeded Enterprise plan meaningfully above the platform floor rather than silently
-- inheriting it. 50 is the validated ceiling WorkspaceSettingsValidator already enforces (1..50),
-- so this grants Enterprise the full self-service range and nothing beyond it.
UPDATE subscription.plans
SET max_active_rooms = 50
WHERE slug = 'enterprise'
  AND deleted_at IS NULL;

-- ─────────────────────────────────────────────────────────────
-- 2. Contract layer: negotiated per-subscription entitlement terms
-- ─────────────────────────────────────────────────────────────
-- jsonb rather than a column per key: the entitlement key set grows with each new capability, and a
-- column per key would force a migration every time one is added. The typed *_override columns
-- beside it stay as they are — they carry commercial terms (credits, overage cap, invoice days),
-- none of which is a capability, which is why none of them could serve this purpose.
ALTER TABLE subscription.subscriptions
    ADD COLUMN IF NOT EXISTS entitlement_overrides jsonb;

COMMENT ON COLUMN subscription.subscriptions.entitlement_overrides IS
    'WT-263. Contract-negotiated entitlement overrides, keyed by entitlement key, e.g. {"max_languages": 5}. Outranks the plan in BOTH directions - a contract may grant more than the catalog row.';

-- ─────────────────────────────────────────────────────────────
-- 3. Workspace self-service layer
-- ─────────────────────────────────────────────────────────────
-- Lives in the BILLING schema even though a workspace owner sets it, because the resolver is the
-- only code permitted to compute an entitlement and it cannot enforce "tighten but never loosen"
-- against a value it cannot see. One row per (workspace, key) rather than a JSON bag so clearing one
-- setting cannot race a concurrent change to another.
CREATE TABLE IF NOT EXISTS subscription.workspace_entitlement_overrides (
    workspace_id    uuid        NOT NULL,
    entitlement_key varchar(60) NOT NULL,
    value           varchar(40) NOT NULL,
    set_by          uuid,
    updated_at      timestamptz NOT NULL DEFAULT NOW(),
    CONSTRAINT workspace_entitlement_overrides_pkey PRIMARY KEY (workspace_id, entitlement_key)
);

COMMENT ON TABLE subscription.workspace_entitlement_overrides IS
    'WT-263. A workspace''s own tightening of an entitlement. Values are stored as text so one table serves both numeric limits and boolean capabilities; BillingService parses each against the key''s declared shape. No cross-service FK to the workspace table, per the FK policy in migration 043.';

GRANT SELECT, INSERT, UPDATE, DELETE
    ON subscription.workspace_entitlement_overrides
    TO warptalk_billing_runtime;

-- ─────────────────────────────────────────────────────────────
-- 4. Replicated read model in WorkspaceService's own schema
-- ─────────────────────────────────────────────────────────────
-- This table is why meeting creation no longer depends on BillingService being reachable. Written
-- only by the billing.entitlements_changed consumer, read only by enforcement.
CREATE TABLE IF NOT EXISTS workspace.workspace_entitlement_snapshots (
    workspace_id            uuid        PRIMARY KEY,
    entitlements            jsonb       NOT NULL DEFAULT '{}'::jsonb,
    plan_slug               varchar(80),
    has_active_subscription boolean     NOT NULL DEFAULT false,
    resolved_at             timestamptz NOT NULL,
    last_event_id           uuid        NOT NULL,
    updated_at              timestamptz NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE workspace.workspace_entitlement_snapshots IS
    'WT-263. Local replica of BillingService''s resolved entitlement map. A CACHE OF A DECISION, never an input to one - nothing here may be recomputed locally. resolved_at is the ordering guard: an event that resolved earlier than the stored row is ignored.';

COMMENT ON COLUMN workspace.workspace_entitlement_snapshots.entitlements IS
    'Resolved map as {key: {value, source}}. source is the provenance: platform_default | plan:<slug> | contract_override | workspace_override.';

GRANT SELECT, INSERT, UPDATE, DELETE
    ON workspace.workspace_entitlement_snapshots
    TO warptalk_workspace_runtime;

COMMIT;
