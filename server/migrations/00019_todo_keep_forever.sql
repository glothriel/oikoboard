-- +goose Up

-- A task marked keep_forever is never removed by the completed-task cleanup.
ALTER TABLE todo_items ADD COLUMN keep_forever boolean NOT NULL DEFAULT false;

-- +goose Down
ALTER TABLE todo_items DROP COLUMN keep_forever;
