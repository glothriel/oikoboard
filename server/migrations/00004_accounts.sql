-- +goose Up

-- Konto (osoba, która się loguje) jest oddzielone od członka rodziny
-- (members). Jedno konto może kiedyś należeć do kilku rodzin, a członek
-- rodziny nie musi mieć konta (np. małe dziecko).
CREATE TABLE users (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email      text        NOT NULL,
    name       text        NOT NULL DEFAULT '',
    picture    text,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Tożsamości u dostawców logowania. Dopasowanie idzie po (provider,
-- subject) — subject u Google to stały identyfikator konta, e-mail może
-- się zmienić.
CREATE TABLE identities (
    provider   text        NOT NULL,
    subject    text        NOT NULL,
    user_id    uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (provider, subject)
);
CREATE INDEX identities_user_idx ON identities (user_id);

ALTER TABLE members
    DROP COLUMN sso_provider,
    DROP COLUMN sso_subject,
    ADD COLUMN user_id uuid REFERENCES users (id) ON DELETE SET NULL,
    -- członek „czeka” na konto z tym e-mailem (przypisany przy pierwszym
    -- logowaniu ze zweryfikowanym adresem)
    ADD COLUMN invite_email text,
    ADD UNIQUE (household_id, user_id);
CREATE INDEX members_user_idx ON members (user_id);
CREATE INDEX members_invite_email_idx ON members (lower(invite_email)) WHERE user_id IS NULL;

-- Sesja należy do konta; member_id to wybrana rodzina (gdy konto jest
-- w kilku). Stare sesje „kim jesteś” są unieważniane.
DROP TABLE sessions;
CREATE TABLE sessions (
    token_hash   bytea PRIMARY KEY,
    user_id      uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    member_id    uuid        REFERENCES members (id) ON DELETE SET NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX sessions_user_idx ON sessions (user_id);

-- Trwające logowania OAuth: od /auth/google/start do /auth/exchange.
CREATE TABLE auth_flows (
    state_hash    bytea PRIMARY KEY,
    pkce_verifier text        NOT NULL, -- PKCE wobec Google
    nonce         text        NOT NULL,
    return_to     text        NOT NULL,
    app_challenge text        NOT NULL, -- PKCE aplikacji wobec nas
    code_hash     bytea UNIQUE,         -- jednorazowy kod dla aplikacji
    user_id       uuid REFERENCES users (id) ON DELETE CASCADE,
    created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE invites (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid        NOT NULL REFERENCES households (id) ON DELETE CASCADE,
    token_hash   bytea       NOT NULL UNIQUE,
    -- zaproszenie dla istniejącego członka bez konta; NULL = nowa osoba
    member_id    uuid,
    created_by   uuid,
    expires_at   timestamptz NOT NULL,
    used_at      timestamptz,
    used_by      uuid REFERENCES users (id) ON DELETE SET NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (household_id, member_id) REFERENCES members (household_id, id) ON DELETE CASCADE,
    FOREIGN KEY (household_id, created_by) REFERENCES members (household_id, id) ON DELETE SET NULL (created_by)
);
CREATE INDEX invites_household_idx ON invites (household_id);

-- +goose Down
DROP TABLE invites;
DROP TABLE auth_flows;
DROP TABLE sessions;
CREATE TABLE sessions (
    token_hash   bytea PRIMARY KEY,
    member_id    uuid        NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    created_at   timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE members
    DROP COLUMN user_id,
    DROP COLUMN invite_email,
    ADD COLUMN sso_provider text,
    ADD COLUMN sso_subject text,
    ADD UNIQUE (sso_provider, sso_subject);
DROP TABLE identities;
DROP TABLE users;
