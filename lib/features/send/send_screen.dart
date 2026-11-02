import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/client/peer_check.dart';
import '../transfer/transfer_format.dart';
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
    ref.read(sendControllerProvider.notifier).send(host, port);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sendControllerProvider);
    final controller = ref.read(sendControllerProvider.notifier);
    final sending = state.phase == SendPhase.sending;
    final theme = Theme.of(context);
    final progress = state.progress;

    return Scaffold(
      appBar: AppBar(title: const Text('Send')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.target?.name case final name?)
            Text('To $name', style: theme.textTheme.titleLarge),
          TextField(
            controller: _host,
            enabled: !sending,
            decoration: const InputDecoration(labelText: 'Receiver IP'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          TextField(
            controller: _port,
            enabled: !sending,
            decoration: const InputDecoration(labelText: 'Port'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: sending ? null : controller.pickFile,
            child: const Text('Pick file'),
          ),
          if (state.name != null) ...[
            const SizedBox(height: 8),
            Text(
              '${state.name} · ${formatMegabytes(state.size ?? 0)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: sending || state.path == null ? null : _send,
                  child: const Text('Send'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: sending ? controller.cancel : null,
                  child: const Text('Stop'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: state.canResume ? controller.resume : null,
                  child: const Text('Resume'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (progress != null) ...[
            LinearProgressIndicator(value: progress.fraction),
            const SizedBox(height: 8),
            Text(
              '${formatMegabytes(progress.sentBytes)} of '
              '${formatMegabytes(progress.totalBytes)}',
            ),
            if (sending)
              Text(
                formatSpeed(progress.bytesPerSecond),
                style: theme.textTheme.headlineMedium,
              ),
          ],
          const SizedBox(height: 8),
          switch (state.phase) {
            SendPhase.done => Text(
              'Done, SHA-256 verified by receiver.\n'
              'Time ${formatDuration(state.elapsed!)} · average '
              '${state.averageMegabytesPerSecond!.toStringAsFixed(1)} MB/s',
              style: theme.textTheme.titleMedium,
            ),
            SendPhase.cancelled => const Text(
              'Stopped. Tap Resume to continue.',
            ),
            SendPhase.failed => Text(
              'Failed: ${state.error}',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            _ => const SizedBox.shrink(),
          },
          if (state.phase == SendPhase.idle && state.error != null)
            Text(
              state.error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
        ],
      ),
    );
  }
}
