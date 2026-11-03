import 'package:crossdrop/core/engine/send_session.dart';
import 'package:crossdrop/core/media/save_target.dart';
import 'package:crossdrop/core/protocol/models.dart';
import 'package:crossdrop/core/security/device_identity.dart';
import 'package:crossdrop/core/storage/transfer_repository.dart';
import 'package:crossdrop/features/receive/receive_controller.dart';
import 'package:crossdrop/features/transfer/transfer_view.dart';
import 'package:flutter_test/flutter_test.dart';

SendSnapshot snap(
  SendPhase phase, {
  List<FileTransferStatus> files = const [FileTransferStatus.saved],
  String? reason,
}) => SendSnapshot(
  phase: phase,
  sessionId: 's1',
  reason: reason,
  totalBytes: 100 * files.length,
  sentBytes: 50,
  files: [
    for (final (i, st) in files.indexed)
      SendFileProgress(
        fileId: 'f$i',
        name: 'f$i.jpg',
        size: 100,
        sentBytes: st == FileTransferStatus.saved ? 100 : 0,
        status: st,
      ),
  ],
);

void main() {
  group('fromSend', () {
    test('null before a send starts', () {
      expect(TransferView.fromSend(null, peerName: 'x'), isNull);
    });

    test('phases map to stages', () {
      final cases = {
        SendPhase.connecting: TransferStage.connecting,
        SendPhase.waitingForAccept: TransferStage.waiting,
        SendPhase.sending: TransferStage.running,
        SendPhase.retrying: TransferStage.retrying,
        SendPhase.paused: TransferStage.paused,
        SendPhase.done: TransferStage.done,
        SendPhase.rejected: TransferStage.rejected,
        SendPhase.cancelled: TransferStage.cancelled,
        SendPhase.failed: TransferStage.failed,
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(
          TransferView.fromSend(snap(key), peerName: 'P')!.stage,
          value,
          reason: key.name,
        );
      }
    });

    test('done with nothing saved is a failure', () {
      final v = TransferView.fromSend(
        snap(SendPhase.done, files: [FileTransferStatus.failed]),
        peerName: 'P',
      )!;
      expect(v.stage, TransferStage.failed);
      expect(v.reason, ErrorCodes.fileFailed);
    });

    test('resumable network failure', () {
      final v = TransferView.fromSend(
        snap(SendPhase.failed, reason: SendReasons.network),
        peerName: 'P',
        peerPlatform: 'ios',
      )!;
      expect(v.canResume, isTrue);
      expect(v.peerPlatform, DevicePlatform.ios);
      expect(v.sending, isTrue);
    });

    test('pausedByUser only while paused', () {
      expect(
        TransferView.fromSend(
          snap(SendPhase.sending),
          peerName: 'P',
          pausedByUser: true,
        )!.pausedByUser,
        isFalse,
      );
      expect(
        TransferView.fromSend(
          snap(SendPhase.paused),
          peerName: 'P',
          pausedByUser: true,
        )!.pausedByUser,
        isTrue,
      );
    });
  });

  test('fromIncoming keeps where files were saved', () {
    final v = TransferView.fromIncoming(
      const IncomingSession(
        sessionId: 's',
        sender: SenderInfo(id: 'i', name: 'Pixel', platform: 'android'),
        status: SessionStatus.transferring,
        doneBytes: 150,
        files: {
          'a': IncomingFile(
            name: 'a.jpg',
            size: 100,
            receivedBytes: 100,
            status: FileTransferStatus.saved,
            savedPath: 'photos:abc',
            savedTo: SaveCollection.photos,
          ),
          'b': IncomingFile(name: 'b.mov', size: 100, receivedBytes: 50),
        },
      ),
    );
    expect(v.stage, TransferStage.running);
    expect(v.sending, isFalse);
    expect(v.fraction, 0.75);
    expect(v.files.first.location, 'photos:abc');
    expect(v.current?.name, 'b.mov');
    expect(v.peerPlatform, DevicePlatform.android);
  });

  test('fromStored derives the collection from the location', () {
    final now = DateTime(2026, 11, 3);
    StoredFile file(String loc) => StoredFile(
      fileId: loc,
      name: 'x',
      size: 1,
      kind: FileKind.photo,
      status: FileTransferStatus.saved,
      transferredBytes: 1,
      finalLocation: loc,
    );
    final v = TransferView.fromStored(
      StoredSession(
        rowId: 1,
        sessionId: 's',
        direction: TransferDirection.receive,
        peer: const SenderInfo(id: 'i', name: 'iPhone', platform: 'ios'),
        status: SessionStatus.done,
        totalBytes: 4,
        createdAt: now,
        updatedAt: now,
        files: [
          file('photos:1'),
          file('content://media/external/images/media/1'),
          file('content://media/external/video/media/2'),
          file('content://media/external/downloads/3'),
        ],
      ),
    );
    expect(v.stage, TransferStage.done);
    expect(v.isSuccess, isTrue);
    expect(v.finishedAt, now);
    expect(
      [for (final f in v.files) f.savedTo],
      [
        SaveCollection.photos,
        SaveCollection.photos,
        SaveCollection.videos,
        SaveCollection.files,
      ],
    );
  });
}
