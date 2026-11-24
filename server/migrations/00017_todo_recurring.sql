-- +goose Up

-- Recurring task templates: on every date matching the RRULE the server
-- creates a task in the target list (see docs/architecture.md).
CREATE TABLE todo_recurring (
    id              uuid PRIMARY KEY,
    household_id    uuid        NOT NULL REFERENCES households (id) ON DELETE CASCADE,
    list_id         uuid        NOT NULL,
    title           text        NOT NULL,
    description     text        NOT NULL DEFAULT '',
    assignee_id     uuid,
    -- RFC 5545 rule without DTSTART, COUNT and UNTIL (those are start_date,
    -- create_time and end_date).
    rrule           text        NOT NULL,
    start_date      date        NOT NULL,
    end_date        date,
    -- household local time at which the task is created
    create_time     time        NOT NULL DEFAULT '06:00',
    -- due = occurrence date + offset; NULL = the task has no due date
    due_offset_days int CHECK (due_offset_days BETWEEN 0 AND 366),
    due_time        time,
    active          boolean     NOT NULL DEFAULT true,
    -- the last date the schedule has been processed for (catch-up bound)
    last_run_date   date,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    version         int         NOT NULL DEFAULT 1,
    UNIQUE (household_id, id),
    CHECK (end_date IS NULL OR end_date >= start_date),
    CHECK (due_time IS NULL OR due_offset_days IS NOT NULL),
    FOREIGN KEY (household_id, list_id)
        REFERENCES todo_lists (household_id, id) ON DELETE CASCADE,
    FOREIGN KEY (household_id, assignee_id)
        REFERENCES members (household_id, id) ON DELETE SET NULL (assignee_id)
);
CREATE INDEX todo_recurring_household_idx ON todo_recurring (household_id, list_id);
SELECT oiko_track('todo_recurring');

-- Generated tasks remember their template and occurrence; the unique index
-- makes generation idempotent. Deleting a template keeps its tasks.
ALTER TABLE todo_items
    ADD COLUMN recurring_id    uuid,
    ADD COLUMN occurrence_date date,
    ADD FOREIGN KEY (household_id, recurring_id)
        REFERENCES todo_recurring (household_id, id) ON DELETE SET NULL (recurring_id);
CREATE UNIQUE INDEX todo_items_occurrence_idx ON todo_items (recurring_id, occurrence_date)
    WHERE recurring_id IS NOT NULL;

-- +goose Down
DROP INDEX todo_items_occurrence_idx;
ALTER TABLE todo_items DROP COLUMN recurring_id, DROP COLUMN occurrence_date;
DROP TABLE todo_recurring;
