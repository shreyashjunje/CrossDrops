import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/app_dirs.dart';
import '../../app/media_providers.dart';
import '../../app/providers.dart';
import '../../core/client/upload_client.dart';
import '../../core/log.dart';
import '../../core/media/prepare.dart';
import '../../core/protocol/models.dart';
import '../../core/storage/partial_cleanup.dart';
import '../../platform/android_store.dart';
import '../../core/storage/transfer_repository.dart';
import '../send/send_controller.dart';
import '../../app/navigation.dart';
import 'transfer_format.dart';
import 'transfer_screen.dart';

/// Runs once per app launch: deletes partial files older than 24 hours,
/// then lists the transfers that can still be resumed.
final unfinishedTransfersProvider = FutureProvider<List<StoredSession>>((
  ref,
) async {
  final repo = ref.read(transferRepositoryProvider);
  try {
    final dirs = await AppDirs.resolve();
    final store = await ref.read(receivedFileStoreProvider.future);
    await PartialCleanup(
      repository: repo,
      incomingTemp: dirs.incomingTemp,
      deletePart: store.delete,
    ).run();
    if (store is MediaStoreFileStore) {
      // Pending items a crash left before their URI was stored.
      await store.cleanupOrphans({
        for (final s in await repo.unfinished())
          for (final f in s.files) ?f.tempPath,
      });
    }
    // After PartialCleanup, which expires sends older than 24 hours.
    await cleanStaging(dirs.outgoingStaging, [
      for (final s in await repo.unfinished())
        if (s.direction == TransferDirection.send)
          for (final f in s.files) ?f.sourcePath,
    ]);
  } catch (e) {
    logEvent('storage', 'cleanup failed: ${e.runtimeType}');
  }
  return repo.unfinished();
});

/// Gives up an unfinished transfer: marks it cancelled, deletes partial
/// files (receive) or tells the receiver (send, best effort).
Future<void> discardTransfer(WidgetRef ref, StoredSession s) async {
  final repo = ref.read(transferRepositoryProvider);
  await repo.updateSession(
    s.rowId,
    status: SessionStatus.cancelled,
    reason: 'discarded',
  );
  if (s.direction == TransferDirection.receive) {
    final dirs = await AppDirs.resolve();
    final store = await ref.read(receivedFileStoreProvider.future);
    for (final f in s.files) {
      final loc = f.tempPath;
      if (loc != null && f.status != FileTransferStatus.saved) {
        await store.delete(loc);
      }
    }
    try {
      await Directory(p.join(dirs.incomingTemp, s.sessionId))
          .delete(recursive: true);
    } on FileSystemException {
      // Already gone.
    }
  } else if (s.peerHost != null &&
      s.peerPort != null &&
      s.peerFingerprint != null) {
    final client = UploadClient(
      host: s.peerHost!,
      port: s.peerPort!,
      fingerprint: s.peerFingerprint!,
      credentials: await ref.read(credentialsProvider.future),
      connectTimeout: const Duration(seconds: 3),
      stallTimeout: const Duration(seconds: 3),
    );
    try {
      await client.cancelSession(s.sessionId);
    } on UploadException {
      // The receiver deletes it after 24 hours anyway.
    } finally {
      client.close();
    }
  }
  logEvent('transfer', 'session ${s.sessionId}: discarded');
}

/// "Resume unfinished transfer?" shown at launch.
class UnfinishedTransfersDialog extends ConsumerWidget {
  const UnfinishedTransfersDialog({super.key, required this.sessions});

  final List<StoredSession> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigator = Navigator.of(context);
    void close() => navigator.pop();

    return AlertDialog(
      title: const Text('Unfinished transfers'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in sessions) ...[
              _Entry(
                session: s,
                onResume: () {
                  close();
                  if (s.direction == TransferDirection.send) {
                    unawaited(
                      ref.read(sendControllerProvider.notifier).resumeStored(s),
                    );
                    navigator.push(
                      MaterialPageRoute<void>(
                        settings: const RouteSettings(name: Routes.transfer),
                        builder: (_) => const TransferScreen(),
                      ),
                    );
                  } else {
                    // This phone is receiving already; the sender resumes
                    // when it reconnects.
                    scaffoldMessengerKey.currentState?.showSnackBar(
                      SnackBar(
                        content: Text(
                          'Ready. ${s.peer.name} continues the transfer when '
                          'it reconnects. Keep CrossDrop open.',
                        ),
                      ),
                    );
                  }
                },
                onDiscard: () async {
                  close();
                  await discardTransfer(ref, s);
                },
              ),
              const Divider(),
            ],
          ],
        ),
      ),
      actions: [TextButton(onPressed: close, child: const Text('Later'))],
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.session,
    required this.onResume,
    required this.onDiscard,
  });

  final StoredSession session;
  final VoidCallback onResume;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final count = s.files.length;
    final files = '$count ${count == 1 ? 'file' : 'files'}';
    final percent = s.totalBytes == 0
        ? 0
        : (s.transferredBytes * 100 / s.totalBytes).floor();
    final sending = s.direction == TransferDirection.send;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sending
              ? 'Sending $files to ${s.peer.name}'
              : 'Receiving $files from ${s.peer.name}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Text('$percent% of ${formatSize(s.totalBytes)} done'),
        if (!sending)
          const Text('The other phone continues when it reconnects.'),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: onDiscard, child: const Text('Discard')),
            FilledButton(onPressed: onResume, child: const Text('Resume')),
          ],
        ),
      ],
    );
  }
}
