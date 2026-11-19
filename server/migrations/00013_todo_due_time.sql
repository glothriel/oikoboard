-- +goose Up

-- Optional time of a task's due date (household local time). A task with a
-- time gets its own event in the calendar instead of a line in the day's event.
ALTER TABLE todo_items ADD COLUMN due_time time;
ALTER TABLE todo_items ADD CONSTRAINT todo_items_due_time_needs_due CHECK (due_time IS NULL OR due IS NOT NULL);

-- +goose Down
ALTER TABLE todo_items DROP CONSTRAINT todo_items_due_time_needs_due;
ALTER TABLE todo_items DROP COLUMN due_time;
