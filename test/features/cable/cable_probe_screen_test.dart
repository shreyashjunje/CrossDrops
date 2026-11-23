import 'package:crossdrop/features/cable/cable_probe_screen.dart';
import 'package:crossdrop/features/cable/cable_controllers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_usb_cable.dart';

void main() {
  testWidgets('runs the cable test with the typed port and shows the report', (
    tester,
  ) async {
    final camera = FakeUsbCable()
      ..probeReport =
          'Handshake: ok, version 2\nCrossDrop (port 4321): reachable';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [usbCableProvider.overrideWithValue(camera)],
        child: const MaterialApp(home: CableProbeScreen()),
      ),
    );

    await tester.enterText(find.byType(TextField), '4321');
    await tester.tap(find.text('Run test'));
    await tester.pumpAndSettle();

    expect(camera.probedPort, 4321);
    expect(find.textContaining('reachable'), findsOneWidget);
    expect(find.text('Copy report'), findsOneWidget);
  });

  testWidgets('an empty or invalid port tests only the tunnel', (tester) async {
    final camera = FakeUsbCable();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [usbCableProvider.overrideWithValue(camera)],
        child: const MaterialApp(home: CableProbeScreen()),
      ),
    );

    await tester.enterText(find.byType(TextField), '99999');
    await tester.tap(find.text('Run test'));
    await tester.pumpAndSettle();

    expect(camera.probedPort, isNull);
  });
}
