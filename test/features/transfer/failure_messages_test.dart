import 'package:crossdrop/core/engine/send_session.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/storage/transfer_repository.dart';
import 'package:crossdrop/features/transfer/failure_messages.dart';
import 'package:crossdrop/features/transfer/transfer_view.dart';
import 'package:flutter_test/flutter_test.dart';

TransferView view(
  TransferStage stage, {
  bool sending = true,
  String? reason,
  int? neededBytes,
  List<FileTransferStatus> files = const [FileTransferStatus.saved],
}) => TransferView(
  direction: sending ? TransferDirection.send : TransferDirection.receive,
  peerName: 'Pixel',
  stage: stage,
  reason: reason,
  neededBytes: neededBytes,
  files: [
    for (final s in files)
      TransferFileView(name: 'a', size: 1, doneBytes: 1, status: s),
  ],
);

void main() {
  test('a full success has no failure message', () {
    expect(describeOutcome(view(TransferStage.done)), isNull);
  });

  test('running transfers have no failure message', () {
    for (final s in [
      TransferStage.connecting,
      TransferStage.waiting,
      TransferStage.running,
      TransferStage.retrying,
      TransferStage.paused,
    ]) {
      expect(describeOutcome(view(s)), isNull, reason: s.name);
    }
  });

  test('partial success names the counts', () {
    final m = describeOutcome(
      view(
        TransferStage.done,
        files: [FileTransferStatus.saved, FileTransferStatus.failed],
      ),
    )!;
    expect(m.reason, contains('1 of 2'));
    expect(m.action, NextAction.sendAgain);
  });

  group('sender failures follow the architecture failure table', () {
    final expected = {
      SendReasons.network: NextAction.resume,
      ErrorCodes.noSpace: NextAction.resume,
      SendReasons.version: NextAction.sendAgain,
      SendReasons.pinMismatch: NextAction.none,
      SendReasons.sourceUnreadable: NextAction.sendAgain,
      SendReasons.sessionLost: NextAction.sendAgain,
      ErrorCodes.rateLimited: NextAction.sendAgain,
      ErrorCodes.fileFailed: NextAction.findHelp,
      'something_new': NextAction.sendAgain,
    };
    for (final MapEntry(:key, :value) in expected.entries) {
      test(key, () {
        final m = describeOutcome(view(TransferStage.failed, reason: key))!;
        expect(m.action, value);
        expect(m.title, isNotEmpty);
        expect(m.reason, isNotEmpty);
        expect(m.next, isNotEmpty);
      });
    }

    test('network failure suggests hotspot mode', () {
      final m = describeOutcome(
        view(TransferStage.failed, reason: SendReasons.network),
      )!;
      expect(m.next, contains('hotspot'));
    });

    test('pin mismatch never offers a retry', () {
      final m = describeOutcome(
        view(TransferStage.failed, reason: SendReasons.pinMismatch),
      )!;
      expect(m.action, NextAction.none);
      expect(m.reason, contains('security key'));
    });

    test('unknown code is shown for support', () {
      final m = describeOutcome(view(TransferStage.failed, reason: 'xyz'))!;
      expect(m.reason, contains('xyz'));
    });
  });

  group('rejections', () {
    test('no space names the size needed', () {
      final m = describeOutcome(
        view(
          TransferStage.rejected,
          reason: RejectReasons.noSpace,
          neededBytes: 2500000000,
        ),
      )!;
      expect(m.reason, contains('2.50 GB'));
    });

    test('receiving off tells the other owner what to do', () {
      final m = describeOutcome(
        view(TransferStage.rejected, reason: ErrorCodes.receivingOff),
      )!;
      expect(m.next, contains('Receiving on'));
    });

    test('receiver side: timeout', () {
      final m = describeOutcome(
        view(
          TransferStage.rejected,
          sending: false,
          reason: RejectReasons.timeout,
        ),
      )!;
      expect(m.title, 'Not answered in time');
      expect(m.next, contains('Pixel'));
    });
  });

  test('cancelled by the other side names it', () {
    final m = describeOutcome(
      view(TransferStage.cancelled, sending: false, reason: 'sender'),
    )!;
    expect(m.title, 'Cancelled by Pixel');
    final own = describeOutcome(
      view(TransferStage.cancelled, sending: false, reason: 'receiver'),
    )!;
    expect(own.title, 'Cancelled');
  });

  test('receiver failures', () {
    expect(
      describeOutcome(
        view(TransferStage.failed, sending: false, reason: 'expired'),
      )!.title,
      'Transfer expired',
    );
    expect(
      describeOutcome(
        view(
          TransferStage.failed,
          sending: false,
          reason: ErrorCodes.fileFailed,
        ),
      )!.action,
      NextAction.findHelp,
    );
  });

  test('connect errors point to QR, then hotspot', () {
    expect(
      describeConnectError('network', fromQr: false).action,
      NextAction.scanQr,
    );
    expect(
      describeConnectError('network', fromQr: true).action,
      NextAction.findHelp,
    );
    expect(
      describeConnectError('pin_mismatch', fromQr: true).title,
      "This isn't the device you scanned",
    );
  });

  test('file errors', () {
    expect(describeFileError(ErrorCodes.hashMismatch), contains('damaged'));
    expect(describeFileError(ErrorCodes.tooManyBytes), contains('bigger'));
    expect(describeFileError(null), 'not saved');
  });
}
