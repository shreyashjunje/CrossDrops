import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/protocol/models.dart';
import '../../core/security/device_identity.dart';
import '../transfer/transfer_format.dart';
import 'accept_dialog.dart';
import 'receive_controller.dart';

class ReceiveScreen extends ConsumerStatefulWidget {
  const ReceiveScreen({super.key});

  @override
  ConsumerState<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends ConsumerState<ReceiveScreen> {
  /// Session whose Accept prompt is open.
  String? _prompting;

  Future<void> _maybePrompt(ReceiveState state) async {
    final pending = state.pendingOffers;
    final open = _prompting;
    if (open != null) {
      // The offer timed out or was withdrawn while the prompt was open.
      if (!pending.any((o) => o.sessionId == open)) {
        _prompting = null;
        Navigator.of(context).pop();
      }
      return;
    }
    if (pending.isEmpty) return;
    final offer = pending.first;
    _prompting = offer.sessionId;
    final decision = await showDialog<AcceptDecision>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AcceptOfferDialog(offer: offer),
    );
    if (!mounted) return;
    if (_prompting == offer.sessionId) {
      _prompting = null;
      if (decision != null) {
        ref
            .read(receiveControllerProvider.notifier)
            .answer(
              offer.sessionId,
              accept: decision.accept,
              trust: decision.trust,
            );
      }
    }
    // Another offer may be waiting.
    await _maybePrompt(ref.read(receiveControllerProvider));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(receiveControllerProvider, (prev, next) {
      if (prev?.pendingOffers != next.pendingOffers) _maybePrompt(next);
      final notice = next.notice;
      if (notice != null && prev?.notice != notice) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(notice)));
        ref.read(receiveControllerProvider.notifier).clearNotice();
      }
    });
    final state = ref.watch(receiveControllerProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Receive')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Receiving'),
            subtitle: Text(
              state.receivingOff
                  ? 'Off: this phone is hidden and refuses new transfers.'
                  : 'On while this screen is open.',
            ),
            value: !state.receivingOff,
            onChanged: (on) =>
                ref.read(receiveControllerProvider.notifier).setReceiving(on),
          ),
          if (state.error != null)
            Text(state.error!, style: TextStyle(color: theme.colorScheme.error))
          else if (state.receivingOff && state.port == null)
            const Text('Receiving is off. Turn it on to receive files.')
          else if (state.port == null)
            const Text('Starting…')
          else ...[
            Text(
              'Ready to receive as ${state.deviceName}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              state.advertising
                  ? 'Phones on this Wi-Fi see you in their nearby list.'
                  : (state.advertiseError ?? 'Starting nearby discovery…'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (state.qrPayload != null) ...[
              Center(
                child: Container(
                  // White background so the code scans in dark mode too.
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(
                    data: state.qrPayload!,
                    size: 220,
                    semanticsLabel: 'CrossDrop connection QR code',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Not in the list? On the other phone tap Send, then Scan QR '
                'code.',
                textAlign: TextAlign.center,
              ),
            ] else
              Text(
                'No Wi-Fi or hotspot address. Join the same Wi-Fi as the '
                'other phone, or use a hotspot.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            const SizedBox(height: 16),
            Text(
              'Or type this on the other phone:',
              style: theme.textTheme.bodySmall,
            ),
            for (final a in state.addresses)
              SelectableText(
                '${a.ip}  (${a.interfaceName})',
                style: theme.textTheme.titleMedium,
              ),
            SelectableText(
              'Port ${state.port}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Keep this screen open. '
              '${describeSaveLocations(DevicePlatform.current)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const Divider(height: 32),
          for (final s in state.sessions.values.toList().reversed)
            _SessionCard(
              session: s,
              onCancel: () => ref
                  .read(receiveControllerProvider.notifier)
                  .cancel(s.sessionId),
            ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.onCancel});

  final IncomingSession session;
  final VoidCallback onCancel;

  String get _status => switch (session.status) {
    SessionStatus.offered => 'Waiting for you to accept',
    SessionStatus.accepted => 'Accepted, waiting for data',
    SessionStatus.transferring || SessionStatus.verifying =>
      '${formatSize(session.doneBytes)} of ${formatSize(session.totalBytes)}'
          ' · ${formatSpeed(session.bytesPerSecond)}'
          ' · ${formatTimeLeft(session.eta)}',
    SessionStatus.paused =>
      'Paused at ${formatSize(session.doneBytes)} of '
          '${formatSize(session.totalBytes)}. Waiting for the sender to '
          'reconnect.',
    SessionStatus.done => 'Done, SHA-256 verified',
    SessionStatus.rejected => switch (session.reason) {
      RejectReasons.timeout => 'Not answered in time',
      RejectReasons.noSpace => 'Refused: not enough free space',
      _ => 'Declined',
    },
    SessionStatus.cancelled =>
      session.reason == 'sender' ? 'Cancelled by the sender' : 'Cancelled',
    SessionStatus.failed => 'Failed (${session.reason ?? 'error'})',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'From ${session.sender.name} · '
                    '${session.files.length} '
                    '${session.files.length == 1 ? 'file' : 'files'}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (!session.status.isTerminal)
                  TextButton(onPressed: onCancel, child: const Text('Cancel')),
              ],
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: session.fraction),
            const SizedBox(height: 4),
            Text(_status),
            const SizedBox(height: 8),
            for (final f in session.files.values) _FileRow(file: f),
          ],
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file});

  final IncomingFile file;

  @override
  Widget build(BuildContext context) {
    final fraction = file.size == 0 ? 1.0 : file.receivedBytes / file.size;
    final trailing = switch (file.status) {
      FileTransferStatus.saved => const Icon(Icons.check, size: 18),
      FileTransferStatus.failed => Icon(
        Icons.error_outline,
        size: 18,
        color: Theme.of(context).colorScheme.error,
      ),
      _ => Text('${(fraction * 100).floor()}%'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (file.savedTo case final to?)
                  Text(
                    formatSavedTo(
                      to,
                      file.saveFallback,
                      platform: DevicePlatform.current,
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: file.saveFallback == null
                          ? null
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}
