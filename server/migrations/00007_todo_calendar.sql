-- +goose Up

-- A task's due is a calendar date (it was local midnight as timestamptz;
-- +12h lands on the intended day for any UTC offset within ±12h).
ALTER TABLE todo_items
    ALTER COLUMN due TYPE date USING ((due AT TIME ZONE 'UTC') + interval '12 hours')::date;
CREATE INDEX todo_items_due_idx ON todo_items (household_id, due) WHERE NOT done AND due IS NOT NULL;

-- Events Oikoboard manages itself (e.g. 'todo-day': the day's due tasks);
-- empty for ordinary events. Stored in the event at the provider, see docs/calendar.md.
ALTER TABLE calendar_remote_events ADD COLUMN kind text NOT NULL DEFAULT '';
ALTER TABLE calendar_events ADD COLUMN kind text NOT NULL DEFAULT '';
CREATE INDEX calendar_remote_events_kind_idx ON calendar_remote_events (household_id, kind) WHERE kind <> '';

-- The household calendar that receives due tasks (at most one).
ALTER TABLE calendars ADD COLUMN todo_target boolean NOT NULL DEFAULT false;
CREATE UNIQUE INDEX calendars_todo_target_idx ON calendars (household_id) WHERE todo_target;
UPDATE calendars c SET todo_target = true
WHERE c.id IN (SELECT DISTINCT ON (household_id) id FROM calendars
               WHERE writable ORDER BY household_id, created_at, id);

-- +goose Down
DROP INDEX calendars_todo_target_idx;
ALTER TABLE calendars DROP COLUMN todo_target;
DROP INDEX calendar_remote_events_kind_idx;
ALTER TABLE calendar_events DROP COLUMN kind;
ALTER TABLE calendar_remote_events DROP COLUMN kind;
DROP INDEX todo_items_due_idx;
ALTER TABLE todo_items ALTER COLUMN due TYPE timestamptz USING due::timestamptz;
