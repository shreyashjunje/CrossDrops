import 'package:crossdrop/app/theme.dart';
import 'package:crossdrop/core/engine/send_session.dart';
import 'package:crossdrop/core/media/save_target.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/security/device_identity.dart';
import 'package:crossdrop/core/server/file_store.dart';
import 'package:crossdrop/core/storage/transfer_repository.dart';
import 'package:crossdrop/features/transfer/failure_messages.dart';
import 'package:crossdrop/features/transfer/result_view.dart';
import 'package:crossdrop/features/transfer/transfer_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const photo = TransferFileView(
  name: 'IMG_4021.HEIC',
  size: 3000000,
  doneBytes: 3000000,
  status: FileTransferStatus.saved,
  savedTo: SaveCollection.photos,
  location: 'content://media/external/images/media/7',
);

const webm = TransferFileView(
  name: 'clip.webm',
  size: 9000000,
  doneBytes: 9000000,
  status: FileTransferStatus.saved,
  savedTo: SaveCollection.files,
  saveFallback: SaveFallback.unsupported,
  location: 'content://media/external/downloads/8',
);

const broken = TransferFileView(
  name: 'IMG_4022.MOV',
  size: 100,
  doneBytes: 0,
  status: FileTransferStatus.failed,
  error: ErrorCodes.hashMismatch,
);

TransferView view({
  TransferStage stage = TransferStage.done,
  bool sending = false,
  String? reason,
  List<TransferFileView> files = const [photo, webm],
}) => TransferView(
  direction: sending ? TransferDirection.send : TransferDirection.receive,
  peerName: "Yash's iPhone",
  stage: stage,
  reason: reason,
  files: files,
);

class Calls {
  final opened = <String>[];
  final actions = <NextAction>[];
  int trust = 0, close = 0;
}

Future<Calls> pump(
  WidgetTester tester,
  TransferView v, {
  bool canTrust = false,
  DevicePlatform platform = DevicePlatform.android,
  Brightness brightness = Brightness.light,
}) async {
  final calls = Calls();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(brightness),
      home: Scaffold(
        body: ResultView(
          view: v,
          platform: platform,
          onOpen: (f) => calls.opened.add(f.name),
          onAction: calls.actions.add,
          onTrust: canTrust ? () => calls.trust++ : null,
          onClose: () => calls.close++,
        ),
      ),
    ),
  );
  return calls;
}

void main() {
  group('Done', () {
    testWidgets('what arrived, where it was saved, Open', (tester) async {
      final calls = await pump(tester, view());
      expect(find.text('2 files received'), findsOneWidget);
      expect(find.text("from Yash's iPhone · 12.0 MB"), findsOneWidget);
      expect(find.text('Saved to Pictures/CrossDrop'), findsOneWidget);
      expect(find.text('Saved to Download/CrossDrop'), findsOneWidget);
      expect(
        find.text(
          'Saved to Download/CrossDrop (the gallery cannot open this format)',
        ),
        findsOneWidget,
      );
      expect(find.text('What happened'), findsNothing);
      await tester.tap(find.text('Open').first);
      expect(calls.opened, ['IMG_4021.HEIC']);
      await tester.tap(find.text('Done'));
      expect(calls.close, 1);
    });

    testWidgets('iPhone Photos items open the Photos app', (tester) async {
      await pump(
        tester,
        view(
          files: const [
            TransferFileView(
              name: 'a.jpg',
              size: 1,
              doneBytes: 1,
              status: FileTransferStatus.saved,
              savedTo: SaveCollection.photos,
              location: 'photos:ABC',
            ),
          ],
        ),
        platform: DevicePlatform.ios,
      );
      expect(find.text('Saved to Photos'), findsOneWidget);
      expect(find.text('Open Photos'), findsOneWidget);
    });

    testWidgets('sender: verified, and Trust offered', (tester) async {
      final calls = await pump(
        tester,
        view(sending: true, files: const [photo]),
        canTrust: true,
      );
      expect(find.text('1 file sent'), findsOneWidget);
      expect(find.textContaining('SHA-256'), findsOneWidget);
      expect(find.text('Open'), findsNothing);
      await tester.tap(find.text("Trust Yash's iPhone"));
      expect(calls.trust, 1);
    });
  });

  group('Failed', () {
    testWidgets('network: plain reason, next step and Resume', (tester) async {
      final calls = await pump(
        tester,
        view(
          sending: true,
          stage: TransferStage.failed,
          reason: SendReasons.network,
          files: const [broken],
        ),
      );
      expect(find.text('Connection lost'), findsOneWidget);
      expect(find.text('What happened'), findsOneWidget);
      expect(
        find.text('The phones could not reach each other for 2 minutes.'),
        findsOneWidget,
      );
      expect(find.textContaining('use hotspot mode'), findsOneWidget);
      await tester.tap(find.text('Resume'));
      expect(calls.actions, [NextAction.resume]);
    });

    testWidgets('no space on the other phone', (tester) async {
      await pump(
        tester,
        view(
          sending: true,
          stage: TransferStage.failed,
          reason: ErrorCodes.noSpace,
        ),
      );
      expect(find.text('The other phone is full'), findsOneWidget);
      expect(find.textContaining('Free some space'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
    });

    testWidgets('pin mismatch: warning, no retry button', (tester) async {
      await pump(
        tester,
        view(
          sending: true,
          stage: TransferStage.failed,
          reason: SendReasons.pinMismatch,
          files: const [broken],
        ),
      );
      expect(find.text('Not the expected phone'), findsOneWidget);
      expect(find.text('Resume'), findsNothing);
      expect(find.text('Send again'), findsNothing);
    });

    testWidgets('declined: Send again', (tester) async {
      final calls = await pump(
        tester,
        view(
          sending: true,
          stage: TransferStage.rejected,
          reason: RejectReasons.declined,
          files: const [broken],
        ),
      );
      expect(find.text('Declined'), findsOneWidget);
      await tester.tap(find.text('Send again'));
      expect(calls.actions, [NextAction.sendAgain]);
    });

    testWidgets('partial: arrived files and the failed ones with a reason', (
      tester,
    ) async {
      await pump(tester, view(files: const [photo, broken]));
      expect(find.text('Some files did not arrive'), findsOneWidget);
      expect(find.text('IMG_4021.HEIC'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Not saved'), 200);
      expect(find.text('Not saved'), findsOneWidget);
      expect(find.text('arrived damaged twice, not saved'), findsOneWidget);
    });

    testWidgets('cancelled by the sender', (tester) async {
      await pump(
        tester,
        view(
          stage: TransferStage.cancelled,
          reason: 'sender',
          files: const [photo],
        ),
      );
      expect(find.text("Cancelled by Yash's iPhone"), findsOneWidget);
      expect(find.text('Files that already arrived are kept.'), findsOneWidget);
    });

    testWidgets('small phone, large text, dark mode: no overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320 * 3, 568 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(
        tester,
        view(
          sending: true,
          stage: TransferStage.failed,
          reason: SendReasons.network,
          files: const [photo, broken],
        ),
        brightness: Brightness.dark,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Done'), findsOneWidget);
    });
  });
}
