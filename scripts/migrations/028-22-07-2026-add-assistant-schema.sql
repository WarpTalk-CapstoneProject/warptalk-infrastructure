CREATE SCHEMA IF NOT EXISTS assistant;

CREATE TABLE assistant.assistant_conversations (
    id UUID PRIMARY KEY,
    workspace_id UUID NOT NULL,
    user_id UUID NOT NULL,
    title VARCHAR(255) NOT NULL DEFAULT 'New chat',
    context_scope TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    last_message_at TIMESTAMP WITH TIME ZONE,
    is_archived BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE assistant.assistant_messages (
    id UUID PRIMARY KEY,
    conversation_id UUID NOT NULL REFERENCES assistant.assistant_conversations(id) ON DELETE CASCADE,
    workspace_id UUID NOT NULL,
    user_id UUID,
    role VARCHAR(20) NOT NULL,
    content TEXT NOT NULL DEFAULT '',
    tool_calls_json TEXT,
    tool_results_json TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'completed',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE assistant.assistant_tool_calls (
    id UUID PRIMARY KEY,
    message_id UUID NOT NULL REFERENCES assistant.assistant_messages(id) ON DELETE CASCADE,
    tool_name VARCHAR(100) NOT NULL,
    arguments_json TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    result_json TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_assistant_messages_conversation ON assistant.assistant_messages(conversation_id, created_at);
CREATE INDEX idx_assistant_conversations_workspace_user ON assistant.assistant_conversations(workspace_id, user_id, last_message_at DESC);
