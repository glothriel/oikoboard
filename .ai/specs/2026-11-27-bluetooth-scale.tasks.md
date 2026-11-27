# Tasks

## [x] T1: Server: measurements and fitness profiles
**Goal:** Store and broadcast household measurements and per-member fitness profiles.
**Acceptance criteria:**
- Measurements can be created (idempotent by client id) for any household member and deleted by any household member; foreign household or member ids are rejected (R1).
- A member can upsert only their own profile; another member's gets 403, and so does a caller without a selected member (`MemberID` nil) (R2).
- Both entity types reach websocket views `fitness.measurements` and `fitness.profiles` (R1, R2).
- An OAuth/MCP (delegated) client gets 403 on both views' snapshots and on all `/fitness/` routes (R12).
- Deleting a member or the household deletes their measurements and profile (cascade).
- `cd server && gofmt -l . && go vet ./... && go test -race ./...` passes with the new tests.
**Changes:**
- `server/migrations/00020_fitness.sql` — `measurements` (member_id, measured_at, weight_kg, nullable impedance and composition columns, source scale|manual) and `fitness_profiles` (id = member id, sex, birth_date, height_cm).
- `server/migrations/00020_fitness.sql` — composite FKs to `members` with `ON DELETE CASCADE`; `oiko_track` on both; Down drops them.
- `server/internal/modules/fitness/fitness.go` — package `fitness`: `Measurement` and `Profile` structs (json snake_case, as `todo.Item`), `Module{DB}`.
- `server/internal/modules/fitness/fitness.go` — routes `POST /fitness/measurements`, `DELETE /fitness/measurements/:id`, `POST /fitness/profiles` (upsert, own member only, nil member rejected).
- `server/internal/modules/fitness/fitness.go` — validates plausible weight, composition and height ranges and a past birth date; checks the member with `core.CheckMembers`; create idempotent as in `todo.Module.createItem`.
- `server/internal/modules/fitness/views.go` — views `fitness.measurements` (newest first) and `fitness.profiles`, no params, following `todo.lists`.
- `server/internal/realtime/` — snapshot (and subscribe, if reachable with such a token) of views named `fitness.*` is refused for `Actor.Restricted()`.
- `server/internal/core/tools.go` — `ToolAllowed` keeps `/api/v1/fitness/` disallowed (comment says why).
- `server/internal/app/app.go` — register `fitness.Module{DB: db}` in `Modules`.
- `server/internal/app/fitness_test.go` — create/retry/delete, bad member and weight, profile upsert, 403 for another member and for a nil member, member deletion cascades.
- `server/internal/app/fitness_test.go` — view snapshots, a change reaching a websocket subscriber, and a delegated (OAuth) token refused on the views and routes (pattern of `oauth_test.go`).
- `docs/architecture.md` — one bullet: Fitness module (`measurements`, `fitness_profiles`, composition computed on the device, scale access behind `ScaleDriver`, Android only).

## [x] T2: App: body composition calculator
**Goal:** A pure function computing variant B body composition from the issue's equations.
**Acceptance criteria:**
- Returns all fields of R3 for known inputs, applying every clamp and the sex/age branches (R3).
- `cd app && dart format --output=none --set-exit-if-changed . && flutter analyze && flutter test` passes.
**Changes:**
- `app/lib/modules/fitness/composition.dart` — `enum Sex`, `class BodyComposition` (bmi, fatPct, waterPct, proteinPct, boneKg, muscleKg, bmrKcal, visceralFat).
- `app/lib/modules/fitness/composition.dart` — `BodyComposition computeComposition({sex, age, heightCm, weightKg, impedance})` and `int ageAt(DateTime birth, DateTime at)`; callers skip it without impedance or profile.
- `app/test/fitness_composition_test.dart` — hand-computed values for a male and a female case, each Schofield age bracket, both visceral fat branches per sex, clamp boundaries, the LBM cap, `ageAt` around a birthday.

## [x] T3: App: scale driver framework and Mi Scale 2 protocol
**Goal:** The transport-independent scale layer: driver interface, registry, Mi Scale 2 parsing and connect sequences, dedup.
**Acceptance criteria:**
- The driver matches `MIBFS`/`MIBCS`/`MI SCALE2`/`MI_SCALE…` names, picks v2 under `0x181B` and v1 under `0x181D` (R4).
- v2 connect writes the six steps of the issue in order, with the "all records" fallback when no count arrives and the `03` end-of-transfer answers (R4).
- 13-byte frames (also two per 26-byte notification) and chunked 10-byte v1 records parse to kg for kg, lb and jin; unstable and weight-removed frames are dropped (R4, R5).
- Frames at or before the scale's last imported timestamp are dropped.
- The first connect to a never-seen scale requests only the last record and stores its timestamp, so a long history never floods the screen (R5).
- `cd app && dart format --output=none --set-exit-if-changed . && flutter analyze && flutter test` passes.
**Changes:**
- `app/lib/modules/fitness/scale/scale_driver.dart` — `abstract interface class GattIo` (`write`, `setNotify`, `serviceUuids`), `enum LinkMode {gatt, broadcast}`, `class ScaleReading` (time, weightKg, impedance?).
- `app/lib/modules/fitness/scale/scale_driver.dart` — `abstract class ScaleDriver`: `displayName`, `matches(name, serviceUuids)`, `linkMode`, `onConnected(GattIo)`, `onNotify(uuid, bytes)`, `Stream<ScaleReading> readings`.
- `app/lib/modules/fitness/scale/mi_scale2.dart` — `MiScale2Driver`: UUIDs, v2 and v1 connect sequences, frame and record parsing, fallback timer with an injectable delay.
- `app/lib/modules/fitness/scale/registry.dart` — ordered `scaleDrivers` list and `ScaleDriver? driverFor(name, serviceUuids)`; first match wins.
- `app/lib/modules/fitness/scale/import_cursor.dart` — `ImportCursor` per scale id: last timestamp at minute resolution via `DevicePrefs`, `isNew`, `advance`, `isKnown` (false for a never-seen scale).
- `app/test/fitness_mi_scale_test.dart` — a second fake driver registered in a test registry is picked for its own device name, proving the registry is open.
- `app/test/fitness_mi_scale_test.dart` — fake `GattIo` recording writes; frames for kg/lb/jin, stable/removed/impedance flags, double frame, v1 chunks, name matching, fallback timer, cursor.

## [x] T4: App: fitness data layer with mock
**Goal:** Models, repository with `Api*` and `Mock*` implementations, providers and member suggestion.
**Acceptance criteria:**
- Measurements and profiles stream from the views and update live; add and delete go through the outbox; profile save is an upsert for the signed-in member (R1, R2).
- The mock backend seeds a few measurements and one profile of made-up members and behaves like the server (R10).
- `suggestMember` returns the closest member per R7 and falls back to the signed-in member (R7).
- `cd app && dart format --output=none --set-exit-if-changed . && flutter analyze && flutter test` passes.
**Changes:**
- `app/lib/modules/fitness/models.dart` — `Measurement` and `FitnessProfile` with `fromJson`/`toJson`/`copyWith`, field names as the server's.
- `app/lib/modules/fitness/repository.dart` — `FitnessRepository`: `watchMeasurements`, `watchProfiles`, `addMeasurement`, `deleteMeasurement`, `saveProfile`.
- `app/lib/modules/fitness/repository.dart` — `ApiFitnessRepository` (sync views + `Mutation`, as `ApiTodoRepository`) and `MockFitnessRepository` on `MockStore`.
- `app/lib/modules/fitness/repository.dart` — `fitnessRepositoryProvider`, stream providers for measurements and profiles, and a `seedFitnessMock(MockStore)` helper.
- `app/lib/modules/fitness/suggest.dart` — `String suggestMember({reading, all, now, fallbackMemberId})` implementing R7; distance is |Δweight kg| + |Δimpedance|/100.
- `app/test/fitness_repository_mock_test.dart` — add, delete and profile save in the mock; JSON round-trips.
- `app/test/fitness_suggest_test.dart` — two recent versus one old measure rule, impedance tie-break, no-data fallback.

## [x] T5: App: Fitness module, hub, Measurements screen and wall tile
**Goal:** The Fitness section is reachable and shows, adds and deletes measurements.
**Acceptance criteria:**
- A 4th nav item opens the hub with a Measurements card (latest weight, trend); the card opens `/fitness/measurements` with a back arrow (R8).
- The Measurements screen shows a trend line for a chosen member, the household list (member, date, weight, composition when present), an empty state, manual add and delete (R8).
- Home shows a wall tile with the signed-in member's latest weight (R9).
- New strings exist in `app_en.arb` and `app_pl.arb` (R11); it works in the mock (R10).
- `cd app && dart format --output=none --set-exit-if-changed . && flutter analyze && flutter test` passes.
**Changes:**
- `app/lib/modules/fitness/fitness_module.dart` — `FitnessModule extends FamilyModule` (id `fitness`, icon `monitor_weight`): `buildScreen` = hub, `subRoutes`, `buildWallTile` with `WallCard`, `seedMock`.
- `app/lib/modules/registry.dart` — add `FitnessModule()` as the last module.
- `app/lib/modules/fitness/fitness_hub.dart` — hub with the Measurements card; cards sit side by side on wide screens.
- `app/lib/modules/fitness/measurements_screen.dart` — member chips, the measurement list with delete, add sheet (weight, date/time, member).
- `app/lib/modules/fitness/trend_chart.dart` — `TrendChart` (custom painter, kg) from the prototype, covered by the screen test.
- `app/lib/l10n/app_en.arb` and `app_pl.arb` — `fitness*` keys for titles, hub, empty state, add sheet, delete, wall tile; regenerate localizations.
- `app/test/fitness_screen_mock_test.dart` — widget test in the mock: nav item present, hub card opens the list, add and delete a measurement, wall tile shows the latest weight.
- Mockup: `em-mockups/issue-34` — reuse `fitness_hub.dart`, `measurements_screen.dart`, `trend_chart.dart` and the wall tile in `fitness_module.dart`; `sample.dart` is sample data only, replace it with providers.

## [x] T6: App: Fitness profile form
**Goal:** A member edits their sex, birth date and height, which enable body composition.
**Acceptance criteria:**
- The form at `/fitness/profile` loads the signed-in member's profile, validates (height 50–250 cm, birth date in the past) and saves via the repository (R2, R8).
- The hub shows a "complete your profile" hint linking to the form while the profile is missing (R3, R8).
- Strings exist in both ARB files (R11).
- `cd app && dart format --output=none --set-exit-if-changed . && flutter analyze && flutter test` passes.
**Changes:**
- `app/lib/modules/fitness/profile_screen.dart` — form with sex selector, birth date picker, height field and Save.
- `app/lib/modules/fitness/fitness_hub.dart` — profile hint card above the sections and an app-bar action opening the profile.
- `app/lib/l10n/app_en.arb` and `app_pl.arb` — profile form and hint keys.
- `app/test/fitness_profile_mock_test.dart` — a valid profile saves, an invalid height is rejected, the hint disappears after saving.
- Mockup: `em-mockups/issue-34` — reuse `profile_screen.dart` and the profile hint card in `fitness_hub.dart`.

## [ ] T7: App: Bluetooth weigh-in
**Goal:** Weigh on the scale from the app, assign each reading to a member or discard it, and save with composition.
**Acceptance criteria:**
- On Android with the real server the Measurements screen offers "Weigh in"; it scans, connects through `flutter_blue_plus`, runs the driver and lists new readings; with the real server on web the entry is hidden (R6, R10).
- Each reading has a member picker preselected by `suggestMember`, Save and Discard; Save stores the measurement with composition from that member's profile when impedance and profile exist; both advance the import cursor (R3, R5, R6, R7).
- In the mock backend the screen is driven by a fake scale emitting sample readings (R10).
- The manifest declares the Bluetooth permissions; permission denied and Bluetooth off have messages; strings in both ARB files (R11).
- `cd app && dart format --output=none --set-exit-if-changed . && flutter analyze && flutter test` passes.
**Changes:**
- `app/pubspec.yaml` — add `flutter_blue_plus`.
- `app/android/app/src/main/AndroidManifest.xml` — `BLUETOOTH_SCAN` (neverForLocation), `BLUETOOTH_CONNECT` and the legacy permissions with `maxSdkVersion` as the plugin documents.
- `app/lib/modules/fitness/scale/scale_session.dart` — `ScaleSession`: scan for all registered drivers' names, connect, `driverFor`, readings filtered by `ImportCursor`, states scanning/connected/error/done.
- `app/lib/modules/fitness/scale/scale_session.dart` — `FlutterBlueGattIo implements GattIo`; `scaleSessionProvider` gives a `FakeScaleSession` whenever the backend is the mock (also on web), null for the real backend on web.
- `app/lib/modules/fitness/weigh_in_screen.dart` — screen at `/fitness/weigh-in`: status header with the scale's `displayName`, reading cards with member dropdown, Save and Discard.
- `app/lib/modules/fitness/measurements_screen.dart` — "Weigh in" action shown only when `scaleSessionProvider` is available.
- `app/lib/l10n/app_en.arb` and `app_pl.arb` — weigh-in keys: states, permissions, save, discard.
- `app/test/fitness_weigh_in_mock_test.dart` — with `FakeScaleSession`: readings appear with the suggested member, Save adds a measurement with composition, Discard drops it, a second session on the same scale skips both.
- Mockup: `em-mockups/issue-34` — reuse `weigh_in_screen.dart` (scale-name status card, reading cards, all variants) and the "Weigh in" action in `measurements_screen.dart`.
