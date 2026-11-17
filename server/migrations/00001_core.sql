-- +goose Up

-- Wszystko jest per gospodarstwo (household). Każda tabela danych ma
-- household_id, a powiązania między tabelami idą złożonymi kluczami
-- (household_id, id) — baza sama pilnuje, żeby rekordy różnych rodzin
-- nigdy się nie wymieszały.

CREATE TABLE households (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name       text        NOT NULL,
    -- licznik zmian; zwiększany przez trigger pod blokadą wiersza,
    -- więc w obrębie gospodarstwa seq = kolejność commitów
    seq        bigint      NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE members (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid        NOT NULL REFERENCES households (id) ON DELETE CASCADE,
    name         text        NOT NULL,
    color        bigint      NOT NULL DEFAULT 4284246976, -- ARGB 0xFF5C6BC0
    -- pod przyszłe SSO: (dostawca, subject) z tokena OIDC
    sso_provider text,
    sso_subject  text,
    created_at   timestamptz NOT NULL DEFAULT now(),
    UNIQUE (household_id, id),
    UNIQUE (sso_provider, sso_subject)
);

CREATE TABLE sessions (
    token_hash   bytea PRIMARY KEY,
    member_id    uuid        NOT NULL REFERENCES members (id) ON DELETE CASCADE,
    created_at   timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now()
);

-- Dziennik zmian (outbox). Wypełniany wyłącznie przez trigger oiko_capture.
CREATE TABLE changes (
    household_id uuid        NOT NULL REFERENCES households (id) ON DELETE CASCADE,
    seq          bigint      NOT NULL,
    entity       text        NOT NULL,
    entity_id    uuid        NOT NULL,
    op           text        NOT NULL CHECK (op IN ('insert', 'update', 'delete')),
    before       jsonb,
    after        jsonb,
    actor_id     uuid,
    mutation_id  uuid,
    created_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (household_id, seq)
);
CREATE INDEX changes_created_at_idx ON changes (created_at);

-- +goose StatementBegin
CREATE FUNCTION oiko_capture() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    hh uuid;
    s  bigint;
BEGIN
    IF TG_OP = 'DELETE' THEN hh := OLD.household_id; ELSE hh := NEW.household_id; END IF;

    UPDATE households SET seq = seq + 1 WHERE id = hh RETURNING seq INTO s;
    IF s IS NULL THEN
        -- gospodarstwo właśnie jest usuwane (kaskada) — nie ma komu rozgłaszać
        RETURN NULL;
    END IF;

    INSERT INTO changes (household_id, seq, entity, entity_id, op, before, after, actor_id, mutation_id)
    VALUES (hh, s, TG_TABLE_NAME,
            CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END,
            lower(TG_OP),
            CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END,
            CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END,
            nullif(current_setting('oiko.actor', true), '')::uuid,
            nullif(current_setting('oiko.mutation', true), '')::uuid);

    -- NOTIFY dociera do słuchaczy dopiero po COMMIT. Payload jest krótki
    -- (limit 8000 B) — treść zmiany serwer doczytuje z tabeli changes.
    PERFORM pg_notify('oiko_changes', hh::text || ':' || s::text);
    RETURN NULL;
END $$;
-- +goose StatementEnd

-- +goose StatementBegin
CREATE FUNCTION oiko_touch() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    NEW.version    := OLD.version + 1;
    RETURN NEW;
END $$;
-- +goose StatementEnd

-- Podpina tabelę modułu pod dziennik zmian (i version/updated_at).
-- Tabela musi mieć kolumny: id, household_id, updated_at, version.
-- +goose StatementBegin
CREATE FUNCTION oiko_track(tbl regclass) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE format('CREATE TRIGGER oiko_touch BEFORE UPDATE ON %s
                    FOR EACH ROW EXECUTE FUNCTION oiko_touch()', tbl);
    EXECUTE format('CREATE TRIGGER oiko_capture AFTER INSERT OR UPDATE OR DELETE ON %s
                    FOR EACH ROW EXECUTE FUNCTION oiko_capture()', tbl);
END $$;
-- +goose StatementEnd

-- +goose Down
DROP FUNCTION oiko_track(regclass);
DROP FUNCTION oiko_touch();
DROP FUNCTION oiko_capture();
DROP TABLE changes;
DROP TABLE sessions;
DROP TABLE members;
DROP TABLE households;
