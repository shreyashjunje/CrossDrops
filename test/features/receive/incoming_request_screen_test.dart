import 'package:crossdrop/app/ui/ui.dart';
import 'package:crossdrop/app/theme.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/server/receive_server.dart';
import 'package:crossdrop/core/storage/trust_repository.dart';
import 'package:crossdrop/features/receive/incoming_request_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TrustedDevice device(String name) => TrustedDevice(
  fingerprint: 'ff' * 32,
  deviceId: 'id',
  name: name,
  platform: 'ios',
  autoAccept: false,
  firstSeen: DateTime(2026),
  lastSeen: DateTime(2026),
);

IncomingOffer offer({PeerTrust trust = PeerTrust.unknown, int files = 3}) =>
    IncomingOffer(
      sessionId: 's1',
      sender: const SenderInfo(
        id: 'id',
        name: "Yash's iPhone",
        platform: 'ios',
      ),
      senderFingerprint: 'aa' * 32,
      pairingCode: '482913',
      trust: trust,
      files: [
        for (var i = 0; i < files; i++)
          FileOffer(
            fileId: 'f$i',
            name: 'IMG_$i.HEIC',
            size: 1000000,
            kind: FileKind.photo,
          ),
      ],
    );

/// Opens the screen from a button and records what it pops with.
Future<List<AcceptDecision?>> open(
  WidgetTester tester,
  IncomingOffer o, {
  Brightness brightness = Brightness.light,
}) async {
  final results = <AcceptDecision?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(brightness),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => results.add(
            await Navigator.of(context).push<AcceptDecision>(
              MaterialPageRoute(
                builder: (_) => IncomingRequestScreen(offer: o),
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

/// The pairing code display showing [code].
Finder codeShown(String code) =>
    find.byWidgetPredicate((w) => w is CodeDisplay && w.code == code);

void main() {
  testWidgets('untrusted sender: who, files, code and first-time warning', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(tester, offer(files: 7));
    expect(find.text("Yash's iPhone"), findsOneWidget);
    expect(find.text('iPhone · Not trusted'), findsOneWidget);
    expect(find.textContaining('First time from this device'), findsOneWidget);
    expect(find.text('wants to send you 7 files · 7.0 MB'), findsOneWidget);
    expect(find.text('IMG_0.HEIC'), findsOneWidget);
    expect(find.text('IMG_4.HEIC'), findsOneWidget);
    expect(find.text('IMG_5.HEIC'), findsNothing);
    expect(find.text('and 2 more'), findsOneWidget);
    expect(codeShown('482913'), findsOneWidget);
    expect(find.bySemanticsLabel('Code 4 8 2 9 1 3'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Trust this device'), 200);
    expect(find.text('Trust this device'), findsOneWidget);
    expect(find.text('Codes match, accept'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('accept with trust ticked', (tester) async {
    final results = await open(tester, offer());
    await tester.tap(find.text('Trust this device'));
    await tester.pump();
    await tester.tap(find.text('Codes match, accept'));
    await tester.pumpAndSettle();
    expect(results.single!.accept, isTrue);
    expect(results.single!.trust, isTrue);
  });

  testWidgets('decline never trusts', (tester) async {
    final results = await open(tester, offer());
    await tester.tap(find.text('Trust this device'));
    await tester.pump();
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    expect(results.single!.accept, isFalse);
    expect(results.single!.trust, isFalse);
  });

  testWidgets('back declines', (tester) async {
    final results = await open(tester, offer());
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(results.single!.accept, isFalse);
  });

  testWidgets('trusted sender: no code, no trust option, plain Accept', (
    tester,
  ) async {
    final results = await open(
      tester,
      offer(trust: PeerTrust(trusted: device("Yash's iPhone"))),
    );
    expect(find.text('iPhone · Trusted'), findsOneWidget);
    expect(find.textContaining('First time'), findsNothing);
    expect(codeShown('482913'), findsNothing);
    expect(find.text('Trust this device'), findsNothing);
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(results.single!.accept, isTrue);
    expect(results.single!.trust, isFalse);
  });

  testWidgets('lookalike: warns that it is not the trusted device', (
    tester,
  ) async {
    await open(tester, offer(trust: PeerTrust(lookalike: device('Old'))));
    expect(
      find.textContaining('This is not the "Old" you trusted'),
      findsOneWidget,
    );
    expect(find.textContaining('First time'), findsNothing);
    // Still untrusted: the code check applies.
    expect(codeShown('482913'), findsOneWidget);
  });

  testWidgets('countdown runs down to expired', (tester) async {
    await open(tester, offer());
    await tester.scrollUntilVisible(find.textContaining('This request'), 200);
    expect(find.text('This request expires in 60 s.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('This request expires in 55 s.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 60));
    expect(find.text('This request has expired.'), findsOneWidget);
  });

  testWidgets('large text and dark mode: no overflow', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 568 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester, offer(files: 9), brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Trust this device'), 200);
    expect(find.text('Codes match, accept'), findsOneWidget);
  });
}
