import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/app_dirs.dart';
import '../../app/media_providers.dart';
import '../../app/providers.dart';
import '../../core/engine/send_session.dart';
import '../../core/log.dart';
import '../../core/media/prepare.dart';
import '../../core/protocol/models.dart';
import '../../core/storage/partial_cleanup.dart';
import '../../platform/android_store.dart';
import '../../core/storage/transfer_repository.dart';
import '../receive/receive_controller.dart';
import '../receive/receive_host.dart';
import '../send/send_controller.dart';
import '../../app/navigation.dart';
import '../../app/tokens.dart';
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

/// Gives up an unfinished transfer. A received one that the running
/// server holds is cancelled through it, so memory and database agree.
Future<void> discardOrCancel(WidgetRef ref, StoredSession s) async {
  if (s.direction == TransferDirection.receive &&
      ref.read(receiveStateProvider).sessions.containsKey(s.sessionId)) {
    await ref.read(receiveControllerProvider.notifier).cancel(s.sessionId);
    return;
  }
  await discardTransfer(ref, s);
}

/// Gives up an unfinished transfer: marks it cancelled, deletes partial
/// files (receive) or tells the receiver (send, best effort,
/// [discardStoredSend]).
Future<void> discardTransfer(WidgetRef ref, StoredSession s) async {
  final repo = ref.read(transferRepositoryProvider);
  if (s.direction == TransferDirection.send) {
    return discardStoredSend(
      repo,
      s,
      credentials: await ref.read(credentialsProvider.future),
    );
  }
  await repo.updateSession(
    s.rowId,
    status: SessionStatus.cancelled,
    reason: SendReasons.discarded,
  );
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
  logEvent('transfer', 'session ${s.sessionId}: discarded');
}

/// Picks an unfinished transfer back up. A send resumes and opens the
/// transfer screen; a receive waits for the sender to reconnect.
void resumeUnfinished(BuildContext context, WidgetRef ref, StoredSession s) {
  if (s.direction == TransferDirection.send) {
    unawaited(ref.read(sendControllerProvider.notifier).resumeStored(s));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: Routes.transfer),
        builder: (_) => const TransferScreen(),
      ),
    );
  } else {
    // This phone is receiving already; the sender resumes when it
    // reconnects.
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          'Ready. ${s.peer.name} continues the transfer when it reconnects. '
          'Keep CrossDrop open.',
        ),
      ),
    );
  }
}

/// One transfer an earlier run left unfinished, on Home (D-069): what,
/// how far, and Resume or Discard.
class UnfinishedCard extends ConsumerWidget {
  const UnfinishedCard({
    super.key,
    required this.session,
    required this.onDone,
  });

  final StoredSession session;

  /// Called after Resume or Discard, so the card can be hidden.
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cd;
    final s = session;
    final count = s.files.length;
    final files = '$count ${count == 1 ? 'file' : 'files'}';
    final percent = s.totalBytes == 0
        ? 0
        : (s.transferredBytes * 100 / s.totalBytes).floor();
    final sending = s.direction == TransferDirection.send;
    final busy = ref.watch(sendControllerProvider.select((x) => x.isRunning));
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: c.warningSoft,
        borderRadius: BorderRadius.circular(CdRadius.button),
        border: Border.all(color: c.warningLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.replay_rounded, color: c.warningInk),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sending
                          ? 'Unfinished: $files to ${s.peer.name}'
                          : 'Unfinished: $files from ${s.peer.name}',
                      style: CdType.titleS.copyWith(
                        fontSize: 15,
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sending
                          ? 'Stopped at $percent% of ${formatSize(s.totalBytes)}'
                          : '$percent% of ${formatSize(s.totalBytes)}. '
                                '${s.peer.name} continues when it reconnects.',
                      style: CdType.small.copyWith(color: c.text2),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (sending) ...[
                Expanded(
                  child: FilledButton(
                    // One send at a time.
                    onPressed: busy
                        ? null
                        : () {
                            resumeUnfinished(context, ref, s);
                            onDone();
                          },
                    child: const Text('Resume'),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await discardOrCancel(ref, s);
                    onDone();
                  },
                  child: const Text('Discard'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
