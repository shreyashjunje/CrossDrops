import 'package:crossdrop/app/theme.dart';
import 'package:crossdrop/core/media/save_target.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/security/device_identity.dart';
import 'package:crossdrop/core/storage/transfer_repository.dart';
import 'package:crossdrop/features/onboarding/onboarding_art.dart';
import 'package:crossdrop/features/transfer/result_view.dart';
import 'package:crossdrop/features/transfer/transfer_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// One theme for every pump: a new ThemeData would animate the change.
final _theme = buildTheme(Brightness.dark);

Widget still(Widget child) => MaterialApp(
  theme: _theme,
  home: MediaQuery(
    data: const MediaQueryData(size: Size(390, 844), disableAnimations: true),
    child: Scaffold(body: child),
  ),
);

const _done = TransferView(
  direction: TransferDirection.receive,
  peerName: "Sam's iPhone",
  stage: TransferStage.done,
  files: [
    TransferFileView(
      name: 'IMG_1.HEIC',
      size: 3000000,
      doneBytes: 3000000,
      status: FileTransferStatus.saved,
      savedTo: SaveCollection.photos,
    ),
  ],
);

/// Under the system's reduce-motion setting nothing moves by itself
/// (D-069). The radar and the flow track have their own tests.
void main() {
  testWidgets('Done: the check is drawn at once', (tester) async {
    await tester.pumpWidget(
      still(const ResultView(view: _done, platform: DevicePlatform.android)),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('Onboarding pictures stand still', (tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pumpWidget(
        still(OnboardingArt(index: i, platform: DevicePlatform.ios)),
      );
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse, reason: 'page $i');
    }
  });
}
