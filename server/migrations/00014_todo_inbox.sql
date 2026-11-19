-- +goose Up

-- A member's inbox: things in tasks that concern them. Rows are written by the
-- server when a comment is added, a description gains a mention or a task is
-- assigned to someone else; the member only marks them read.
--   mention  — the member was mentioned ([@Name](member:<id>)) in a comment or description
--   reply    — a new comment in a thread the member takes part in
--   assigned — someone assigned the task to the member
ALTER TABLE todo_comments ADD CONSTRAINT todo_comments_household_id_id_key UNIQUE (household_id, id);
CREATE TABLE todo_inbox (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid        NOT NULL,
    member_id    uuid        NOT NULL,
    kind         text        NOT NULL CHECK (kind IN ('mention', 'reply', 'assigned')),
    list_id      uuid        NOT NULL,
    item_id      uuid,       -- null: a mention in the list's description
    comment_id   uuid,       -- null: about the description or the assignment
    actor_id     uuid,
    -- the task's (or list's) title and the comment's text when it happened
    title        text        NOT NULL,
    excerpt      text        NOT NULL DEFAULT '',
    read_at      timestamptz,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    version      int         NOT NULL DEFAULT 1,
    FOREIGN KEY (household_id, member_id) REFERENCES members (household_id, id) ON DELETE CASCADE,
    FOREIGN KEY (household_id, list_id) REFERENCES todo_lists (household_id, id) ON DELETE CASCADE,
    FOREIGN KEY (household_id, item_id) REFERENCES todo_items (household_id, id) ON DELETE CASCADE,
    FOREIGN KEY (household_id, comment_id) REFERENCES todo_comments (household_id, id) ON DELETE CASCADE,
    FOREIGN KEY (household_id, actor_id) REFERENCES members (household_id, id) ON DELETE SET NULL (actor_id)
);
CREATE INDEX todo_inbox_member_idx ON todo_inbox (household_id, member_id, created_at);
CREATE INDEX todo_inbox_item_idx ON todo_inbox (household_id, item_id);
SELECT oiko_track('todo_inbox');

-- +goose Down
DROP TABLE todo_inbox;
ALTER TABLE todo_comments DROP CONSTRAINT todo_comments_household_id_id_key;
