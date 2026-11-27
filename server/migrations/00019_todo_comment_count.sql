-- +goose Up

-- Number of comments on a task, kept in step with todo_comments by a trigger, so a
-- task row alone tells clients whether it has comments (no extra view needed).
ALTER TABLE todo_items ADD COLUMN comment_count int NOT NULL DEFAULT 0;

UPDATE todo_items i SET comment_count = (
    SELECT count(*) FROM todo_comments c WHERE c.household_id = i.household_id AND c.item_id = i.id);

-- +goose StatementBegin
CREATE FUNCTION todo_comment_count_sync() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE todo_items SET comment_count = comment_count + 1
            WHERE household_id = NEW.household_id AND id = NEW.item_id;
        RETURN NEW;
    END IF;
    -- No-op when the task itself is being deleted (its row is already gone).
    UPDATE todo_items SET comment_count = comment_count - 1
        WHERE household_id = OLD.household_id AND id = OLD.item_id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;
-- +goose StatementEnd

CREATE TRIGGER todo_comment_count_sync AFTER INSERT OR DELETE ON todo_comments
    FOR EACH ROW EXECUTE FUNCTION todo_comment_count_sync();

-- +goose Down
DROP TRIGGER todo_comment_count_sync ON todo_comments;
DROP FUNCTION todo_comment_count_sync();
ALTER TABLE todo_items DROP COLUMN comment_count;
