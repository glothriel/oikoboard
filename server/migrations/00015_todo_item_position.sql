-- +goose Up

-- Manual order of a list's tasks, ascending. Seconds since the epoch at
-- creation, so new tasks go to the end; moving a task sets it between its new
-- neighbours' positions.
ALTER TABLE todo_items ADD COLUMN position double precision;
UPDATE todo_items SET position = extract(epoch FROM created_at);
ALTER TABLE todo_items ALTER COLUMN position SET NOT NULL,
    ALTER COLUMN position SET DEFAULT extract(epoch FROM now());

-- +goose Down
ALTER TABLE todo_items DROP COLUMN position;
