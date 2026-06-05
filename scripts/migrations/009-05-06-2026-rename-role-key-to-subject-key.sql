-- Migration: Rename role_key to subject_key and expand its length in workspace.workspace_document_access_policies
-- Created At: 2026-06-05

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_schema = 'workspace' 
          AND table_name = 'workspace_document_access_policies' 
          AND column_name = 'role_key'
    ) THEN
        -- Rename column
        ALTER TABLE workspace.workspace_document_access_policies 
        RENAME COLUMN role_key TO subject_key;
    END IF;
END $$;

-- Alter column size to VARCHAR(150)
ALTER TABLE workspace.workspace_document_access_policies 
ALTER COLUMN subject_key TYPE VARCHAR(150);

-- Add source_id UUID to workspace_documents
-- Mục đích: Lưu ID của đối tượng nguồn sinh ra tài liệu này (ví dụ: ID của phòng dịch Translation Room, ID của kênh chat, hoặc ID của cổng tích hợp),
-- kết hợp với cột 'source_type' để tạo thành một khóa ngoại đa hình (polymorphic relationship).
ALTER TABLE workspace.workspace_documents 
ADD COLUMN IF NOT EXISTS source_id UUID;

