-- +goose Up
-- The chat-bot assistant (Hermes) was removed; AI clients connect over MCP + OAuth only.
-- households.timezone stays (MCP tools resolve dates in it).
DROP TABLE assistant_users;
DROP TABLE assistant_telegram;
DROP TABLE assistants;

-- +goose Down
-- Not restored: the assistant's code is gone (see git history for 00008_assistant.sql).
SELECT 1;
