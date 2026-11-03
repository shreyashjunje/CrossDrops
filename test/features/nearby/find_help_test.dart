import 'package:crossdrop/core/security/device_identity.dart';
import 'package:crossdrop/features/nearby/find_help_screen.dart';
import 'package:crossdrop/features/nearby/nearby_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<FindHelpResult?>> open(
  WidgetTester tester,
  DevicePlatform platform,
) async {
  final results = <FindHelpResult?>[];
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => results.add(
              await Navigator.of(context).push<FindHelpResult>(
                MaterialPageRoute(
                  builder: (_) => FindHelpScreen(platform: platform),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  test('connection hint: iPhone hotspot addresses', () {
    expect(connectionHint('172.20.10.2'), 'via iPhone hotspot');
    expect(connectionHint('192.168.1.23'), 'same Wi-Fi');
  });

  testWidgets('walks through basics, then QR, then hotspot', (tester) async {
    await open(tester, DevicePlatform.android);
    expect(find.text('1. Check both phones'), findsOneWidget);
    expect(find.textContaining('Local Network'), findsNothing);
    await tester.scrollUntilVisible(find.text('3. Use hotspot mode'), 300);
    expect(find.text('2. Use the QR code'), findsOneWidget);
    expect(find.text('Hotspot mode'), findsOneWidget);
  });

  testWidgets('iPhone: mentions Local Network with a Settings link', (
    tester,
  ) async {
    await open(tester, DevicePlatform.ios);
    expect(find.textContaining('Local Network is allowed'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
  });

  testWidgets('Scan QR code returns to the nearby screen to scan', (
    tester,
  ) async {
    final results = await open(tester, DevicePlatform.android);
    await tester.ensureVisible(find.text('Scan QR code'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan QR code'));
    await tester.pumpAndSettle();
    expect(results, [FindHelpResult.scanQr]);
  });

  testWidgets('Hotspot mode opens the chooser for this phone', (tester) async {
    await open(tester, DevicePlatform.ios);
    await tester.scrollUntilVisible(find.text('Hotspot mode'), 300);
    await tester.ensureVisible(find.text('Hotspot mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hotspot mode'));
    await tester.pumpAndSettle();
    expect(find.text("Join the Android phone's network"), findsOneWidget);
  });
}
