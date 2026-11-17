-- +goose Up

CREATE TABLE todo_lists (
    id           uuid PRIMARY KEY,
    household_id uuid        NOT NULL REFERENCES households (id) ON DELETE CASCADE,
    name         text        NOT NULL,
    color        bigint      NOT NULL DEFAULT 4280723098, -- 0xFF26A69A
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    version      int         NOT NULL DEFAULT 1,
    UNIQUE (household_id, id)
);

CREATE TABLE todo_items (
    id           uuid PRIMARY KEY,
    household_id uuid        NOT NULL,
    list_id      uuid        NOT NULL,
    title        text        NOT NULL,
    done         boolean     NOT NULL DEFAULT false,
    done_at      timestamptz,
    assignee_id  uuid,
    due          timestamptz,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    version      int         NOT NULL DEFAULT 1,
    FOREIGN KEY (household_id, list_id)
        REFERENCES todo_lists (household_id, id) ON DELETE CASCADE,
    FOREIGN KEY (household_id, assignee_id)
        REFERENCES members (household_id, id) ON DELETE SET NULL (assignee_id)
);
CREATE INDEX todo_items_list_idx ON todo_items (household_id, list_id);
CREATE INDEX todo_items_open_idx ON todo_items (household_id) WHERE NOT done;

SELECT oiko_track('todo_lists');
SELECT oiko_track('todo_items');

-- +goose Down
DROP TABLE todo_items;
DROP TABLE todo_lists;
