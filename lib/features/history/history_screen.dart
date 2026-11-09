import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/media_providers.dart';
import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/tokens.dart';
import '../../app/ui/ui.dart';
import '../../core/security/device_identity.dart';
import '../../core/storage/transfer_repository.dart';
import '../receive/receive_host.dart';
import '../send/send_controller.dart';
import '../transfer/result_view.dart';
import '../transfer/transfer_format.dart';
import '../transfer/transfer_screen.dart';
import '../transfer/transfer_view.dart';
import '../transfer/unfinished_transfers.dart';
import 'transfer_row.dart';

/// The last 200 transfers, newest first. Re-read when History opens.
final historyProvider = FutureProvider.autoDispose<List<StoredSession>>(
  (ref) => ref.watch(transferRepositoryProvider).recent(limit: 200),
);

/// Which transfers History shows.
enum HistoryFilter {
  all('All'),
  sent('Sent'),
  received('Received'),
  unfinished('Unfinished');

  const HistoryFilter(this.label);
  final String label;

  bool keeps(StoredSession s) => switch (this) {
    all => true,
    sent => s.direction == TransferDirection.send,
    received => s.direction == TransferDirection.receive,
    unfinished => TransferView.fromStored(s).stage == TransferStage.paused,
  };
}

/// Past transfers from the database, by day, with filters (D-069).
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  var _filter = HistoryFilter.all;

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: switch (history) {
        AsyncData(:final value) when value.isEmpty => const _Empty(),
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: () => ref.refresh(historyProvider.future),
          child: _List(
            sessions: value.where(_filter.keeps).toList(),
            now: DateTime.now(),
            filter: _filter,
            onFilter: (f) => setState(() => _filter = f),
          ),
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
  Widget build(BuildContext context) => LayoutBuilder(
    // Centred, and scrolls when the system text is very large.
    builder: (context, box) => SingleChildScrollView(
      padding: const EdgeInsets.all(CdSpace.gutter),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: (box.maxHeight - 2 * CdSpace.gutter).clamp(
            0,
            double.infinity,
          ),
        ),
        child: const Center(
          child: EmptyState(
            title: 'No transfers yet',
            text: 'Files you send and receive are listed here.',
          ),
        ),
      ),
    ),
  );
}

class _List extends StatelessWidget {
  const _List({
    required this.sessions,
    required this.now,
    required this.filter,
    required this.onFilter,
  });

  final List<StoredSession> sessions;
  final DateTime now;
  final HistoryFilter filter;
  final ValueChanged<HistoryFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final rows = <Widget>[
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          CdSpace.gutter,
          4,
          CdSpace.gutter,
          4,
        ),
        child: Row(
          children: [
            for (final f in HistoryFilter.values) ...[
              ChoiceChip(
                label: Text(f.label),
                selected: f == filter,
                showCheckmark: false,
                onSelected: (_) => onFilter(f),
                labelStyle: CdType.titleS.copyWith(
                  color: f == filter ? c.bg : c.text,
                ),
                selectedColor: c.text,
                backgroundColor: c.bg,
                side: BorderSide(color: f == filter ? c.text : c.lineStrong),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    ];
    if (sessions.isEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.all(CdSpace.xl),
          child: Text(
            'Nothing here yet.',
            textAlign: TextAlign.center,
            style: CdType.bodyM.copyWith(color: c.text2),
          ),
        ),
      );
    }
    String? day;
    for (final s in sessions) {
      final d = formatDay(s.createdAt.toLocal(), now);
      if (d != day) {
        day = d;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CdSpace.gutter,
              20,
              CdSpace.gutter,
              4,
            ),
            child: Semantics(
              header: true,
              child: Text(d, style: CdType.overline.copyWith(color: c.text2)),
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: CdSpace.gutter),
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.cd.line)),
      ),
      child: TransferRow(
        session: session,
        onTap: () => pushScreen<void>(
          context,
          Routes.history,
          HistoryDetailScreen(session: session),
        ),
      ),
    ),
  );
}

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
    final c = context.cd;
    void openLive() => Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: Routes.transfer),
        builder: (_) =>
            TransferScreen(receiveSessionId: sending ? null : s.sessionId),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        CdSpace.gutter,
        8,
        CdSpace.gutter,
        CdSpace.l,
      ),
      children: [
        Text(
          sending
              ? 'Sending to ${s.peer.name}'
              : 'Receiving from ${s.peer.name}',
          style: CdType.h2.copyWith(color: c.text),
        ),
        const SizedBox(height: 16),
        CdProgressBar(value: percent / 100, paused: true),
        const SizedBox(height: 8),
        Text(
          'Unfinished: $percent% of ${formatSize(s.totalBytes)}.',
          style: CdType.bodyL.copyWith(color: c.text),
        ),
        const SizedBox(height: 8),
        Text(
          sending
              ? 'Open CrossDrop on ${s.peer.name}, then tap Resume.'
              : '${s.peer.name} continues it when it reconnects. Keep '
                    'CrossDrop open.',
          style: CdType.bodyM.copyWith(color: c.text2),
        ),
        const SizedBox(height: 24),
        if (live)
          FilledButton(
            style: CdButtonStyles.wide,
            onPressed: openLive,
            child: const Text('View'),
          )
        else if (sending)
          FilledButton(
            style: CdButtonStyles.wide,
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
        const SizedBox(height: 12),
        if (!(live && sending))
          OutlinedButton(
            style: CdButtonStyles.wide,
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
