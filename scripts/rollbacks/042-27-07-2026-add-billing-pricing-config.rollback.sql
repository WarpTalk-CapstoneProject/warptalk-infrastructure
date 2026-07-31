-- Rollback: 042-27-07-2026-add-billing-pricing-config
-- Use only before production cutover or after taking a database backup.

BEGIN;

DROP TABLE IF EXISTS subscription.billing_pricing_config;

COMMIT;
