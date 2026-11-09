import 'package:crossdrop/app/theme.dart';
import 'package:crossdrop/core/security/device_identity.dart';
import 'package:crossdrop/features/transfer/flow_track.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// One theme for every pump: a new ThemeData would animate the change.
final _theme = buildTheme(Brightness.dark);

Widget host(FlowMode mode, {bool reduce = false}) => MaterialApp(
  theme: _theme,
  home: MediaQuery(
    data: MediaQueryData(size: const Size(390, 844), disableAnimations: reduce),
    child: Scaffold(
      body: FlowTrack(
        sending: true,
        peerName: "Alex's Pixel 8",
        peerPlatform: DevicePlatform.android,
        mode: mode,
      ),
    ),
  ),
);

void main() {
  testWidgets('files flow while sending and stop when paused', (tester) async {
    await tester.pumpWidget(host(FlowMode.flowing));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(host(FlowMode.frozen));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('reduced motion: still tiles', (tester) async {
    await tester.pumpWidget(host(FlowMode.flowing, reduce: true));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('labels the phones: You and the first name', (tester) async {
    await tester.pumpWidget(host(FlowMode.waiting));
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
  });
}
