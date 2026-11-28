# Tasks

## [ ] T1: Compact assignee row and collapsible "More options" in the task editor
**Goal:** Declutter the task editor sheet by hiding rare fields and compacting the assignee choice.
**Acceptance criteria:**
- List selector, Keep forever and Description are inside a "More options" section after the due date; it starts expanded only if the description is non-empty or Keep forever is on (R1, R2).
- The list selector is not shown when there is a single list (R3).
- The attach button is in the header bar before Comments and Delete (also on a new task) and the "Attachments" label row is gone; attached files still show below "More options" (R8).
- Assignee is one inline row with a short label and chips; "Nobody" is an icon chip with a tooltip (R4).
- Saving, done, delete, comments and attachments are unchanged, including edits made in a collapsed section (R5).
- New strings exist in en and pl (R6).
**Changes:**
- Mockup: `centurion-mockups/issue-76` — reuse the `_TodoItemEditorState.build` rework (ExpansionTile "More options", inline assignee Wrap with icon Nobody chip) and the two l10n keys; adapt rather than copy.
- `app/lib/modules/todo/todo_screen.dart` — rework `_TodoItemEditorState.build`: ExpansionTile (`initiallyExpanded` from item description/keepForever) holding list dropdown, keep-forever switch, MarkdownField; inline assignee Wrap.
- `app/lib/modules/todo/todo_screen.dart` — move `AttachButton` into `EditorSheet.actions` before Comments and Delete (also for new tasks); drop the Attachments label row, keep `AttachmentStrip`.
- `app/lib/l10n/app_en.arb` — add `todoMoreOptions` ("More options") and `todoAssignee` ("Assignee"); remove `todoWhoDoesIt` if unused.
- `app/lib/l10n/app_pl.arb` — Polish translations of the same keys.
- `app/test/todo_editor_declutter_mock_test.dart` — widget tests on the mock backend: collapsed by default, expanded with a description or keep-forever, nobody icon chip, change in the section saves, attach button in the header bar.
- `app/test/todo_*_test.dart` — existing todo editor tests (description, keep forever, move, new task) that use the hidden fields expand the section first.
