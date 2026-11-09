import 'package:crossdrop/app/theme.dart';
import 'package:crossdrop/app/tokens.dart';
import 'package:crossdrop/app/ui/ui.dart';
import 'package:crossdrop/core/security/device_identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {Brightness brightness = Brightness.dark}) =>
    MaterialApp(
      theme: buildTheme(brightness),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: child,
        ),
      ),
    );

/// Every building block on one screen, for the accessibility guidelines.
Widget gallery() => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    const Row(
      children: [
        DeviceAvatar(name: "Alex's Pixel 8", platform: DevicePlatform.android),
        SizedBox(width: 16),
        DeviceAvatar(name: "Sam's iPhone", platform: DevicePlatform.ios),
        SizedBox(width: 16),
        DeviceAvatar(name: 'Alex', platform: null, locked: true),
      ],
    ),
    const SizedBox(height: 16),
    const Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        StatusBadge.trusted(),
        StatusBadge.firstTime(),
        StatusBadge(
          label: 'Stopped',
          tone: BadgeTone.danger,
          icon: Icons.close,
        ),
        StatusBadge(
          label: 'Paused',
          tone: BadgeTone.neutral,
          icon: Icons.pause,
        ),
        HintChip(label: 'Same Wi-Fi', icon: Icons.wifi),
      ],
    ),
    const SizedBox(height: 16),
    const CodeDisplay(code: '482913'),
    const SizedBox(height: 16),
    const CdProgressBar(value: 0.64, semanticLabel: 'Total progress'),
    const SizedBox(height: 8),
    const CdProgressBar(value: 0.64, paused: true),
    const SizedBox(height: 8),
    const ProgressRing(value: 0.3),
    const SizedBox(height: 16),
    for (final tone in NoticeTone.values) ...[
      NoticeCard(
        title: 'Title ${tone.name}',
        text: 'Keep CrossDrop open and the screen on.',
        icon: Icons.info_outline,
        tone: tone,
      ),
      const SizedBox(height: 8),
    ],
    EmptyState(
      title: 'Nothing sent yet',
      text: 'Photos and files you send or receive show up here.',
      actionLabel: 'Send something',
      onAction: () {},
    ),
    const SizedBox(height: 16),
    PermissionCard(
      icon: Icons.wifi,
      title: 'Let CrossDrop look for nearby phones',
      text: 'Tap Allow when iPhone asks. Nothing leaves this Wi-Fi.',
      buttonLabel: 'Continue',
      onPressed: () {},
    ),
    const SizedBox(height: 16),
    const Center(
      child: QrCard(
        data: 'crossdrop-test',
        semanticLabel: "QR code to connect to Sam's iPhone",
        size: 160,
        caption: 'Scan with the other phone',
      ),
    ),
    const SizedBox(height: 16),
    Builder(
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(onPressed: () {}, child: const Text('Accept')),
          const SizedBox(height: 8),
          FilledButton(
            style: CdButtonStyles.secondary(context),
            onPressed: () {},
            child: const Text('Pause'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () {}, child: const Text('Scan QR')),
          const SizedBox(height: 8),
          OutlinedButton(
            style: CdButtonStyles.danger(context),
            onPressed: () {},
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  ],
);

void main() {
  test('initials come from the first visible character', () {
    expect(DeviceAvatar.initialOf("alex's Pixel"), 'A');
    expect(DeviceAvatar.initialOf('  Mum'), 'M');
    expect(DeviceAvatar.initialOf(''), '?');
    expect(DeviceAvatar.initialOf('👋 Hi'), '👋');
  });

  testWidgets('the code is read digit by digit', (tester) async {
    await tester.pumpWidget(host(const CodeDisplay(code: '482913')));
    expect(find.bySemanticsLabel('Code 4 8 2 9 1 3'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('the code fits a narrow screen without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(const CodeDisplay(code: '482913')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('avatar shows the initial and hides itself from readers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        const DeviceAvatar(
          name: "Alex's Pixel 8",
          platform: DevicePlatform.android,
        ),
      ),
    );
    expect(find.text('A'), findsOneWidget);
    expect(find.bySemanticsLabel('A'), findsNothing);
    semantics.dispose();
  });

  testWidgets('progress bar reports its value', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(const CdProgressBar(value: 0.643, semanticLabel: 'Total progress')),
    );
    final node = tester.getSemantics(find.bySemanticsLabel('Total progress'));
    expect(node.value, '64%');
    semantics.dispose();
  });

  testWidgets('progress clamps out-of-range values', (tester) async {
    await tester.pumpWidget(
      host(
        const Column(
          children: [CdProgressBar(value: 1.7), ProgressRing(value: -1)],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('QR card is dark on white in dark mode', (tester) async {
    await tester.pumpWidget(
      host(const QrCard(data: 'x', semanticLabel: 'QR code')),
    );
    final box = tester.widget<Container>(
      find
          .ancestor(of: find.byType(Column), matching: find.byType(Container))
          .first,
    );
    expect((box.decoration! as BoxDecoration).color, const Color(0xFFFFFFFF));
  });

  testWidgets('notice tones pick their token colors', (tester) async {
    await tester.pumpWidget(
      host(
        const NoticeCard(
          text: 't',
          icon: Icons.warning,
          tone: NoticeTone.danger,
        ),
      ),
    );
    final icon = tester.widget<Icon>(find.byIcon(Icons.warning));
    expect(icon.color, CdColors.dark.danger);
  });

  for (final brightness in Brightness.values) {
    testWidgets('building blocks, ${brightness.name}: a11y guidelines', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(gallery(), brightness: brightness));
      await tester.pump();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
    });

    testWidgets('building blocks, ${brightness.name}: 200% text, no overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: host(gallery(), brightness: brightness),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
