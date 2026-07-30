-- Migration: 023-20-07-2026-switch-payment-provider-to-stripe
-- Description:
--   Team switched payment provider from PayOS to Stripe. Updates the default value of
--   subscription.payments.provider from 'payos' to 'stripe' for new rows, and backfills
--   any existing 'payos' rows (dev/test data only — no production PayOS transactions were
--   ever processed, per the removed PayOSSimulationController/tech-debt note) to 'stripe'
--   so no stale provider name lingers in the table.

BEGIN;

ALTER TABLE subscription.payments
  ALTER COLUMN provider SET DEFAULT 'stripe';

UPDATE subscription.payments
SET provider = 'stripe'
WHERE provider = 'payos';

COMMIT;
