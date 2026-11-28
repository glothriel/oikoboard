-- +goose Up
-- Members join the change feed. The account's picture is denormalized into
-- members.picture so a live row can carry it.
ALTER TABLE members ADD COLUMN picture text;

UPDATE members m SET picture = u.picture FROM users u WHERE u.id = m.user_id;

-- +goose StatementBegin
CREATE FUNCTION members_sync_picture() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.picture := (SELECT picture FROM users WHERE id = NEW.user_id);
    RETURN NEW;
END $$;
-- +goose StatementEnd

CREATE TRIGGER members_sync_picture BEFORE INSERT OR UPDATE OF user_id ON members
    FOR EACH ROW EXECUTE FUNCTION members_sync_picture();

-- +goose StatementBegin
CREATE FUNCTION users_sync_picture() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE members SET picture = NEW.picture WHERE user_id = NEW.id;
    RETURN NULL;
END $$;
-- +goose StatementEnd

CREATE TRIGGER users_sync_picture AFTER UPDATE OF picture ON users
    FOR EACH ROW WHEN (OLD.picture IS DISTINCT FROM NEW.picture)
    EXECUTE FUNCTION users_sync_picture();

-- members has no version/updated_at, so only the capture trigger of oiko_track.
CREATE TRIGGER oiko_capture AFTER INSERT OR UPDATE OR DELETE ON members
    FOR EACH ROW EXECUTE FUNCTION oiko_capture();

-- +goose Down
DROP TRIGGER oiko_capture ON members;
DROP TRIGGER users_sync_picture ON users;
DROP FUNCTION users_sync_picture();
DROP TRIGGER members_sync_picture ON members;
DROP FUNCTION members_sync_picture();
ALTER TABLE members DROP COLUMN picture;
