-- +goose Up

-- Household timezone: resolves "today", "tomorrow", "on Friday" in assistant requests.
ALTER TABLE households ADD COLUMN timezone text NOT NULL DEFAULT 'Europe/Warsaw';

-- The family assistant (Hermes, run by the runner container; see docs/assistant.md).
-- One per household; it talks to people over exactly one chat channel at a time.
CREATE TABLE assistants (
    household_id   uuid PRIMARY KEY REFERENCES households (id) ON DELETE CASCADE,
    -- actor id written to changes.actor_id for the assistant's writes
    id             uuid        NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    enabled        boolean     NOT NULL DEFAULT false,
    channel        text        NOT NULL DEFAULT 'telegram' CHECK (channel IN ('telegram')),
    -- OpenAI-compatible chat completions endpoint
    llm_base_url   text        NOT NULL DEFAULT '',
    llm_model      text        NOT NULL DEFAULT '',
    llm_api_key    text        NOT NULL DEFAULT '', -- sealed (OIKO_SECRET_KEY)
    -- MCP token of the assistant: hash for lookups, sealed copy for the runner config
    token_hash     bytea       NOT NULL UNIQUE,
    token_sealed   text        NOT NULL,
    -- bumped on every settings change; the runner restarts Hermes when it moves
    revision       bigint      NOT NULL DEFAULT 1,
    -- reported by the runner
    runner_seen_at timestamptz,
    runner_state   text        NOT NULL DEFAULT '',
    runner_error   text        NOT NULL DEFAULT '',
    runner_revision bigint     NOT NULL DEFAULT 0,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now()
);

-- Channel settings, one table per channel kind.
CREATE TABLE assistant_telegram (
    household_id uuid PRIMARY KEY REFERENCES assistants (household_id) ON DELETE CASCADE,
    bot_token    text NOT NULL DEFAULT '' -- sealed
);

-- Who may talk to the assistant: a member's account on a channel (e.g. a Telegram user id).
CREATE TABLE assistant_users (
    household_id uuid NOT NULL,
    member_id    uuid NOT NULL,
    channel      text NOT NULL,
    external_id  text NOT NULL,
    PRIMARY KEY (household_id, member_id, channel),
    UNIQUE (household_id, channel, external_id),
    FOREIGN KEY (household_id, member_id) REFERENCES members (household_id, id) ON DELETE CASCADE,
    FOREIGN KEY (household_id) REFERENCES assistants (household_id) ON DELETE CASCADE
);

-- +goose Down
DROP TABLE assistant_users;
DROP TABLE assistant_telegram;
DROP TABLE assistants;
ALTER TABLE households DROP COLUMN timezone;
