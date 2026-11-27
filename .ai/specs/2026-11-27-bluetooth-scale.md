# Bluetooth scale: weight and body composition

Source: issue #34.

## Goal
Household members record body weight (and, when the scale reports impedance, body composition) by weighing on a
Xiaomi Mi Body Composition Scale 2 over Bluetooth, and see the household's history in a new Fitness section.
The model stays clean enough to export to Garmin Connect later.

## Requirements
- R1: Server table `measurements` (household- and member-scoped, typed columns, kg) with REST add and delete and a realtime view; every household member sees all measurements.
- R2: Server table `fitness_profiles` (sex, birth date, height) with one row per member, written only by that member, with a realtime view.
- R3: Body composition (variant B of the issue: LBM, fat %, water %, protein %, bone, muscle, BMR, visceral fat, BMI) is computed on the device from weight, impedance and the member's profile; skipped (weight only) without a profile or without impedance.
- R4: A `ScaleDriver` interface, an ordered driver registry (first match wins) and a GATT session class; the Mi Scale 2 driver implements the v2 connect sequence and 13-byte frames, and the v1 weight-only 10-byte records, including kg/lb/jin parsing.
- R5: Only stable, not-removed frames are kept; frames at or before the last imported timestamp of that scale (minute resolution) are dropped.
- R6: Weigh-in screen (Android, real server): connects to the scale, lists the received readings; each reading has a member picker defaulting to the member with the most similar recent results, a Save action and a Discard action.
- R7: The suggested member is the one whose last 2 measurements (if both are from the last 30 days, else only the last one) are closest to the reading by weight plus absolute impedance difference; no data at all → the signed-in member.
- R8: New top-level Fitness module (4th nav item) with a hub screen, a Measurements sub-route (trend + list, manual add, delete) and a Fitness profile form; Workouts and Calories are not shown.
- R9: Home wall tile shows the signed-in member's latest weight.
- R10: Everything works in the mock backend (`Mock*` repositories, a fake scale in mock mode); the mock wins over the platform, so the weigh-in screen is reachable in the mock on web too; with the real server on web the weigh-in entry is hidden and manual entry works.
- R11: All new UI strings exist in `app_en.arb` and `app_pl.arb`; weights are displayed in kg only.
- R12: Body data is not readable by OAuth/MCP (delegated) clients: the `fitness.*` views and `/fitness/` routes refuse them.

## UI
- Fitness hub (one Measurements card with latest weight and trend)
- Measurements screen (trend chart, list, empty state) and the add-measurement sheet
- Fitness profile form
- Weigh-in screen (scan/connect states, readings with member picker, Save, Discard)
- Home wall tile "Weight"

Prototype: branch `em-mockups/issue-34` (never merged) holds all five views; tasks T5–T7 reuse it.

## Out of scope
- Workouts and Calories sections, any placeholder for them
- Garmin Connect (or other) exporter
- Web Bluetooth, connectionless/broadcast mode, variant A formulas
- lb/jin display units, per-member privacy of body data, push of live-mode partial frames

## Decisions and why
- Clean-room: the Mi Scale protocol and formulas are implemented from the issue text only, as the author required.
- `fitness_profiles.id` is the member id (FK to `members`): `oiko_track` needs an `id` column, and it makes the row one-per-member without a lookup. Written by `POST /fitness/profiles` as an upsert for the caller's own member only (403 otherwise).
- Measurements are written for any member by any household member (the scale cannot tell people apart and mistakes must be fixable), so any household member may delete any measurement; household data is shared like todos.
- Composition is stored in typed nullable columns computed at save time with the saved member's profile (not at read time), so later profile edits don't rewrite history; `source` (`scale`/`manual`) is kept for a future exporter.
- Dedup is client-side, keyed by the scale's BLE device id (the member is only chosen after the transfer), persisted with `DevicePrefs`; discarded readings also advance it so they don't return. No server unique constraint: client UUIDs already make a retried POST idempotent.
- The "wait for impedance in live mode" open question is not implemented: GATT history transfer delivers finished records; a stable frame without impedance is stored as weight only.
- Mi Scale user id in the `01 FF FF hi lo` / `04 FF FF hi lo` commands is fixed to 0 (one logical user), since members are picked in the app.
- Trend is a small custom painted line chart, no charting dependency.
- BLE uses `flutter_blue_plus` behind a `GattIo` abstraction, so drivers and the session are unit-tested with fake byte streams and no plugin.
- Similarity compares weight in kg plus |impedance difference|/100, so both are of similar magnitude; the weights of the formula are a constant in code.

- Delegated (ChatGPT/MCP) clients may read any view snapshot via `ToolAllowed`; the fitness views are explicitly excluded for them because weight and birth date are sensitive. Writes were already disallowed by default.
- Deleting a member or household cascades to their measurements and profile (composite FKs, as todo tables).
- Dedup is per scale, so the first connect to a scale never seen on this device asks only for its last record and stores that timestamp; older stored history is intentionally not imported.

## Backward compatibility
None breaking: a new migration adds two tables, new REST routes and two new views/entity types (`measurements`, `fitness_profiles`); existing endpoints, entities and data are untouched, and the new views are not exposed to OAuth/MCP clients, and older app versions simply never read the new views. A new app against an older server shows the Fitness section only once its views exist; no compatibility path is added for that.
