# Live HR on firmware-locked WHOOP bands — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user opt in to live heart rate from a firmware-locked WHOOP band, read off the standard BLE Heart Rate Service by the existing engine, with the lock copy corrected to match.

**Architecture:** The band's framed live-HR opcode stream is locked, but it still serves the standard SIG Heart Rate Service (0x180D / `2A37`). When the band is `isDataLockedFirmware`, connected, exposes 0x180D in its discovered GATT, and the user has opted in, the existing `BleEngine` subscribes `2A37` on the session it already owns and writes `state.liveHr` / `state.liveHrAt` — the same fields normal live HR uses, keeping a single live-HR path. Nothing is persisted; HR only, no HRV. The existing device tile renders `state.liveHr`, so the UI work is the opt-in affordance and corrected copy.

**Tech Stack:** Flutter/Dart, `flutter_blue_plus`, `openstrap_protocol` (carries `parseHeartRateMeasurement`), Flutter gen-l10n (`.arb`).

**Spec:** `docs/superpowers/specs/2026-11-19-whoop-firmware-lock-fallback-design.md` (rev 2)

## Global Constraints

- Repo split (CONTRIBUTING): edge only. No wire decode in edge (HR parser stays in `openstrap_protocol`); no metric math in edge (no HRV).
- Single live-HR path (AGENTS invariant 8): write only `state.liveHr`; the engine is the only writer. No second subscriber/stream/field.
- Never fabricate a metric (AGENTS invariant 3): show `-` when HR is stale or absent; never a substituted value.
- Live streams RAM-only (AGENTS invariant 14): persist nothing.
- Clear any "opted-in / view-open" flag in `finally` (pattern 4.3).
- Consent: opt-in is a per-session manual action, never a persisted auto-arming toggle.
- Gate on `isDataLockedFirmware(firmware)` + connected + 0x180D-in-discovered-GATT, NOT on `BandCondition.firmwareLocked`.
- Firmware is stored per install, not per band (`issue_report.dart:265`): key the gate off the connected band's own discovered service + firmware.
- `standardHrFallback` (existing symbol) means framed-HR-without-IMU, NOT 0x180D — do not reuse that name.
- Commits MUST NOT include a `Co-Authored-By` trailer (edge CONTRIBUTING forbids it).
- Locales to keep in sync: `de, en, es, fr, hi, ru, th, zh` (8 `app_*.arb`).

## Review Focus

- Out of range mid-view: `liveHr` stops updating → the view must show `-` after a staleness window, not a frozen last BPM. (Task 4)
- Engine bounces the link on a locked band (stuck-strap / defensive SET_CLOCK): the `2A37` subscription is dropped → must re-subscribe when the session returns, `-` meanwhile. (Task 4)
- Off-wrist: flags `0x10` has no sensor-contact bit, so `2A37` may send 0/garbage BPM → present `-` for a non-physiological reading, never a fabricated number. (Task 4)
- Broadcast prerequisite off: if the band isn't broadcasting, the view shows `-` forever → the opt-in/empty state must read as "no signal", not an app error, and must not imply success. (Task 3)
- Second band: a different connected band without 0x180D must not get the opt-in, even if the per-install firmware string says `50.43.x`. (Task 2)

---

### Task 1: Upstream proposal (no code)

CONTRIBUTING says open an issue first when unsure. This task gates the PR.

- [ ] **Step 1:** Comment on edge#673 with the raw capture and method: band on 50.43.2.0 serves `180D`/`2A37` Notify with no WHOOP app; raw `10 51 E502 EC02` = flags `0x10` (R-R present), 81 bpm, R-R 723.63/730.47 ms; captured via nRF Connect.
- [ ] **Step 2:** Open an issue proposing: opt-in live HR on locked bands via an engine-owned `2A37` subscription feeding `state.liveHr`, HR-only, nothing persisted, plus the lock-copy correction. Link the capture and this design. Ask maintainers to confirm before the PR.
- [ ] **Step 3:** Proceed to Task 2 only after a maintainer signals the approach is wanted (or after a reasonable wait, owner's call).

### Task 2: Standard-HR-on-lock gate (pure policy)

**Files:**
- Modify: `lib/ble/ble_state.dart` (add the predicate near `isDataLockedFirmware`)
- Test: `test/ble_state_test.dart` (or the existing ble_state policy test file)

**Interfaces:**
- Consumes: `isDataLockedFirmware(String?)` (existing).
- Produces: `bool shouldOfferLockedLiveHr({required String? firmware, required bool connected, required bool hasStandardHrService, required bool optedIn})` — true iff `isDataLockedFirmware(firmware) && connected && hasStandardHrService && optedIn`.

- [ ] **Step 1: Write the failing test** — cases: locked+connected+180D+optedIn → true; each of the four false individually → false; non-locked firmware with 180D+optedIn → false; locked+180D+optedIn but not connected → false.
- [ ] **Step 2: Run it, verify it fails** (`shouldOfferLockedLiveHr` undefined).
- [ ] **Step 3: Implement** `shouldOfferLockedLiveHr(...)` in `ble_state.dart` as the single boolean conjunction above.
- [ ] **Step 4: Run it, verify it passes.**
- [ ] **Step 5: Commit** (no `Co-Authored-By`).

### Task 3: Opt-in affordance + per-session flag

**Files:**
- Modify: `lib/state/app_state.dart` — add a per-session opt-in flag + retain/release, mirroring the existing `retainLiveHrView`/`releaseLiveHrView` pair.
- Modify: `lib/ui2/profile/devices.dart` — the firmwareLocked card gets the action.
- Test: a widget test under `test/` asserting the gate wiring (opt-in toggles the flag; leaving clears it).

**Interfaces:**
- Produces: `AppState.lockedLiveHrOptIn` (bool, default false), `retainLockedLiveHr()` / `releaseLockedLiveHr()` (set/clear it, notify). The engine reads `lockedLiveHrOptIn` as the `optedIn` input to `shouldOfferLockedLiveHr` and as `visibleLiveHrView`'s analogue for the lock path.
- Consumes: `localizedBandStatus`, `BandStatus` (existing, `devices.dart:76-77`); the existing `$liveHr bpm` tile render (`devices.dart:2760`).

- [ ] **Step 1: Write the failing test** — mounting the firmwareLocked card and tapping "Show live heart rate" sets `lockedLiveHrOptIn` true; disposing/leaving clears it (assert cleared even on an exception path — `finally`).
- [ ] **Step 2: Run it, verify it fails.**
- [ ] **Step 3: Implement** the flag + `retainLockedLiveHr`/`releaseLockedLiveHr` in `AppState`; add an opt-in action on the firmwareLocked card that calls them, and an empty state reading "no signal" (not an error) when opted in but `liveHr` is null/stale. Clear in `finally` on dispose.
- [ ] **Step 4: Run it, verify it passes.**
- [ ] **Step 5: Commit.**

### Task 4: Engine subscribes `2A37` under the gate, writes `state.liveHr`

**Files:**
- Modify: `lib/ble/ble_engine.dart` — in the connected-session path that already discovers services (`_discoverBand`, ~4004-4007) and writes `state.liveHr` (~6342-6343).
- Test: `test/` — a staleness unit for the view-facing freshness check; engine wiring itself follows the repo's existing notify-subscription idiom (integration, per repo norm).

**Interfaces:**
- Consumes: `shouldOfferLockedLiveHr(...)` (Task 2), `AppState.lockedLiveHrOptIn` (Task 3), `openstrap_protocol.parseHeartRateMeasurement` (returns HR bpm + R-R; use HR only).
- Produces: writes to existing `state.liveHr` (int?) and `state.liveHrAt` (int ms). No new field.

- [ ] **Step 1: Write the failing test** — a pure freshness helper `bool isLiveHrFresh(int? atMs, int nowMs, {int windowMs})`: fresh within window → true; stale/ null → false. (The view uses this to show `-`.) Assert a 0-bpm / non-physiological reading maps to "show `-`" (helper returns the value unchanged but the view's guard treats <1 bpm as absent — pin that guard here).
- [ ] **Step 2: Run it, verify it fails.**
- [ ] **Step 3: Implement:** when `shouldOfferLockedLiveHr(firmware, connected, hasStandardHrService, lockedLiveHrOptIn)` holds, subscribe the discovered `2A37` characteristic on the current session (following the engine's existing notify pattern), parse with `parseHeartRateMeasurement`, and set `state.liveHr`/`state.liveHrAt` from the HR field (ignore R-R). Stop/clear the subscription and null `liveHr` when the gate drops or the view releases (`finally`). On a link bounce, re-subscribe when the session returns. Add `isLiveHrFresh` + the <1-bpm absent guard; wire the lock live view to show `-` when not fresh.
- [ ] **Step 4: Run it, verify it passes.**
- [ ] **Step 5: Commit.**

### Task 5: Correct the lock copy in all locales

**Files:**
- Modify: `lib/l10n/app_en.arb` (source) — `bandStatusFirmwareLockedReason`, and add the opt-in action string + live-view empty-state string. Keep each `@`-metadata block.
- Modify: `lib/l10n/app_{de,es,fr,hi,ru,th,zh}.arb` — translate the same keys.
- Modify: `lib/ble/band_status_l10n.dart` only if a new key needs mapping.

**Interfaces:**
- Produces: corrected English `bandStatusFirmwareLockedReason` (exact text below), new keys `lockedLiveHrAction` and `lockedLiveHrNoSignal`.

- [ ] **Step 1:** Set English `bandStatusFirmwareLockedReason` to exactly:
  "This band runs WHOOP firmware 50.43, which connects and answers the app but sends no stored recordings — no history, sleep, or recovery — until a WHOOP-signed membership token is on it. OpenStrap cannot issue that token. Live heart rate is still available: tap below to show it. Everything already saved here is safe."
- [ ] **Step 2:** Add `lockedLiveHrAction` = "Show live heart rate" and `lockedLiveHrNoSignal` = "No live signal — keep the band on and in range." with `@`-metadata.
- [ ] **Step 3:** Translate all three keys into the 7 other locales following the repo's l10n convention.
- [ ] **Step 4:** Run the l10n codegen + `flutter analyze`; verify no missing-translation errors.
- [ ] **Step 5: Commit.**

---

## Self-review notes

- Spec coverage: gate (T2), opt-in/consent + copy-false fix (T3/T5), engine 2A37→liveHr (T4), process/ask-first (T1), all locales (T5). A2/HRV/B are out of scope by the spec.
- Review Focus mapped: staleness + re-subscribe + off-wrist → T4; broadcast-off empty state → T3; per-band gating → T2.
- Open dependency (broadcast prerequisite) is a copy/empty-state concern (T3/T5), not a code blocker; if hardware shows a WHOOP-app toggle is required, `lockedLiveHrNoSignal` copy should name it — flagged for the builder.
