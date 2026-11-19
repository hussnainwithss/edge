# Design: live-HR on firmware-locked WHOOP bands (engine-owned)

Repo: `OpenStrap/edge` (upstream PR). Date: 2026-11-19. Rev 2 (post Fable review).

## Intent and why

WHOOP 5.0 / MG on firmware `50.43.x` connect over BLE and answer commands but
withhold all history and live data until a WHOOP-signed membership token is on
the band (edge#673). OpenStrap cannot issue or replay that token, and will not
forge one. History, sleep, recovery stay out of reach without WHOOP.

But the locked band still streams the standard Bluetooth Heart Rate Service
(0x180D) — live HR and R-R — with no token. Edge already detects the lock
(`isDataLockedFirmware`, `BandCondition.firmwareLocked`) and shows copy telling
the user there is nothing the app can do and no live heart rate. That copy is now
false: the band DOES stream live HR.

The fix (A1): when a locked band is connected and exposes 0x180D, let the
**existing BLE engine** subscribe to its `2A37` on the session it already owns
and feed the app's existing live-HR state, behind an opt-in. Correct the lock
copy. Nothing persisted, HR only.

This restores no history/sleep/recovery. The ceiling is real; the UI says so.

## What changed from rev 1 (Fable review, code-cited)

- **No side-car connection.** One app = one link. A second connection fights the
  engine's session (teardown kills it; the engine bounces the link on locked
  bands). Use the engine's own session + its existing `state.liveHr` /
  `visibleLiveHrView` / `desiredLiveStreams` machinery. A parallel live-HR path
  violates AGENTS invariant 8.
- **Gate is not `firmwareLocked`.** That condition needs `strapNeedsReboot ||
  syncClockLost` (≥10 min to trip) and is outranked by other states — flickery
  and late. Gate on `isDataLockedFirmware(firmware)` + connected + 0x180D present
  in the discovered GATT.
- **No HRV in A1.** Spot RMSSD is a new metric (analytics repo), and flags `0x10`
  carries no sensor-contact bit, so off-wrist garbage can't be rejected →
  invariant 3 risk. HR only.
- **B dropped.** The issue report already carries firmware + both lock flags +
  `standardHrFallback` and dumps the GATT every connect. A lock-state enum
  re-encodes existing fields. Instead: post the raw capture + method to #673.
- **Doc over-claims removed** (see Constraints): the 2A37 parser is in
  `openstrap_protocol`, not edge; the HRS adapter is EXPERIMENTAL / "NOTHING HERE
  HAS MET HARDWARE"; the lock copy must be rewritten, not just extended.

## Goals

- A user with a connected, 0x180D-exposing locked band can opt in to a **live
  heart-rate view**, fed by the engine's existing live-HR state. HR only,
  in-range only, nothing persisted.
- Reuse the engine's session and `state.liveHr`; call the existing
  `openstrap_protocol` HR parser (orchestration). No new connection, no new
  decode, no new dependency, no metric math in edge.
- Correct the now-false lock copy in every locale.

## Non-goals

- History, sleep, recovery, strain for locked bands.
- Any token capture/replay/forgery; any logging of the handshake/token bytes
  (`0x9b`-`0x9e`).
- HRV / any metric computation in edge (analytics repo owns metrics).
- A second/parallel BLE connection or live-HR path.
- A diagnostics PR (old B). The finding goes on #673 instead.
- Stored HRV trends (A2 — separate design, deferred).

## Anti-goals (failure even if it "works")

- Streaming without the user choosing it (breaks consent + the lock promise).
- Any surface implying recovery of history or WHOOP's full metrics.
- Fabricating a metric when R-R / contact is absent (invariant 3).

## Constraints

- **Repo split (CONTRIBUTING).** Edge only: flows/UI/live-state. Wire decode →
  protocol (the HR parser already lives there, `parseHeartRateMeasurement`;
  `test/hrs_link_test.dart` says edge deliberately does not pin the decode).
  Metric math → analytics.
- **Single live-HR path (AGENTS invariant 8).** Feed `state.liveHr` through the
  engine's existing owner/stream, not a second subscriber.
- **No fabricated metric (invariant 3).** HR only; show "-" when stale/absent.
- **Live streams stay RAM-only (invariant 14).** A1 persists nothing — satisfied.
- **`finally`-clear (pattern 4.3).** Any "live view open" flag clears in
  `finally`.
- **ponytail.** Reuse `state.liveHr`, the protocol parser, the discovered-GATT
  from `_discoverBand`. No new helper where one exists.
- **CONTRIBUTING forbids `Co-Authored-By` trailers** — conflicts with this
  session's default commit footer. Edge commits MUST omit it.
- `standardHrFallback` in the code is framed-HR-without-IMU, NOT 0x180D — do not
  reuse that name for this.

## Gating facts

CONFIRMED on hardware 2026-11-19 (owner's band "PONYO'S WHOOP 5", firmware
50.43.2.0, via nRF Connect, no WHOOP app session): standard HR service `180D`
PRIMARY with `2A37` Notify; raw notification `10 51 E502 EC02` = flags `0x10`
(R-R present, 8-bit HR, no sensor-contact bit), HR 81 bpm, R-R 723.63/730.47 ms.
So a locked band streams live HR + R-R with no token.

OPEN (must resolve during build or with the owner): does standard 0x180D
broadcast require a one-time enable in the WHOOP app, or a prior bond? The
capture proves it works on THIS band now; it does not prove a band freshly off
the WHOOP app broadcasts unprompted. If a prerequisite exists, the opt-in copy
must state it, and A1's "token-free and self-sufficient" claim weakens to
"token-free once broadcast is on."

## Approaches considered

- **A1 (chosen): engine-owned live-HR on lock.** Engine subscribes 2A37 on its
  existing session when locked + 0x180D present, feeds `state.liveHr`, opt-in
  view. Small, honest, single live-HR path. No persistence.
- **Side-car 0x180D reader (rejected).** Rev 1's design. Fights the engine's
  single link; likely rejected upstream.
- **B diagnostics (dropped).** Redundant with existing report fields; the finding
  belongs on #673.
- **A2 stored HRV (deferred).** Needs a substrate feed + band identity + derive
  routing (db.dart / derivation_engine.dart hotspots); does not reproduce
  recovery (overnight RMSSD + staging, locked + analytics). Separate design once
  A1 is proven.

## Process (CONTRIBUTING: open an issue first when unsure)

1. Post the raw `10 51 E502 EC02` capture + nRF method as a comment on edge#673
   (helps the community; replaces old B).
2. Open an issue proposing engine-owned opt-in live-HR on locked bands, link the
   capture, confirm the maintainers want it before the PR.
3. Then the A1 PR.

## Decided design (A1)

Anchors (verify line numbers against source; symbols are stable):
- `lib/ble/ble_engine.dart` — `_discoverBand` discovers services (~4004-4007, the
  GATT table logged every connect); `state.liveHr` (~6342); link-bounce on locked
  bands (stuck-strap / defensive SET_CLOCK, ~7960-7975).
- `lib/ble/ble_state.dart` — `isDataLockedFirmware(firmware)` (prefix `50.43.`,
  ~271); `visibleLiveHrView` owner + `desiredLiveStreams` (~2204-2222); the
  `firmwareLocked` status + reason copy (~379-388).
- `lib/ble/band_status_l10n.dart` — `firmwareLocked` copy mapping.
- `lib/ui2/profile/devices.dart` — the firmwareLocked status card.
- `openstrap_protocol` — `parseHeartRateMeasurement` (the 2A37 decoder; a dep,
  not edge code).

Changes:
1. **Gate (pure policy in `ble_state.dart`, with a test):** offer live-HR when
   `isDataLockedFirmware(firmware)` AND the link is connected AND 0x180D is in the
   discovered GATT. Not `BandCondition.firmwareLocked`.
2. **Engine hook:** when the gate holds AND `visibleLiveHrView` is owned, the
   engine subscribes to `2A37` on its existing session, parses via the protocol
   HR parser, and feeds `state.liveHr` — the same owner/stream normal live HR
   uses. R-R is not consumed (no HRV). Subscription stops when the view closes
   (flag cleared in `finally`) and tolerates the engine bouncing the link
   (re-subscribes when the session returns).
3. **UI:** the firmwareLocked card gets an opt-in action "Show live heart rate."
   Copy: live-only, in-range-only, explicitly not history/sleep/recovery. The
   view binds to `state.liveHr` and shows "-" after a staleness window.
   Per-session; no persistent toggle.
4. **Copy fix:** rewrite the `firmwareLocked` reason (currently "no recordings or
   live heart rate") to reflect live HR is available on opt-in, across EVERY
   `app_*.arb` (count the files; ~8-10), plus the base string + the l10n card
   mapping. This is editing existing strings, not only adding new ones.
5. **Tests:** the gate policy test; a staleness/"-" logic test. NO 2A37 parser
   fixture test in edge (decode isn't pinned here — that belongs in the protocol
   repo).

## Left to the builder

1. Exact engine hook point for the lock 2A37 subscription vs the existing
   `desiredLiveStreams` wiring (reuse that path if it already expresses "subscribe
   2A37 while a view is visible").
2. Staleness window before the view shows "-".
3. Behaviour across an engine link-bounce mid-view (re-subscribe + "-" meanwhile).
4. Android vs iOS parity — the engine owns the link and CoreBluetooth restore, so
   this should follow existing behaviour; verify.
5. Live-view placement/affordance off the firmwareLocked card.
6. Enumerate the exact `app_*.arb` locale set to edit.

## Open dependencies

- Live-HR-on-lock gating facts CONFIRMED (HR + R-R over 0x180D while locked).
- Broadcast-prerequisite OPEN (WHOOP-app toggle / prior bond?) — see Gating facts.
- Maintainer buy-in via the #673 issue before the PR.
