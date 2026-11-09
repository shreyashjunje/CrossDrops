import 'package:crossdrop/app/ui/ui.dart';
import 'package:crossdrop/app/theme.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/security/device_identity.dart';
import 'package:crossdrop/core/storage/transfer_repository.dart';
import 'package:crossdrop/features/transfer/progress_view.dart';
import 'package:crossdrop/features/transfer/transfer_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TransferView view({
  TransferStage stage = TransferStage.running,
  bool sending = true,
  bool pausedByUser = false,
  String? pairingCode,
}) => TransferView(
  direction: sending ? TransferDirection.send : TransferDirection.receive,
  peerName: 'Pixel 8',
  peerPlatform: DevicePlatform.android,
  stage: stage,
  doneBytes: 297000000,
  bytesPerSecond: 18400000,
  eta: const Duration(seconds: 7),
  pausedByUser: pausedByUser,
  pairingCode: pairingCode,
  files: const [
    TransferFileView(
      name: 'IMG_4022.HEIC',
      size: 3000000,
      doneBytes: 3000000,
      status: FileTransferStatus.saved,
    ),
    TransferFileView(
      name: 'IMG_4021.MOV',
      size: 409000000,
      doneBytes: 294000000,
      status: FileTransferStatus.receiving,
    ),
  ],
);

class Taps {
  int pause = 0, resume = 0, cancel = 0;
}

Future<Taps> pump(
  WidgetTester tester,
  TransferView v, {
  DevicePlatform platform = DevicePlatform.ios,
  Brightness brightness = Brightness.light,
}) async {
  final taps = Taps();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(brightness),
      home: Scaffold(
        body: ProgressView(
          view: v,
          platform: platform,
          onPause: () => taps.pause++,
          onResume: () => taps.resume++,
          onCancel: () => taps.cancel++,
        ),
      ),
    ),
  );
  return taps;
}

/// The pairing code display showing [code].
Finder codeShown(String code) =>
    find.byWidgetPredicate((w) => w is CodeDisplay && w.code == code);

void main() {
  test('several files moving together say so (D-068)', () {
    TransferFileView f(FileTransferStatus s) =>
        TransferFileView(name: 'x', size: 10, doneBytes: 5, status: s);
    final v = TransferView(
      direction: TransferDirection.send,
      peerName: 'P',
      stage: TransferStage.running,
      files: [
        f(FileTransferStatus.saved),
        f(FileTransferStatus.receiving),
        f(FileTransferStatus.verifying),
        f(FileTransferStatus.receiving),
        f(FileTransferStatus.pending),
      ],
    );
    expect(ProgressView.stageText(v), 'Sending 3 files at once · 1 of 5 done');
  });

  testWidgets('total and per-file progress, speed and time left', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, view());
    expect(find.text('Sending to Pixel 8'), findsOneWidget);
    expect(find.text('Sending 2 of 2'), findsOneWidget);
    expect(find.text('297.0 MB of 412.0 MB sent · 72%'), findsOneWidget);
    expect(find.text('18.4 MB/s · 7 s left'), findsOneWidget);
    expect(find.text('IMG_4022.HEIC'), findsOneWidget);
    expect(find.text('IMG_4021.MOV'), findsOneWidget);
    expect(find.text('71%'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^IMG_4022\.HEIC\s+[\d.]+ MB\s+done$')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^IMG_4021\.MOV\s+[\d.]+ MB\s+71%$')),
      findsOneWidget,
    );
    final total = tester.getSemantics(find.bySemanticsLabel('Total progress'));
    expect(total.value, '72%');
    semantics.dispose();
  });

  testWidgets('iPhone: keep CrossDrop open and the screen on', (tester) async {
    await pump(tester, view());
    expect(
      find.textContaining('Keep CrossDrop open and the screen on'),
      findsOneWidget,
    );
  });

  testWidgets('Android: the notification keeps it going', (tester) async {
    await pump(tester, view(), platform: DevicePlatform.android);
    expect(
      find.textContaining('Keep CrossDrop open and the screen'),
      findsNothing,
    );
    expect(find.textContaining('notification'), findsOneWidget);
  });

  testWidgets('sender can pause and cancel', (tester) async {
    final taps = await pump(tester, view());
    await tester.tap(find.text('Pause'));
    await tester.tap(find.text('Cancel'));
    expect(taps.pause, 1);
    expect(taps.cancel, 1);
    expect(find.text('Resume'), findsNothing);
  });

  testWidgets('paused by the user shows Resume', (tester) async {
    final taps = await pump(
      tester,
      view(stage: TransferStage.paused, pausedByUser: true),
    );
    expect(find.text('Paused. Tap Resume to go on.'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);
    await tester.tap(find.text('Resume'));
    expect(taps.resume, 1);
  });

  testWidgets('receiver: cancel only, waits for the sender when paused', (
    tester,
  ) async {
    await pump(tester, view(sending: false, stage: TransferStage.paused));
    expect(find.text('Receiving from Pixel 8'), findsOneWidget);
    expect(
      find.text('Paused. Waiting for Pixel 8 to reconnect…'),
      findsOneWidget,
    );
    expect(find.text('Pause'), findsNothing);
    expect(find.text('Resume'), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('sender waiting for accept shows the pairing code', (
    tester,
  ) async {
    await pump(
      tester,
      view(stage: TransferStage.waiting, pairingCode: '048213'),
    );
    expect(find.text('Waiting for Pixel 8 to accept…'), findsOneWidget);
    expect(codeShown('048213'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);
  });

  testWidgets('retrying counts down', (tester) async {
    await pump(
      tester,
      TransferView(
        direction: TransferDirection.send,
        peerName: 'P',
        stage: TransferStage.retrying,
        retryIn: const Duration(milliseconds: 3500),
        files: const [],
      ),
    );
    expect(find.text('Connection lost. Trying again in 4 s…'), findsOneWidget);
  });

  testWidgets('small phone, large text, dark mode: no overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320 * 3, 568 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, view(), brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
    expect(find.text('Pause'), findsOneWidget);
  });
}
