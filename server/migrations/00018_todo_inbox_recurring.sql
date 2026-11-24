-- +goose Up

-- An entry created by a recurring task template has no human actor, so it must
-- not read "someone assigned you". The kind stays "assigned" (older apps only
-- know mention/reply/assigned); this flag lets newer apps word it properly.
ALTER TABLE todo_inbox ADD COLUMN recurring boolean NOT NULL DEFAULT false;

-- +goose Down
ALTER TABLE todo_inbox DROP COLUMN recurring;
