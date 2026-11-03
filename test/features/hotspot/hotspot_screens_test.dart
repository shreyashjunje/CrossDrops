import 'package:crossdrop/core/security/device_identity.dart';
import 'package:crossdrop/features/hotspot/hotspot_screens.dart';
import 'package:crossdrop/platform/hotspot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeHotspot implements HotspotService {
  FakeHotspot(this._support);
  final HotspotSupport _support;
  int stops = 0;

  @override
  Future<HotspotSupport> support() async => _support;

  @override
  Future<HotspotInfo> start() async => const HotspotInfo(
    ssid: 'DIRECT-ab',
    password: 'pw123456',
    qrPayload: 'crossdrop://connect?v=1',
  );

  @override
  Future<void> stop() async => stops++;
}

Future<void> pump(WidgetTester tester, Widget screen, HotspotService s) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [hotspotServiceProvider.overrideWithValue(s)],
        child: MaterialApp(home: screen),
      ),
    );

void main() {
  testWidgets('Android: make a network, or join the iPhone', (tester) async {
    await pump(
      tester,
      const HotspotModeScreen(platform: DevicePlatform.android),
      FakeHotspot(HotspotSupport.notYet),
    );
    expect(find.text('This phone makes the network'), findsOneWidget);
    expect(find.text("Join the iPhone's Personal Hotspot"), findsOneWidget);
  });

  testWidgets('iPhone: join the Android, or Personal Hotspot', (tester) async {
    await pump(
      tester,
      const HotspotModeScreen(platform: DevicePlatform.ios),
      FakeHotspot(HotspotSupport.unsupported),
    );
    expect(find.text("Join the Android phone's network"), findsOneWidget);
    expect(find.text('This iPhone makes the network'), findsOneWidget);
    await tester.tap(find.text('This iPhone makes the network'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Allow Others to Join'), findsOneWidget);
  });

  testWidgets('until Phase 7: the manual way with Android settings', (
    tester,
  ) async {
    await pump(
      tester,
      const AndroidHotspotScreen(),
      FakeHotspot(HotspotSupport.notYet),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('comes in the next update'), findsOneWidget);
    expect(find.text('Start'), findsNothing);
  });

  testWidgets('available: Start shows the network and stops on leave', (
    tester,
  ) async {
    final hotspot = FakeHotspot(HotspotSupport.available);
    await pump(tester, const AndroidHotspotScreen(), hotspot);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Network: DIRECT-ab'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(hotspot.stops, 1);
  });
}
