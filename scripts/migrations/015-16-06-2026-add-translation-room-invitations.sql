-- Migration: 015-16-06-2026-add-translation-room-invitations
-- Description: Add translation_room_invitations table to track invited emails

CREATE TABLE IF NOT EXISTS translation_room.translation_room_invitations (
    id uuid NOT NULL DEFAULT (uuidv7()),
    translation_room_id uuid NOT NULL,
    email character varying(255) NOT NULL,
    status character varying(50) NOT NULL DEFAULT 'PENDING',
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT translation_room_invitations_pkey PRIMARY KEY (id),
    CONSTRAINT translation_room_invitations_translation_room_id_fkey FOREIGN KEY (translation_room_id) REFERENCES translation_room.translation_rooms(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS translation_room_invitations_room_email_idx ON translation_room.translation_room_invitations (translation_room_id, email);
