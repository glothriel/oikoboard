# Capability: recurring-tasks

Archived from the Delta of `.ai/specs/2026-11-23-recurring-tasks.md` (issue #27).

#### ADDED Requirement: Recurring task template
The system SHALL let a household member define a template that names a target list, task fields, an RRULE schedule, a creation time, and an optional relative due date.

##### Scenario: Create a weekly template
- WHEN a member creates a template with `FREQ=WEEKLY;BYDAY=MO,FR` and due offset 2
- THEN the template is stored, shown in the list view's recurring drawer, and its next occurrences are previewed

#### ADDED Requirement: Scheduled task creation
The system SHALL create exactly one task per matching local date for each active template, at the template's creation time in the household timezone.

##### Scenario: Occurrence day
- WHEN the local date matches the template's RRULE and the creation time is reached
- THEN a task with the template's title, description and assignee appears in the target list, with due = occurrence date + offset (and the template's due time)

##### Scenario: Non-matching day
- WHEN the local date does not match the RRULE, or is outside `start_date`..`end_date`, or the template is paused
- THEN no task is created

##### Scenario: Duplicate trigger
- WHEN the same occurrence is triggered twice (restart, two instances)
- THEN still only one task exists for that occurrence

#### ADDED Requirement: Catch-up after downtime
The system SHALL, after the server was down through one or more occurrences, create only the latest missed occurrence when it comes back.

##### Scenario: Missed Monday and Friday
- WHEN the server was down over a Monday and a Friday occurrence and restarts on Saturday
- THEN one task (for Friday) is created

#### ADDED Requirement: Pausing and deleting
The system SHALL stop creating tasks when a template is paused or deleted, and SHALL keep tasks it already created.

##### Scenario: Delete template
- WHEN a member deletes a template
- THEN no further tasks are created and previously created tasks remain

