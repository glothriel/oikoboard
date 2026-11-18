-- +goose Up

-- Markdown description of a list and of a task.
ALTER TABLE todo_lists ADD COLUMN description text NOT NULL DEFAULT '';
ALTER TABLE todo_items ADD COLUMN description text NOT NULL DEFAULT '';

-- +goose Down
ALTER TABLE todo_items DROP COLUMN description;
ALTER TABLE todo_lists DROP COLUMN description;
