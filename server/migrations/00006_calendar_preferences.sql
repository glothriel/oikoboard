-- +goose Up

-- Per-member calendar settings (follow the member across devices). Not
-- tracked: nobody else watches them, the app reads them over REST.
CREATE TABLE calendar_preferences (
    member_id    uuid PRIMARY KEY,
    household_id uuid        NOT NULL,
    view         text        NOT NULL DEFAULT 'month' CHECK (view IN ('day', '3days', 'week', 'month')),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (household_id, member_id) REFERENCES members (household_id, id) ON DELETE CASCADE
);

-- +goose Down
DROP TABLE calendar_preferences;
