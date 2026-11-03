import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/media_providers.dart';
import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../core/security/device_identity.dart';
import '../../core/storage/transfer_repository.dart';
import '../receive/receive_host.dart';
import '../send/send_controller.dart';
import '../transfer/result_view.dart';
import '../transfer/transfer_format.dart';
import '../transfer/transfer_screen.dart';
import '../transfer/transfer_view.dart';
import '../transfer/unfinished_transfers.dart';
import '../transfer/widgets.dart';

/// The last 200 transfers, newest first. Re-read when History opens.
final historyProvider = FutureProvider.autoDispose<List<StoredSession>>(
  (ref) => ref.watch(transferRepositoryProvider).recent(limit: 200),
);

/// Past transfers from the database: direction, device, size, status.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: switch (history) {
        AsyncData(:final value) when value.isEmpty => const _Empty(),
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: () => ref.refresh(historyProvider.future),
          child: _List(sessions: value, now: DateTime.now()),
        ),
        AsyncError() => const Center(child: Text('History could not be read.')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'No transfers yet. Files you send and receive are listed here.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    ),
  );
}

class _List extends StatelessWidget {
  const _List({required this.sessions, required this.now});

  final List<StoredSession> sessions;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    String? day;
    for (final s in sessions) {
      final d = formatDay(s.createdAt.toLocal(), now);
      if (d != day) {
        day = d;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Semantics(
              header: true,
              child: Text(d, style: Theme.of(context).textTheme.titleSmall),
            ),
          ),
        );
      }
      rows.add(HistoryTile(session: s));
    }
    return ListView(children: rows);
  }
}

/// One past transfer.
class HistoryTile extends StatelessWidget {
  const HistoryTile({super.key, required this.session});

  final StoredSession session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final v = TransferView.fromStored(s);
    final n = s.files.length;
    final sending = s.direction == TransferDirection.send;
    final scheme = Theme.of(context).colorScheme;
    final (status, color) = statusLabel(v, scheme);
    return ListTile(
      leading: Icon(
        sending ? Icons.north_east : Icons.south_west,
        semanticLabel: sending ? 'Sent' : 'Received',
      ),
      title: Text(
        '${sending ? 'To' : 'From'} ${s.peer.name}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$n ${n == 1 ? 'file' : 'files'} · ${formatSize(s.totalBytes)} · '
        '${platformLabel(v.peerPlatform)}',
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(status, style: TextStyle(color: color)),
          Text(formatTime(s.createdAt.toLocal())),
        ],
      ),
      onTap: () => pushScreen<void>(
        context,
        Routes.history,
        HistoryDetailScreen(session: s),
      ),
    );
  }
}

/// "Done", "Failed", ... with a color that keeps contrast in both themes.
(String, Color?) statusLabel(TransferView v, ColorScheme scheme) =>
    switch (v.stage) {
      TransferStage.done when v.failedCount > 0 => ('Partly', scheme.error),
      TransferStage.done => ('Done', scheme.primary),
      TransferStage.failed => ('Failed', scheme.error),
      TransferStage.cancelled => ('Cancelled', null),
      TransferStage.rejected => ('Declined', null),
      TransferStage.paused => ('Unfinished', scheme.error),
      _ => ('In progress', scheme.primary),
    };

/// One past transfer in full: what arrived and where, or why it failed.
/// An unfinished send can be resumed or discarded here.
class HistoryDetailScreen extends ConsumerWidget {
  const HistoryDetailScreen({super.key, required this.session});

  final StoredSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = session;
    final v = TransferView.fromStored(s);
    final Widget body;
    if (v.stage.isFinished) {
      body = ResultView(
        view: v,
        platform: DevicePlatform.current,
        onOpen: (f) async {
          final messenger = ScaffoldMessenger.of(context);
          final ok = await ref.read(fileOpenerProvider).open(f.location!);
          if (!ok) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text(
                  'Could not open it. It may have been moved or deleted.',
                ),
              ),
            );
          }
        },
        onClose: () => Navigator.of(context).pop(),
      );
    } else {
      body = _Unfinished(session: s, view: v);
    }
    return Scaffold(
      appBar: AppBar(title: Text(formatDay(s.createdAt, DateTime.now()))),
      body: body,
    );
  }
}

class _Unfinished extends ConsumerWidget {
  const _Unfinished({required this.session, required this.view});

  final StoredSession session;
  final TransferView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = session;
    final sending = s.direction == TransferDirection.send;
    final send = ref.watch(sendControllerProvider);
    final live = sending
        ? send.isRunning && send.snapshot?.sessionId == s.sessionId
        : ref.watch(
            receiveStateProvider.select(
              (r) => !(r.sessions[s.sessionId]?.status.isTerminal ?? true),
            ),
          );
    final percent = s.totalBytes == 0
        ? 0
        : (s.transferredBytes * 100 / s.totalBytes).floor();
    final theme = Theme.of(context);
    void openLive() => Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: Routes.transfer),
        builder: (_) =>
            TransferScreen(receiveSessionId: sending ? null : s.sessionId),
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          sending
              ? 'Sending to ${s.peer.name}'
              : 'Receiving from ${s.peer.name}',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Unfinished: $percent% of ${formatSize(s.totalBytes)}.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        Text(
          sending
              ? 'Open CrossDrop on ${s.peer.name}, then tap Resume.'
              : '${s.peer.name} continues it when it reconnects. Keep '
                    'CrossDrop open.',
        ),
        const SizedBox(height: 16),
        if (live)
          FilledButton(onPressed: openLive, child: const Text('View'))
        else if (sending)
          FilledButton(
            // One send at a time.
            onPressed: send.isRunning
                ? null
                : () {
                    unawaited(
                      ref.read(sendControllerProvider.notifier).resumeStored(s),
                    );
                    openLive();
                  },
            child: const Text('Resume'),
          ),
        const SizedBox(height: 8),
        if (!(live && sending))
          OutlinedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              await discardOrCancel(ref, s);
              ref.invalidate(historyProvider);
              navigator.pop();
            },
            child: const Text('Discard'),
          ),
      ],
    );
  }
}
