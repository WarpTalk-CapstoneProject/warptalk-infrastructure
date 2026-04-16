-- Migration: 000-init-migrations
-- Description: Create the schema_migrations tracking table

CREATE TABLE IF NOT EXISTS public.schema_migrations (
    version varchar(255) PRIMARY KEY,
    applied_at timestamp default current_timestamp
);
