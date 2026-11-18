-- +goose Up

-- A whole list can have a due date (e.g. a packing list for a trip).
ALTER TABLE todo_lists ADD COLUMN due date;

-- Comments on a task: a thread under the item.
ALTER TABLE todo_items ADD CONSTRAINT todo_items_household_id_id_key UNIQUE (household_id, id);
CREATE TABLE todo_comments (
    id           uuid PRIMARY KEY,
    household_id uuid        NOT NULL,
    item_id      uuid        NOT NULL,
    author_id    uuid,
    body         text        NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    version      int         NOT NULL DEFAULT 1,
    FOREIGN KEY (household_id, item_id)
        REFERENCES todo_items (household_id, id) ON DELETE CASCADE,
    FOREIGN KEY (household_id, author_id)
        REFERENCES members (household_id, id) ON DELETE SET NULL (author_id)
);
CREATE INDEX todo_comments_item_idx ON todo_comments (household_id, item_id);
SELECT oiko_track('todo_comments');

-- The calendar view is remembered on the device now, not per member on the server.
DROP TABLE calendar_preferences;

-- +goose Down
CREATE TABLE calendar_preferences (
    member_id    uuid PRIMARY KEY,
    household_id uuid        NOT NULL,
    view         text        NOT NULL DEFAULT 'month' CHECK (view IN ('day', '3days', 'week', 'month')),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (household_id, member_id) REFERENCES members (household_id, id) ON DELETE CASCADE
);
DROP TABLE todo_comments;
ALTER TABLE todo_items DROP CONSTRAINT todo_items_household_id_id_key;
ALTER TABLE todo_lists DROP COLUMN due;
