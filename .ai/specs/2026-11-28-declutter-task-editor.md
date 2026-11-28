# Declutter the edit task item view

Source: issue #76.

## Goal
The task editor sheet puts title, assignee, due date and attachments first, and tucks the rarely used list selector, Keep forever and Description into a collapsible "More options" section. The assignee block becomes compact and inline.

## Requirements
- R1: The list selector, the Keep forever switch and the Description field sit in one collapsible section titled "More options", placed after the due date and before attachments.
- R2: The section starts expanded when the task has a non-empty description or Keep forever is on; otherwise collapsed. This holds for new and existing tasks. The state is not persisted.
- R3: The list selector is still absent when there is only one list.
- R4: "Who will do it?" becomes a single inline row: a short label ("Assignee") followed by choice chips; "Nobody" is an icon-only chip (with tooltip "Nobody") and members stay avatar plus name chips.
- R5: Saving, marking done, delete, comments and attachments behave exactly as before; a value changed inside a collapsed section is still saved.
- R6: New or changed strings exist in `app_en.arb` and `app_pl.arb`; the old "Who will do it?" key is removed if unused.
- R7: Works on the mock backend (no mock changes expected).

## UI
- Task editor sheet (`_TodoItemEditor` in the todo module): reordered, with the "More options" section and the compact assignee row.
- Prototype: branch `centurion-mockups/issue-76` (never merged); the designer shows several alternative layouts and the human picks one on the plan PR.

## Out of scope
- Server/API/data model changes; the list editor sheet and recurring task editor; changes to due date, attachments or comments.

## Backward compatibility
None: app-only layout change, no stored data, API or protocol change.

## Decisions and why
- Section is Flutter's `ExpansionTile` (no divider borders) with `initiallyExpanded` computed once from the item: no new abstraction, state resets per open as agreed.
- The intent's "also open for a non-default list" is dropped: an existing task always has a list, so the rule would almost always open the section and defeat the purpose. A collapsed header shows no summary; the mockup step may revise this.
- Assignee label is shortened to "Assignee" and placed inline with the chips in a `Wrap`; the nobody chip is `Icons.person_off_outlined` with a tooltip, keeping the existing `ChoiceChip` selection behaviour.
- Single task: it is one widget in one file, split would not build on its own.
