import 'package:crossdrop/app/theme.dart';
import 'package:crossdrop/core/security/device_identity.dart';
import 'package:crossdrop/features/nearby/radar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<RadarPeer> peers(int n) => [
  for (var i = 0; i < n; i++)
    RadarPeer(
      id: 'p$i',
      name: 'Phone $i',
      platform: DevicePlatform.android,
      hint: 'Same Wi-Fi',
    ),
];

/// One theme for every pump: a new ThemeData would animate the change.
final _theme = buildTheme(Brightness.dark);

Widget host(Widget child, {MediaQueryData? media}) => MaterialApp(
  theme: _theme,
  home: MediaQuery(
    data: media ?? const MediaQueryData(size: Size(390, 844)),
    child: Scaffold(
      body: Padding(padding: const EdgeInsets.all(24), child: child),
    ),
  ),
);

void main() {
  testWidgets('tapping a phone reports it; a locked phone says connecting', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    RadarPeer? tapped;
    await tester.pumpWidget(
      host(Radar(peers: peers(2), searching: true, onTap: (p) => tapped = p)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Phone 1'));
    expect(tapped?.id, 'p1');

    await tester.pumpWidget(
      host(
        Radar(
          peers: peers(2),
          searching: true,
          lockedId: 'p1',
          onTap: (p) => tapped = p,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Connecting…'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Phone 1, Android, Same Wi-Fi, connecting'),
      ),
      findsOneWidget,
    );
    // While locked, other phones cannot be tapped.
    tapped = null;
    await tester.tap(find.text('Phone 0'), warnIfMissed: false);
    expect(tapped, isNull);
    semantics.dispose();
  });

  testWidgets('places at most six phones', (tester) async {
    await tester.pumpWidget(
      host(Radar(peers: peers(9), searching: true, onTap: (_) {})),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Phone 5'), findsOneWidget);
    expect(find.text('Phone 6'), findsNothing);
  });

  testWidgets('pulses while searching, still under reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(Radar(peers: const [], searching: true, onTap: (_) {})),
    );
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpWidget(
      host(
        Radar(peers: const [], searching: true, onTap: (_) {}),
        media: const MediaQueryData(
          size: Size(390, 844),
          disableAnimations: true,
        ),
      ),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('large text or a screen reader asks for the list', (
    tester,
  ) async {
    bool? list;
    Widget probe(MediaQueryData m) => MediaQuery(
      data: m,
      child: Builder(
        builder: (context) {
          list = useRadarList(context);
          return const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(probe(const MediaQueryData()));
    expect(list, isFalse);
    await tester.pumpWidget(
      probe(const MediaQueryData(textScaler: TextScaler.linear(2))),
    );
    expect(list, isTrue);
    await tester.pumpWidget(
      probe(const MediaQueryData(accessibleNavigation: true)),
    );
    expect(list, isTrue);
  });

  testWidgets('fits a small phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      host(
        SingleChildScrollView(
          child: Radar(peers: peers(6), searching: true, onTap: (_) {}),
        ),
        media: const MediaQueryData(size: Size(320, 568)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
