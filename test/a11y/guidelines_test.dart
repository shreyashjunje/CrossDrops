import 'package:crossdrop/app/theme.dart';
import 'package:crossdrop/core/engine/send_session.dart';
import 'package:crossdrop/core/media/save_target.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/security/device_identity.dart';
import 'package:crossdrop/core/server/receive_server.dart';
import 'package:crossdrop/core/storage/transfer_repository.dart';
import 'package:crossdrop/features/hotspot/hotspot_screens.dart';
import 'package:crossdrop/features/nearby/find_help_screen.dart';
import 'package:crossdrop/features/onboarding/onboarding_screen.dart';
import 'package:crossdrop/features/receive/incoming_request_screen.dart';
import 'package:crossdrop/features/transfer/progress_view.dart';
import 'package:crossdrop/features/transfer/result_view.dart';
import 'package:crossdrop/features/transfer/transfer_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const files = [
  TransferFileView(
    name: 'IMG_1.HEIC',
    size: 3000000,
    doneBytes: 3000000,
    status: FileTransferStatus.saved,
    savedTo: SaveCollection.photos,
    location: 'content://media/external/images/media/1',
  ),
  TransferFileView(
    name: 'IMG_2.MOV',
    size: 9000000,
    doneBytes: 4000000,
    status: FileTransferStatus.receiving,
  ),
];

TransferView view(TransferStage stage, {String? reason}) => TransferView(
  direction: TransferDirection.send,
  peerName: 'Pixel 8',
  peerPlatform: DevicePlatform.android,
  stage: stage,
  reason: reason,
  doneBytes: 7000000,
  bytesPerSecond: 12000000,
  files: files,
);

final screens = <String, Widget>{
  'Incoming request': IncomingRequestScreen(
    offer: IncomingOffer(
      sessionId: 's',
      sender: const SenderInfo(id: 'i', name: 'iPhone', platform: 'ios'),
      senderFingerprint: 'aa' * 32,
      pairingCode: '123456',
      files: const [FileOffer(fileId: 'f', name: 'a.jpg', size: 1)],
    ),
  ),
  'Progress': Scaffold(
    body: ProgressView(
      view: view(TransferStage.running),
      platform: DevicePlatform.ios,
      onPause: () {},
      onCancel: () {},
    ),
  ),
  'Done': Scaffold(
    body: ResultView(
      view: view(TransferStage.done),
      platform: DevicePlatform.android,
      onOpen: (_) {},
      onClose: () {},
    ),
  ),
  'Failed': Scaffold(
    body: ResultView(
      view: view(TransferStage.failed, reason: SendReasons.network),
      platform: DevicePlatform.android,
      onAction: (_) {},
      onClose: () {},
    ),
  ),
  'Find help': const FindHelpScreen(platform: DevicePlatform.ios),
  'Hotspot mode': const HotspotModeScreen(platform: DevicePlatform.android),
  'Personal Hotspot guide': const PersonalHotspotGuide(),
  'Onboarding': const OnboardingScreen(platform: DevicePlatform.ios),
};

void main() {
  for (final brightness in Brightness.values) {
    for (final MapEntry(key: name, value: screen) in screens.entries) {
      testWidgets('$name, ${brightness.name}: a11y guidelines', (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(theme: buildTheme(brightness), home: screen),
          ),
        );
        await tester.pump();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantics.dispose();
      });
    }
  }
}
