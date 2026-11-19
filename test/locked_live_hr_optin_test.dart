// Opt-in live heart rate on a firmware-locked band's device page: the action
// shows only when the band is locked, connected and exposes the standard
// 0x180D service; tapping it is a per-session flag that the page clears when
// it goes away (never persisted).
//
// No database is opened, as in live_hr_view_owner_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_edge/l10n/app_localizations.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/ui2/profile/devices.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BleEngine.resetBandClaimForTest();
  });
  tearDown(BleEngine.resetBandClaimForTest);

  const band = HealthSource(
    name: 'WHOOP',
    kind: 'band',
    tier: null,
    icon: Icons.watch,
    isBand: true,
  );

  Widget host(AppState app, Widget child) => MaterialApp(
        theme: buildTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<AppState>.value(
          value: app,
          child: Scaffold(body: child),
        ),
      );

  AppState lockedApp() {
    final app = AppState.forTesting();
    app.device.firmware = '50.43.2.0';
    app.device.connection = 'connected';
    app.device.syncClockLost = true;
    app.setLockedStandardHrAvailable(true);
    return app;
  }

  Future<void> pumpCard(WidgetTester t, AppState app) async {
    t.view.physicalSize = const Size(390 * 3, 2400 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(app, const DeviceDetail(band)));
    await t.pump();
  }

  testWidgets('offers the action and tapping it opts in', (t) async {
    final app = lockedApp();
    addTearDown(app.dispose);
    await pumpCard(t, app);
    expect(app.engine.bandStatus.condition.name, 'firmwareLocked');
    expect(app.lockedLiveHrOptIn, isFalse);
    expect(find.text('Show live heart rate'), findsOneWidget);
    await t.tap(find.text('Show live heart rate'));
    await t.pump();
    expect(app.lockedLiveHrOptIn, isTrue);
  });

  testWidgets('no action without the standard HR service', (t) async {
    final app = lockedApp()..setLockedStandardHrAvailable(false);
    addTearDown(app.dispose);
    await pumpCard(t, app);
    expect(find.text('Show live heart rate'), findsNothing);
  });

  testWidgets('opted in with no beat shows the no-signal state, not a value',
      (t) async {
    final app = lockedApp()..retainLockedLiveHr();
    addTearDown(app.dispose);
    await pumpCard(t, app);
    expect(app.liveHr, isNull);
    expect(find.text('Show live heart rate'), findsNothing);
    expect(find.text('No live signal — keep the band on and in range.'),
        findsOneWidget);
    expect(find.textContaining(' bpm'), findsNothing);
  });

  testWidgets('opted in with a fresh beat renders the bpm value', (t) async {
    final app = lockedApp()..retainLockedLiveHr();
    app.device.liveHr = 72;
    app.device.liveHrAt = DateTime.now().millisecondsSinceEpoch;
    addTearDown(app.dispose);
    await pumpCard(t, app);
    expect(app.liveHr, 72);
    expect(find.text('Show live heart rate'), findsNothing);
    expect(find.text('72 bpm'), findsWidgets);
  });

  testWidgets('leaving the page clears the opt-in', (t) async {
    final app = lockedApp();
    addTearDown(app.dispose);
    await pumpCard(t, app);
    await t.tap(find.text('Show live heart rate'));
    await t.pump();
    expect(app.lockedLiveHrOptIn, isTrue);
    await t.pumpWidget(host(app, const SizedBox()));
    await t.pump();
    expect(app.lockedLiveHrOptIn, isFalse);
  });
}
