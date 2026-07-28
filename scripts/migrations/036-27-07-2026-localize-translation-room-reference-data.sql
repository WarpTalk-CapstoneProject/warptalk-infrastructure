-- Remove the two cross-schema views that prevented Translation Room from being
-- extracted into its own logical database.
BEGIN;

DROP VIEW IF EXISTS translation_room.user_settings;

DROP VIEW IF EXISTS translation_room.supported_languages;

CREATE TABLE translation_room.supported_languages (
    code VARCHAR(15) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    native_name VARCHAR(100),
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- One-time materialization of the current product language catalog. Translation
-- Room becomes the authoritative owner for room language validation after this
-- migration; future changes are made against this local table.
INSERT INTO translation_room.supported_languages (
    code,
    name,
    native_name,
    is_active
)
SELECT
    code,
    name,
    native_name,
    is_active
FROM platform.supported_languages
WHERE deleted_at IS NULL
ON CONFLICT (code) DO UPDATE
SET
    name = EXCLUDED.name,
    native_name = EXCLUDED.native_name,
    is_active = EXCLUDED.is_active;

COMMENT ON TABLE translation_room.supported_languages IS
    'Translation Room-owned catalog used for room language validation; no cross-schema view.';

COMMIT;
