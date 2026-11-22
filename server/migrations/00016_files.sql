-- +goose Up

-- Uploaded files of a household, stored in the database for now. Not in the
-- change feed (the data would land in changes); owners such as
-- todo_attachments reference them, and files no owner references are deleted
-- a day after upload (core.Files.Cleanup).
CREATE TABLE files (
    id           uuid PRIMARY KEY,
    household_id uuid        NOT NULL REFERENCES households (id) ON DELETE CASCADE,
    name         text        NOT NULL,
    mime         text        NOT NULL,
    size         bigint      NOT NULL,
    data         bytea       NOT NULL,
    created_by   uuid,
    created_at   timestamptz NOT NULL DEFAULT now(),
    UNIQUE (household_id, id)
);
-- photos and archives are compressed already
ALTER TABLE files ALTER COLUMN data SET STORAGE EXTERNAL;

-- Files attached to a task (comment_id null) or to one of its comments.
-- The id is the file's id; deleting the file deletes the attachment.
CREATE TABLE todo_attachments (
    id           uuid PRIMARY KEY,
    household_id uuid        NOT NULL,
    item_id      uuid        NOT NULL,
    comment_id   uuid,
    name         text        NOT NULL,
    mime         text        NOT NULL,
    size         bigint      NOT NULL,
    created_by   uuid,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    version      int         NOT NULL DEFAULT 1,
    FOREIGN KEY (household_id, id) REFERENCES files (household_id, id) ON DELETE CASCADE,
    FOREIGN KEY (household_id, item_id) REFERENCES todo_items (household_id, id) ON DELETE CASCADE,
    FOREIGN KEY (household_id, comment_id) REFERENCES todo_comments (household_id, id) ON DELETE CASCADE,
    FOREIGN KEY (household_id, created_by) REFERENCES members (household_id, id) ON DELETE SET NULL (created_by)
);
CREATE INDEX todo_attachments_item_idx ON todo_attachments (household_id, item_id);
SELECT oiko_track('todo_attachments');

-- +goose Down
DROP TABLE todo_attachments;
DROP TABLE files;
