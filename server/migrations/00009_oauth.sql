-- +goose Up

-- OAuth 2.1 authorization server for MCP clients (ChatGPT, Claude…): see docs/assistant.md.

-- Clients registered dynamically (RFC 7591).
CREATE TABLE oauth_clients (
    id            text PRIMARY KEY,
    secret_hash   bytea,                 -- NULL = public client (PKCE only)
    name          text        NOT NULL DEFAULT '',
    redirect_uris text[]      NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now()
);

-- Authorization requests in progress: from /oauth/authorize through sign-in and consent.
CREATE TABLE oauth_requests (
    id             bytea PRIMARY KEY,    -- hash of the request token
    client_id      text        NOT NULL REFERENCES oauth_clients (id) ON DELETE CASCADE,
    redirect_uri   text        NOT NULL,
    code_challenge text        NOT NULL,
    state          text        NOT NULL DEFAULT '',
    scope          text        NOT NULL DEFAULT '',
    resource       text        NOT NULL DEFAULT '',
    login_verifier text        NOT NULL, -- our PKCE verifier for the sign-in flow
    user_id        uuid REFERENCES users (id) ON DELETE CASCADE, -- after sign-in
    consent_hash   bytea,                -- CSRF token of the consent form (also in a cookie)
    created_at     timestamptz NOT NULL DEFAULT now()
);

-- A member's permission for a client: authorization codes and tokens hang off it.
-- Deleting it (the app's "disconnect") revokes everything.
CREATE TABLE oauth_grants (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id    text        NOT NULL REFERENCES oauth_clients (id) ON DELETE CASCADE,
    household_id uuid        NOT NULL,
    member_id    uuid        NOT NULL,
    user_id      uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    scope        text        NOT NULL DEFAULT '',
    resource     text        NOT NULL DEFAULT '',
    created_at   timestamptz NOT NULL DEFAULT now(),
    last_used_at timestamptz,
    FOREIGN KEY (household_id, member_id) REFERENCES members (household_id, id) ON DELETE CASCADE
);
CREATE INDEX oauth_grants_member_idx ON oauth_grants (household_id, member_id);

CREATE TABLE oauth_codes (
    code_hash      bytea PRIMARY KEY,
    grant_id       uuid        NOT NULL REFERENCES oauth_grants (id) ON DELETE CASCADE,
    redirect_uri   text        NOT NULL,
    code_challenge text        NOT NULL,
    expires_at     timestamptz NOT NULL
);

-- kind: access (short-lived) | refresh (rotated on use)
CREATE TABLE oauth_tokens (
    token_hash bytea PRIMARY KEY,
    grant_id   uuid        NOT NULL REFERENCES oauth_grants (id) ON DELETE CASCADE,
    kind       text        NOT NULL CHECK (kind IN ('access', 'refresh')),
    expires_at timestamptz NOT NULL
);
CREATE INDEX oauth_tokens_grant_idx ON oauth_tokens (grant_id);

-- +goose Down
DROP TABLE oauth_tokens;
DROP TABLE oauth_codes;
DROP TABLE oauth_grants;
DROP TABLE oauth_requests;
DROP TABLE oauth_clients;
