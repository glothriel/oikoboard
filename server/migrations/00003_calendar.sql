-- +goose Up

CREATE TABLE calendar_events (
    id           uuid PRIMARY KEY,
    household_id uuid        NOT NULL REFERENCES households (id) ON DELETE CASCADE,
    title        text        NOT NULL,
    starts_at    timestamptz NOT NULL,
    ends_at      timestamptz NOT NULL,
    all_day      boolean     NOT NULL DEFAULT false,
    -- członkowie rodziny; walidowane w aplikacji (FK na elementy tablicy nie istnieje)
    member_ids   uuid[]      NOT NULL DEFAULT '{}',
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    version      int         NOT NULL DEFAULT 1,
    CHECK (ends_at >= starts_at)
);
CREATE INDEX calendar_events_range_idx ON calendar_events (household_id, starts_at, ends_at);

SELECT oiko_track('calendar_events');

-- +goose Down
DROP TABLE calendar_events;
