# Tasks

## [ ] T1: Server log ingest and OTLP export
**Goal:** The server accepts `log` messages on the WebSocket and exports them as OTLP logs.
**Acceptance criteria:**
- A `{"t":"log","logs":[{"ts","level","msg","attrs"}]}` message from an authenticated connection reaches the exporter with household and member ids as attributes (R13).
- With `OIKO_OTLP_LOGS_URL` set, records are POSTed as OTLP/HTTP JSON with basic auth, batched; without it they go to slog only (R13).
- Oversized text and surplus records are truncated or dropped; a max-size message (20 records at the caps) stays under the 32 KiB read limit and keeps the socket open (R13).
**Changes:**
- `server/internal/otlp/otlp.go` — new package: `Exporter` (URL, user, password; `Add(Record)`, background flush every 5 s or 100 records, bounded queue, `Close`), `Record`; OTLP JSON logs payload, resource `service.name=oikoboard`.
- `server/internal/otlp/otlp_test.go` — httptest collector: payload shape, basic auth header, batching, overflow drop.
- `server/internal/realtime/hub.go` — `LogSink` interface (`Log(actor core.Actor, recs []LogRecord)`); `NewHub` takes it (nil = slog only).
- `server/internal/realtime/conn.go` — `clientMsg` gets `Logs`; new `case "log"` in the read loop applies the caps (20 records, `msg` 512 B, `attrs` 512 B) and forwards to the sink.
- `server/cmd/oikoboard/main.go` — read the three `OIKO_OTLP_*` vars, build the exporter, close it on shutdown; document the vars in the header comment.
- `server/internal/app/app.go` — wire the sink into `realtime.NewHub`.
- `server/internal/app/logs_test.go` — WebSocket test: log message arrives at a fake sink with actor ids; malformed messages and a max-size message (20 records at the caps) keep the socket open; extra records are dropped.
- `docs/backend-realtime.md` — add the `log` message to the protocol; `README.md` env var list if it has one.

## [ ] T2: App log pipeline over the WebSocket
**Goal:** The app has a generic structured logger that forwards to the server.
**Acceptance criteria:**
- `AppLog.info/debug/warn(source, msg, attrs)` entries are sent as `log` messages when connected, kept in a 500-entry ring buffer otherwise, oldest dropped first (R12).
- On the mock backend entries only go to the ring buffer and `debugPrint` (R12, R14).
**Changes:**
- `app/lib/core/app_log.dart` — `LogEntry`, `AppLog` (ring buffer, `sink` callback, `flush()`), `appLogProvider`.
- `app/lib/core/api/sync_client.dart` — `sendLogs(List<Map>)` (at most 20 entries per call) using `_send`, no-op while disconnected; send buffered entries on each `status` up.
- `app/lib/core/data.dart` — `appLogProvider` override wiring: in API mode batches go to `syncClientProvider.sendLogs`.
- `app/test/app_log_test.dart` — ring-buffer bound, flush on reconnect, batches of at most 20.
- `app/test/sync_client_test.dart` — an `error` frame without `sub` (older server's reply to `log`) is ignored and the connection stays up.

## [ ] T3: Driver protocol fixes and activity signals
**Goal:** `MiScale2Driver` parses what the scale really sends and reports activity.
**Acceptance criteria:**
- Records split across notifications, 13/26-byte live frames, 16-bit and 8-bit count replies and echoed magic frames are handled as described (R4, R5).
- Variant detection, `unsupported` error, best-effort time write, per-variant write order, alternate-service fallback and user-id parameter (R6, R7).
- Out-of-range dates are dropped by shared code (R8); `flush()` emits the held record (R3).
- Every write, notification, detected variant and count goes to the log (R12).
**Changes:**
- `app/lib/modules/fitness/scale/scale_driver.dart` — add `id`, `Stream<ScaleSignal> signals` (`activity`, `historyComplete`), `flush()`, `UnsupportedScaleError`; drop `onlyLast`.
- `app/lib/modules/fitness/scale/scale_driver.dart` — `GattIo` gets `serviceOf(uuid)`; `onConnected` takes a `ScaleLog`.
- `app/lib/modules/fitness/scale/scale_log.dart` — `ScaleLog` thin wrapper over `AppLog` with source `scale`, plus `hex()` helper.
- `app/lib/modules/fitness/scale/mi_scale2.dart` — one reassembly buffer, marker-aware count parsing, variant by history-characteristic service, per-variant write order.
- `app/lib/modules/fitness/scale/mi_scale2.dart` — alternate-service retry, `userId` constructor parameter, emits signals.
- `app/lib/modules/fitness/scale/scale_session.dart` — `FlutterBlueGattIo.serviceOf`, `isPlausibleTime` check applied in `_BaseSession.offer` (shared place).
- `app/lib/modules/fitness/scale/scale_session.dart` — `BleScaleSession._connect` call site: pass the `ScaleLog` to `onConnected` and stop passing `onlyLast`, so T3 builds on its own.
- `app/test/fitness_mi_scale_test.dart` — fake `GattIo` byte sequences: delayed history, fragmented frames, magic echo, v1 order, weight-only `MI SCALE2`, no service, failing time write.
- `app/test/fitness_mi_scale_test.dart` — update existing tests for the dropped `onlyLast`.

## [ ] T4: Session timing, waiting state and first import
**Goal:** The session waits for the scale and imports everything on first connect.
**Acceptance criteria:**
- Silence timer resets on any driver signal, expires after 60 s; `historyComplete` + 2 s quiet finishes; user Done and disconnect finish; finish calls `flush()` (R1, R2, R3).
- States `waiting` (connected, nothing yet) and error `unsupported` exist and the screen shows them with a Done button (R2, R6).
- An unknown scale is asked for all records; its readings all land in the pending list; "Discard all" resolves each of them (R11).
- Each pending reading picks its member with the shared member `ChoiceChip` + `MemberAvatar` row, no dropdown (R15).
- The end reason (idle / disconnect / user / history) is logged (R12).
**Changes:**
- `app/lib/modules/fitness/scale/scale_session.dart` — `ScalePhase.waiting`, `ScaleError.unsupported`, `finishNow()` on `ScaleSession`; silence/quiet timers use plain `Timer` so `fakeAsync` drives them.
- `app/lib/modules/fitness/scale/scale_session.dart` — `FakeScaleSession` emits the waiting state and many samples; timer logic sits in a BLE-free class the test can drive.
- `app/lib/modules/fitness/weigh_in_screen.dart` — waiting text and Done button in `_StatusCard`, unsupported error text, "Discard all" button calling `_resolve` for all pending.
- `app/lib/modules/fitness/weigh_in_screen.dart` — replace the "Who" dropdown with a `Wrap` of `ChoiceChip(avatar: MemberAvatar)` as in `measurements_screen.dart`.
- Mockup: `centurion-mockups/issue-84` — reuse `_StatusCard` (`onDone`, waiting/unsupported), Discard all `TextButton`, the "Who" `ChoiceChip` row, arb keys.
- `app/lib/l10n/app_en.arb`, `app/lib/l10n/app_pl.arb` — keys `fitnessWeighInWaiting`, `fitnessWeighInDoneButton`, `fitnessWeighInUnsupported`, `fitnessWeighInDiscardAll`.
- `app/test/scale_session_test.dart` — `fakeAsync` with a fake driver: reset on activity, 60 s expiry, quiet-period finish, flush on finish; session logic factored so it runs without the BLE plugin.
- `app/test/fitness_weigh_in_mock_test.dart` — waiting state, Done, Discard all on the mock backend.

## [ ] T5: Remembered scale
**Goal:** The app remembers the paired scale and connects to it directly.
**Acceptance criteria:**
- After the first successful session the scale is saved; the next session connects by remote id with `autoConnect`, scanning (filtered to that id) only as fallback (R9).
- Several matching devices with nothing saved: the user picks one; the choice is saved (R10).
- "Forget scale" clears it and returns to scanning (R10).
**Changes:**
- `app/lib/modules/fitness/scale/saved_scale.dart` — `SavedScale` (remoteId, driverId, name) stored as JSON in `DevicePrefs` key `fitness.scale.paired`; `load/save/clear`.
- `app/lib/modules/fitness/scale/registry.dart` — `driverById(String)`; `driverFor` stays the only name matcher.
- `app/lib/modules/fitness/scale/scale_session.dart` — saved-scale connect path, filtered scan fallback, `ScalePhase.choosing` with `candidates`, `choose(candidate)`, `forget()`; `FakeScaleSession` supports them.
- `app/lib/modules/fitness/weigh_in_screen.dart` — candidate list card and the "Forget scale" overflow action.
- Mockup: `centurion-mockups/issue-84` — reuse the candidates `Card` of `ListTile`s, the `PopupMenuButton` in `FitnessHeader.actions`, and the `choose`/`forget` session API.
- `app/lib/l10n/app_en.arb`, `app/lib/l10n/app_pl.arb` — keys `fitnessWeighInPick`, `fitnessWeighInForget`.
- `app/test/saved_scale_test.dart` — round-trip, forget; `app/test/fitness_weigh_in_mock_test.dart` — pick and forget flows on the mock.

## [ ] T6: Docs
**Goal:** Architecture docs describe the scale session and the log path.
**Acceptance criteria:**
- `docs/architecture.md` states: scale layer (driver/session split, signals), remembered scale, and logs → WebSocket → OTLP, with the env vars (R13).
**Changes:**
- `docs/architecture.md` — short paragraph for each of the three points above; no changelog text.
