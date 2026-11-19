// The engine's standard 0x180D (2A37) live-HR writer, exercised at the one
// seam the radio otherwise sits in front of: [BleEngine.debugOnStandardHrValue]
// feeds a real Heart Rate Measurement notification through the same code a live
// subscription would, and we assert what it writes to the single live-HR state.
//
// The capture bytes are from real hardware: flags 0x10 (RR present, uint8 HR),
// HR 0x51 = 81 bpm, then two RR intervals. We consume HR only; R-R is ignored.
//
// The subscription LIFECYCLE (setNotifyValue / onValueReceived / cancel on a
// link bounce) is not unit-tested here: flutter_blue_plus has no simulator path
// and this repo has no FlutterBluePlus harness, so — as in ble_hrs.dart and
// hrs_link_test.dart — the notify wiring is left to integration. Its gating is
// covered by the pure `shouldOfferLockedLiveHr` unit elsewhere.

import 'package:flutter_test/flutter_test.dart';

import 'package:openstrap_edge/ble/ble_engine.dart';

void main() {
  // flags 0x10 → RR present, uint8 HR; 0x51 = 81 bpm; 0x02E5, 0x02EC = R-R.
  const capture = [0x10, 0x51, 0xE5, 0x02, 0xEC, 0x02];

  BleEngine makeEngine(List<void Function()> onStateCalls) => BleEngine(
        onRecord: (_, _) async {},
        onState: (_) => onStateCalls.add(() {}),
        log: (_) {},
      );

  test('a 2A37 capture writes liveHr (81 bpm) and stamps liveHrAt', () {
    final calls = <void Function()>[];
    final engine = makeEngine(calls);
    expect(engine.state.liveHr, isNull);

    engine.debugOnStandardHrValue(capture);

    expect(engine.state.liveHr, 81);
    expect(engine.state.liveHrAt, isNotNull);
    expect(calls, isNotEmpty, reason: 'onState must fire on a usable beat');
  });

  test('a 0-bpm reading does not write a 0 and keeps the last value', () {
    final calls = <void Function()>[];
    final engine = makeEngine(calls);

    // A fresh engine: a 0-bpm notification (flags 0, HR byte 0) must not land a
    // real-looking zero in the HR series.
    engine.debugOnStandardHrValue([0x00, 0x00]);
    expect(engine.state.liveHr, isNull);

    // With a real beat already present, a later 0-bpm/absent reading must leave
    // it alone (it goes stale on its own; the view self-expires to no-signal).
    engine.debugOnStandardHrValue(capture);
    expect(engine.state.liveHr, 81);
    engine.debugOnStandardHrValue([0x00, 0x00]);
    expect(engine.state.liveHr, 81);
  });

  test('a malformed notification is dropped, not patched', () {
    final engine = makeEngine([]);
    // Too short to be a 2A37 value → parser returns null → no write.
    engine.debugOnStandardHrValue([0x10]);
    expect(engine.state.liveHr, isNull);
  });
}
