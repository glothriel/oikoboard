# Fix the Mi scale weigh-in and collect its BLE logs

Source: issue #84.

## Goal
The weigh-in screen reliably downloads the stored measurements from the Xiaomi Mi scale (today it finds the scale but receives nothing). The BLE session logs reach an OpenTelemetry backend through the oikoboard server, so failures can be diagnosed without the device in hand.

## Requirements
- R1: The session does not end while the scale is still talking: any driver activity (notification) resets the silence timer; the window is 60 s of silence.
- R2: While connected and waiting the screen shows "waiting for the scale…" with a Done button that finishes the session; the session also finishes on a disconnect or on end-of-history plus a short quiet period (2 s).
- R3: On finish the driver flushes the record it holds, so a reading is never lost to a torn-down session.
- R4: One reassembly buffer serves both Mi scale variants: 13/26-byte frames are live frames, everything else is accumulated and parsed as records, so records split across notifications survive.
- R5: The count response is parsed with its echoed marker (8-bit and 16-bit counts); unknown echoes (e.g. of the magic write) are ignored and never cancel the all-records fallback; the announced count is logged.
- R6: Variant detection uses the service holding the history characteristic (service presence as fallback); a scale with neither service gives `ScaleError.unsupported`, shown to the user.
- R7: The time write is best effort (primary service, then the other, then continue); the v1 variant writes the "enable history" magic before subscribing; the fallback retries on the alternate service; the user id in requests and acks is one driver parameter.
- R8: Readings dated more than 20 years from now are dropped, in the shared layer, not per driver.
- R9: The paired scale (remote id, driver id, name) is saved on the device; a later session connects directly to it (autoConnect), falling back to a scan filtered to that remote id.
- R10: With no saved scale and several matching devices in range, the user picks one; a "Forget scale" action clears the saved one.
- R11: First connect to a never-seen scale requests all stored records; all of them appear in the pending list (save/discard each), plus one "Discard all" action.
- R12: The app logs the BLE session (scan hit, services, variant, every write, every notification as hex, announced count, why the session ended) and sends it over the existing WebSocket as `log` messages; offline or on mock it is kept in a small ring buffer and dropped when full.
- R13: The server exports received logs as OTLP/HTTP JSON log records, with basic auth, configured by `OIKO_OTLP_LOGS_URL`, `OIKO_OTLP_USER`, `OIKO_OTLP_PASSWORD`; without the URL logs are only written to slog. Records carry household and member ids, never tokens.
- R15: The "Who" choice on a pending reading uses the same member `ChoiceChip`s with `MemberAvatar` as the other fitness screens, not a dropdown.
- R14: The mock backend's `FakeScaleSession` still works and covers the new states (waiting, pick, discard all).

## UI
- Weigh-in screen (`weigh_in_screen.dart`): new "waiting for the scale…" status with a Done button; "unsupported scale" error text; a scale picker list when several scales are found; a "Forget scale" menu item; a "Discard all" button above the pending readings; the pending reading's "Who" dropdown becomes the app-wide member picker (`ChoiceChip` with `MemberAvatar`, as in `measurements_screen.dart`).
- Mockup prototype: branch `centurion-mockups/issue-84`.

## Out of scope
- Other scale models, broadcast (advertisement-only) scales.
- An in-app log viewer or share sheet (replaced by OTel export).
- A bulk "save all" action.
- Logs from anything but the scale session (the transport is generic, nothing else uses it).

## Decisions and why
- Hand-written OTLP/HTTP JSON exporter on `net/http` instead of the OpenTelemetry Go SDK: the log SDK is still unstable and pulls many dependencies for one POST; the OTLP JSON shape is small and stable. Batching: flush every 5 s or 100 records (exporter side, independent of the per-message cap), bounded queue, drops on overflow.
- Log transport is a new `{"t":"log","logs":[…]}` client message on the existing socket (no new endpoint), as the author asked; the server never replies.
- Limits are chosen to fit coder/websocket's default 32 KiB read limit (a larger message would close the socket): at most 20 records per `log` message (the app batches by 20), each record's `msg` cut to 512 bytes and its `attrs` to 512 bytes serialized (about 1.2 KiB a record, under 25 KiB a message); extra records are dropped, so a misbehaving client cannot flood the collector.
- The driver gets a `Stream<ScaleSignal>` (`activity`, `historyComplete`) next to `readings`, so the session never guesses from emitted readings.
- `onlyLast` is removed from `ScaleDriver.onConnected`: the cursor already filters duplicates, and first connect now requests everything.
- The saved scale lives in `DevicePrefs` under one key as JSON, next to the per-`remoteId` import cursor (which stays as is).
- "Who" picker: the review asked for the shared look, so the dropdown is replaced by the `Wrap` of member `ChoiceChip`s used in `measurements_screen.dart` (no new widget).
- The 60 s silence window and 2 s quiet period are constants in `scale_session.dart`; not configurable.
- Fixes ship in the order of the issue's spike (logging first) so one real session log confirms the diagnosis.

## Backward compatibility
Additive. An older server answers the new `log` client message with an `error` frame without `sub`, which `SyncClient._onMessage` already ignores (no matching subscription); a test pins this. The new `OIKO_OTLP_*` env vars are optional; no schema change; the saved-scale pref key is new and old installs simply have none.
