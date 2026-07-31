-- Rollback: 044-28-07-2026-add-sales-inquiries

BEGIN;

DROP TABLE IF EXISTS subscription.sales_inquiries;

COMMIT;
