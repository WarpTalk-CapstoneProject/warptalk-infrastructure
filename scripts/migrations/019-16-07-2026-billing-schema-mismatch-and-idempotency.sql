-- Migration: 019-16-07-2026-billing-schema-mismatch-and-idempotency
-- Description:
--   WarpTalk.BillingService's EF Core model (BillingDbContext.cs) maps every entity to
--   schema "billing" (billing.subscriptions, billing.plans, billing.credit_transactions,
--   billing.transactions, billing.idempotency_records). That schema has NEVER existed in
--   this database — init-db.sql only ever creates schema "subscription" (see
--   subscription.plans/subscriptions/credit_transactions/usage_records/payments/refunds/
--   invoices, lines ~873-1010). Confirmed empirically: `\dn` on the live DB lists no
--   "billing" schema at all.
--
--   Effect in production: every billing.* query BillingService issues has been failing
--   (schema does not exist), silently swallowed by try/catch in BillingService.cs and
--   TranscriptRedisConsumerService.cs's gRPC ConsumeCreditsAsync call — so the entire
--   billing REST/gRPC API (CreateSubscription, TopUpCredits, ConsumeCredits,
--   GetWorkspaceCredits, CancelSubscription) has never worked. This was masked because
--   failures are logged as errors, not surfaced as visible outages, and nothing in the
--   app's happy-path flows blocks on billing succeeding.
--
--   Per project decision, the ERD (warptalk-v4-final.dbml) and the "subscription" schema
--   it defines are the source of truth — NOT the stale "billing" naming BillingDbContext.cs
--   was scaffolded against. This migration does not touch table structure (subscription.*
--   already has everything BillingService needs, per init-db.sql + migration 017); it only
--   adds the one piece BillingService.cs's own idempotency mechanism needs that the
--   "subscription" schema does not yet have: a home for IIdempotencyService's
--   IdempotencyRecord entity (HTTP-level request dedup on TopUp/CreateSubscription,
--   distinct from billing_worker's own per-event idempotency_key column on
--   subscription.credit_transactions, which already exists via migration 017).
--
--   The C# side (BillingDbContext.cs, Domain entities, BillingService.cs) is fixed
--   separately in this same session to map to subscription.* instead of billing.*.

BEGIN;

CREATE TABLE IF NOT EXISTS subscription.idempotency_records (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  idempotency_key VARCHAR(255) NOT NULL,
  operation VARCHAR(100) NOT NULL,
  workspace_id UUID,
  request_hash VARCHAR(128) NOT NULL,
  response_json TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  expires_at TIMESTAMPTZ NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_idempotency_records_key_operation
  ON subscription.idempotency_records (idempotency_key, operation);

CREATE INDEX IF NOT EXISTS idx_idempotency_records_workspace
  ON subscription.idempotency_records (workspace_id);

COMMIT;
