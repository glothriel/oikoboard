# Task row indicators: comments and recurring

Source: issue #46.

## Goal
In a task list row, next to the existing "has a description" icon, show an icon when the task has
comments and an icon when the task was created by a recurring task, so users see this without opening the task.

## Requirements
- R1: A task with at least one comment shows a comments icon (no count) in its row; it appears and disappears live as comments are added or deleted.
- R2: A task created from a recurring task template shows a recurring icon in its row, also after the template is deleted.
- R3: Both icons look like the description icon (size 18, outline colour, tooltip) and sit in the trailing row before the assignee avatar, in the order recurring, comments, description. They show for open and done tasks and do not change tapping the row.
- R4: The server task payload carries `comment_count` (int, read-only, kept in step with `todo_comments`) and the existing `occurrence_date`.
- R5: The mock backend shows both indicators with made-up sample data and keeps `comment_count` correct when comments are added or deleted.
- R6: New strings exist in `app_en.arb` and `app_pl.arb`.

## UI
- Todo list screen (`TodoListScreen` task rows), also used for the same row elsewhere if it is the same widget: the trailing indicators.

## Out of scope
- Comment counts on the row; attachments indicator; indicators on the calendar or the recurring drawer.

## Backward compatibility
Additive: `todo_items.comment_count` is a new column with default 0 and a backfill; the API only gains a field, older app versions ignore it. Newer apps against an older server read a missing `comment_count` as 0 (no icon). Migration has a down.

## Decisions and why
- Recurring means `occurrence_date != null`, not `recurring_id != null`: deleting a template sets `recurring_id` to NULL but keeps `occurrence_date`, and R2 wants the icon to stay.
- Comment presence is a `comment_count` column on `todo_items` maintained by a trigger on `todo_comments`, rather than a client-side lookup: the list screen has no comments view for all tasks, and an item row update is delivered to clients by the existing `todo_items` change feed with no new view. Cost: each comment add/delete bumps the item's `version`/`updated_at`; accepted (a comment is activity on the task). A count is stored although only presence is shown; it is as simple as a boolean and cannot drift on concurrent deletes.
- Icons: `Icons.repeat` (as in the recurring drawer) and `Icons.forum_outlined` (as the comments button in the editor). Tooltips: "Created from a recurring task", "Has comments".
