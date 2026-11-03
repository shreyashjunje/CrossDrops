import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/client/peer_check.dart';
import '../../core/engine/send_session.dart';
import '../../core/protocol/models.dart';
import '../../core/security/peer_auth.dart';
import '../transfer/transfer_format.dart';
import '../../core/media/format_plan.dart';
import '../../core/media/prepare.dart';
import 'gallery_picker_screen.dart';
import 'send_controller.dart';

class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key, this.target});

  /// Receiver chosen on the Nearby screen. The address stays editable.
  final ConnectTarget? target;

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  late final _host = TextEditingController(text: widget.target?.host);
  late final _port = TextEditingController(
    text: widget.target == null ? null : '${widget.target!.port}',
  );

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  void _send() {
    final port = int.tryParse(_port.text.trim());
    final host = _host.text.trim();
    if (host.isEmpty || port == null || port <= 0 || port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the IP and port shown on Receive')),
      );
      return;
    }
    final t = widget.target;
    // A typed address that differs from the nearby entry has no known id.
    final same = t != null && t.host == host && t.port == port;
    ref
        .read(sendControllerProvider.notifier)
        .send(same ? t : ConnectTarget(host: host, port: port, name: host));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sendControllerProvider);
    final controller = ref.read(sendControllerProvider.notifier);
    final running = state.isRunning;
    final theme = Theme.of(context);
    final snap = state.snapshot;

    return Scaffold(
      appBar: AppBar(title: const Text('Send')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (running || snap != null)
            Text(
              'To ${state.receiverName ?? ''}',
              style: theme.textTheme.titleLarge,
            )
          else if (widget.target?.name case final name?)
            Text('To $name', style: theme.textTheme.titleLarge),
          if (!running) ...[
            TextField(
              controller: _host,
              decoration: const InputDecoration(labelText: 'Receiver IP'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            TextField(
              controller: _port,
              decoration: const InputDecoration(labelText: 'Port'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickMedia,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Photos & videos'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: controller.pickDocuments,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Files'),
                  ),
                ),
              ],
            ),
            if (state.picked.isNotEmpty)
              Row(
                children: [
                  Expanded(child: Text(_pickedSummary(state.picked))),
                  TextButton(
                    onPressed: controller.clearFiles,
                    child: const Text('Clear'),
                  ),
                ],
              ),
          ],
          if ((state.receiver ?? widget.target)?.trust.lookalike
              case final lookalike?) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              color: theme.colorScheme.errorContainer,
              child: Text(
                'This is not the "${lookalike.name}" you trusted: its '
                'security key is different.',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ],
          if (state.preparing case final prep?) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: prep.fraction),
            const SizedBox(height: 8),
            Text(
              prep.fraction == null
                  ? 'Preparing ${prep.index + 1} of ${prep.count}…'
                  : 'Preparing ${prep.index + 1} of ${prep.count}: '
                        'downloading from iCloud '
                        '${(prep.fraction! * 100).floor()}%',
            ),
          ],
          if (state.skipped.isNotEmpty) _SkippedNotice(state.skipped),
          if (state.error != null)
            Text(
              state.error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: state.canSend ? _send : null,
                  child: const Text('Send'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: running ? controller.cancel : null,
                  child: const Text('Cancel'),
                ),
              ),
              if (state.canResume) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: controller.resume,
                    child: const Text('Resume'),
                  ),
                ),
              ],
            ],
          ),
          if (snap != null) ...[
            const SizedBox(height: 24),
            LinearProgressIndicator(value: snap.fraction),
            const SizedBox(height: 8),
            Text(_status(snap), style: theme.textTheme.titleMedium),
            if (snap.phase == SendPhase.waitingForAccept &&
                snap.pairingCode != null) ...[
              const SizedBox(height: 12),
              const Text('Check that the other phone shows this code:'),
              Center(
                child: Text(
                  formatPairingCode(snap.pairingCode!),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    letterSpacing: 2,
                  ),
                ),
              ),
            ],
            if (state.canTrustReceiver) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: controller.trustReceiver,
                icon: const Icon(Icons.verified_user_outlined),
                label: Text('Trust ${state.receiverName ?? 'this device'}'),
              ),
            ],
            if (snap.phase == SendPhase.sending)
              Text(
                '${formatSize(snap.sentBytes)} of '
                '${formatSize(snap.totalBytes)} · '
                '${formatSpeed(snap.bytesPerSecond)} · '
                '${formatTimeLeft(snap.eta)}',
              ),
            const SizedBox(height: 8),
            for (final f in snap.files) _FileRow(file: f),
          ],
        ],
      ),
    );
  }

  Future<void> _pickMedia() async {
    final assets = await Navigator.of(context).push<List<LibraryAsset>>(
      MaterialPageRoute(builder: (_) => const GalleryPickerScreen()),
    );
    if (assets != null) {
      ref.read(sendControllerProvider.notifier).addMedia(assets);
    }
  }

  static String _pickedSummary(List<PickedItem> picked) {
    var photos = 0, videos = 0, files = 0;
    for (final p in picked) {
      switch (p) {
        case PickedAsset(:final asset) when asset.kind == FileKind.video:
          videos++;
        case PickedAsset():
          photos++;
        case PickedFile():
          files++;
      }
    }
    String n(int c, String one, String many) => '$c ${c == 1 ? one : many}';
    return [
      if (photos > 0) n(photos, 'photo', 'photos'),
      if (videos > 0) n(videos, 'video', 'videos'),
      if (files > 0) n(files, 'file', 'files'),
    ].join(', ');
  }

  static String _status(SendSnapshot s) => switch (s.phase) {
    SendPhase.connecting => 'Connecting…',
    SendPhase.waitingForAccept => 'Waiting for the other phone to accept…',
    SendPhase.sending => 'Sending',
    SendPhase.retrying =>
      'Connection lost. Trying again in '
          '${(s.retryIn?.inMilliseconds ?? 0) ~/ 1000 + 1} s…',
    SendPhase.paused => 'Paused while CrossDrop is in the background',
    SendPhase.done =>
      s.failedCount == 0
          ? 'Done, SHA-256 verified by the receiver'
          : 'Done: ${s.savedCount} sent, ${s.failedCount} failed',
    SendPhase.rejected => switch (s.reason) {
      RejectReasons.noSpace =>
        'The other phone does not have enough space '
            '(${formatSize(s.neededBytes ?? 0)} needed).',
      RejectReasons.timeout => 'The other phone did not answer in time.',
      ErrorCodes.receivingOff =>
        'The other phone is not receiving from new devices. Ask its owner '
            'to turn Receiving on.',
      RejectReasons.senderBusy =>
        'The other phone still has an unfinished transfer from you. '
            'Resume it from the start screen, or cancel it there.',
      _ => 'The other phone declined.',
    },
    SendPhase.cancelled =>
      s.reason == 'receiver' ? 'Cancelled by the other phone' : 'Cancelled',
    SendPhase.failed => switch (s.reason) {
      SendReasons.network =>
        'Lost the connection for 2 minutes. Check that both phones are on '
            'the same Wi-Fi, then tap Resume.',
      SendReasons.version => 'Update CrossDrop on the other phone.',
      SendReasons.identityMismatch =>
        'A different device answered at this address.',
      SendReasons.pinMismatch =>
        "That isn't the expected device: its security key is different. "
            'Sending stopped.',
      SendReasons.timeout => 'The other phone did not answer.',
      SendReasons.sourceUnreadable =>
        'A file could not be read any more, so the transfer stopped.',
      SendReasons.sessionLost =>
        'The other phone no longer has this transfer. Send again.',
      ErrorCodes.noSpace =>
        'The other phone ran out of space. Free some space there, then tap '
            'Resume.',
      ErrorCodes.rateLimited =>
        'Too many attempts. Wait a minute, then send again.',
      _ => 'Failed (${s.reason}).',
    },
  };
}

/// Items the preparation left out, and why.
class _SkippedNotice extends StatelessWidget {
  const _SkippedNotice(this.skipped);
  final List<SkippedItem> skipped;

  static String _why(SkipReason r) => switch (r) {
    SkipReason.icloud =>
      'only in iCloud and could not be downloaded. Check the internet '
          'connection, or open it in Photos first',
    SkipReason.notFound =>
      'no longer in your library, or not shared with CrossDrop',
    SkipReason.noSpace => 'not enough free space on this phone to prepare it',
    SkipReason.unreadable => 'could not be read',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = skipped.length;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(8),
      color: theme.colorScheme.errorContainer,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: theme.colorScheme.onErrorContainer),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              n == 1 ? '1 item is not sent:' : '$n items are not sent:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final s in skipped.take(5))
              Text('• ${s.label}: ${_why(s.reason)}.'),
            if (n > 5) Text('…and ${n - 5} more.'),
          ],
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file});

  final SendFileProgress file;

  @override
  Widget build(BuildContext context) {
    final fraction = file.size == 0 ? 1.0 : file.sentBytes / file.size;
    final trailing = switch (file.status) {
      FileTransferStatus.saved => const Icon(Icons.check, size: 18),
      FileTransferStatus.failed => Icon(
        Icons.error_outline,
        size: 18,
        color: Theme.of(context).colorScheme.error,
      ),
      FileTransferStatus.verifying => const Text('verifying'),
      _ => Text('${(fraction * 100).floor()}%'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}
