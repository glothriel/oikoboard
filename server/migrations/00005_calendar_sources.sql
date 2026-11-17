-- +goose Up

-- Calendars are no longer stored locally: every calendar lives in an external
-- provider (Google, later CalDAV) and the database keeps a mirror of it.
-- Old local events are dropped.
DROP TABLE calendar_events;

-- An account's link to a calendar provider (OAuth grant). Belongs to the user
-- who connected it; calendars of several households may use it.
CREATE TABLE calendar_connections (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       uuid REFERENCES users (id) ON DELETE SET NULL,
    provider      text        NOT NULL,          -- 'google' | 'mock'
    account       text        NOT NULL DEFAULT '', -- e.g. the Google e-mail
    credentials   text        NOT NULL DEFAULT '', -- encrypted (see core.Secrets)
    status        text        NOT NULL DEFAULT 'ok' CHECK (status IN ('ok', 'revoked')),
    created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX calendar_connections_user_idx ON calendar_connections (user_id);

-- A provider calendar linked to a household.
CREATE TABLE calendars (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id  uuid        NOT NULL REFERENCES households (id) ON DELETE CASCADE,
    connection_id uuid        NOT NULL REFERENCES calendar_connections (id) ON DELETE CASCADE,
    remote_id     text        NOT NULL,
    name          text        NOT NULL,
    color         bigint      NOT NULL DEFAULT 4284246976,
    writable      boolean     NOT NULL DEFAULT true,
    timezone      text        NOT NULL DEFAULT 'UTC', -- default for new timed/recurring events
    account       text        NOT NULL DEFAULT '',    -- connection account, for display
    sync_error    text        NOT NULL DEFAULT '',
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    version       int         NOT NULL DEFAULT 1,
    UNIQUE (household_id, id),
    UNIQUE (household_id, connection_id, remote_id)
);
SELECT oiko_track('calendars');

-- Sync bookkeeping, kept out of the tracked table so polling doesn't produce changes.
CREATE TABLE calendar_sync_state (
    calendar_id uuid PRIMARY KEY REFERENCES calendars (id) ON DELETE CASCADE,
    sync_token  text NOT NULL DEFAULT '',
    synced_at   timestamptz
);

-- Mirror of provider events: series masters, exceptions and single events,
-- in a provider-neutral (iCalendar-shaped) form. Not tracked — clients read
-- the materialized occurrences below.
CREATE TABLE calendar_remote_events (
    id             uuid PRIMARY KEY,               -- uuid5(calendar_id, remote_id) or client-chosen
    household_id   uuid        NOT NULL,
    calendar_id    uuid        NOT NULL,
    remote_id      text        NOT NULL,
    etag           text        NOT NULL DEFAULT '',
    remote_updated timestamptz NOT NULL,
    status         text        NOT NULL DEFAULT 'confirmed', -- confirmed | tentative | cancelled
    title          text        NOT NULL DEFAULT '',
    description    text        NOT NULL DEFAULT '',
    location       text        NOT NULL DEFAULT '',
    starts_at      timestamptz,                    -- NULL only for cancelled exceptions
    ends_at        timestamptz,
    all_day        boolean     NOT NULL DEFAULT false,
    timezone       text        NOT NULL DEFAULT '',
    recurrence     jsonb       NOT NULL DEFAULT '[]', -- RRULE/EXDATE/RDATE lines
    series_remote_id text,                          -- exception: remote_id of its master
    original_start timestamptz,                    -- exception: start of the replaced instance
    member_ids     uuid[]      NOT NULL DEFAULT '{}',
    attendee_emails jsonb      NOT NULL DEFAULT '[]',
    FOREIGN KEY (household_id, calendar_id) REFERENCES calendars (household_id, id) ON DELETE CASCADE,
    UNIQUE (calendar_id, remote_id)
);
CREATE INDEX calendar_remote_events_series_idx ON calendar_remote_events (calendar_id, series_remote_id);

-- Occurrences: what the app, views and the assistant read. Derived from the
-- mirror (recurring series expanded within a window) in the same transaction.
CREATE TABLE calendar_events (
    id             uuid PRIMARY KEY,
    household_id   uuid        NOT NULL,
    calendar_id    uuid        NOT NULL,
    event_id       uuid        NOT NULL,           -- calendar_remote_events.id of the series/single event
    title          text        NOT NULL,
    description    text        NOT NULL DEFAULT '',
    location       text        NOT NULL DEFAULT '',
    starts_at      timestamptz NOT NULL,
    ends_at        timestamptz NOT NULL,
    all_day        boolean     NOT NULL DEFAULT false,
    member_ids     uuid[]      NOT NULL DEFAULT '{}',
    recurrence     jsonb       NOT NULL DEFAULT '[]', -- of the series (for display/editing)
    original_start timestamptz,                    -- set for occurrences of a series
    remote_key     text        NOT NULL,           -- remote_id of the series/single event (internal)
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    version        int         NOT NULL DEFAULT 1,
    FOREIGN KEY (household_id, calendar_id) REFERENCES calendars (household_id, id) ON DELETE CASCADE,
    CHECK (ends_at >= starts_at)
);
CREATE INDEX calendar_events_range_idx ON calendar_events (household_id, starts_at, ends_at);
CREATE INDEX calendar_events_key_idx ON calendar_events (calendar_id, remote_key);
SELECT oiko_track('calendar_events');

-- Data of the mock provider (dev/tests): stands in for Google's servers.
CREATE TABLE mock_provider_calendars (
    connection_id uuid NOT NULL REFERENCES calendar_connections (id) ON DELETE CASCADE,
    remote_id     text NOT NULL,
    name          text NOT NULL,
    color         bigint NOT NULL,
    PRIMARY KEY (connection_id, remote_id)
);
CREATE TABLE mock_provider_events (
    connection_id uuid   NOT NULL,
    calendar_id   text   NOT NULL,
    remote_id     text   NOT NULL,
    seq           bigserial,
    data          jsonb  NOT NULL,
    deleted       boolean NOT NULL DEFAULT false,
    PRIMARY KEY (connection_id, calendar_id, remote_id),
    FOREIGN KEY (connection_id, calendar_id) REFERENCES mock_provider_calendars (connection_id, remote_id) ON DELETE CASCADE
);

-- Calendar connect flows reuse auth_flows (same Google callback).
ALTER TABLE auth_flows
    ADD COLUMN purpose text NOT NULL DEFAULT 'login' CHECK (purpose IN ('login', 'calendar')),
    ADD COLUMN result  text; -- calendar: encrypted credentials until the app completes the flow

-- +goose Down
ALTER TABLE auth_flows DROP COLUMN purpose, DROP COLUMN result;
DROP TABLE mock_provider_events;
DROP TABLE mock_provider_calendars;
DROP TABLE calendar_events;
DROP TABLE calendar_remote_events;
DROP TABLE calendar_sync_state;
DROP TABLE calendars;
DROP TABLE calendar_connections;
CREATE TABLE calendar_events (
    id           uuid PRIMARY KEY,
    household_id uuid        NOT NULL REFERENCES households (id) ON DELETE CASCADE,
    title        text        NOT NULL,
    starts_at    timestamptz NOT NULL,
    ends_at      timestamptz NOT NULL,
    all_day      boolean     NOT NULL DEFAULT false,
    member_ids   uuid[]      NOT NULL DEFAULT '{}',
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    version      int         NOT NULL DEFAULT 1,
    CHECK (ends_at >= starts_at)
);
CREATE INDEX calendar_events_range_idx ON calendar_events (household_id, starts_at, ends_at);
SELECT oiko_track('calendar_events');
