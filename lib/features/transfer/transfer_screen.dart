import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/device_identity.dart';
import '../receive/receive_controller.dart';
import '../receive/receive_host.dart';
import '../send/send_controller.dart';
import 'progress_view.dart';
import 'transfer_view.dart';

/// One transfer: progress while it runs, then Done or Failed. With no
/// [receiveSessionId] it shows this phone's send.
class TransferScreen extends ConsumerWidget {
  const TransferScreen({super.key, this.receiveSessionId});

  final String? receiveSessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = receiveSessionId;
    final Widget body;
    if (id == null) {
      final s = ref.watch(sendControllerProvider);
      final view = TransferView.fromSend(
        s.snapshot,
        peerName: s.receiverName ?? 'the other phone',
        peerPlatform: s.receiver?.platform,
        pausedByUser: s.pausedByUser,
      );
      final send = ref.read(sendControllerProvider.notifier);
      if (s.preparing case final prep?) {
        body = _Preparing(
          text: prep.fraction == null
              ? 'Preparing ${prep.index + 1} of ${prep.count}…'
              : 'Preparing ${prep.index + 1} of ${prep.count}: downloading '
                    'from iCloud ${(prep.fraction! * 100).floor()}%',
          fraction: prep.fraction,
          onCancel: send.cancel,
        );
      } else if (view == null) {
        body = const Center(child: CircularProgressIndicator());
      } else {
        body = ProgressView(
          view: view,
          platform: DevicePlatform.current,
          onPause: send.pause,
          onResume: send.continueSending,
          onCancel: () => _confirmCancel(context, send.cancel),
        );
      }
    } else {
      final session = ref.watch(
        receiveStateProvider.select((s) => s.sessions[id]),
      );
      if (session == null) {
        body = const Center(child: Text('This transfer is no longer here.'));
      } else {
        body = ProgressView(
          view: TransferView.fromIncoming(session),
          platform: DevicePlatform.current,
          onCancel: () => _confirmCancel(
            context,
            () => ref.read(receiveControllerProvider.notifier).cancel(id),
          ),
        );
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Transfer')),
      body: body,
    );
  }

  static Future<void> _confirmCancel(
    BuildContext context,
    Future<void> Function() cancel,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel the transfer?'),
        content: const Text(
          'Files that already arrived are kept. The rest stops and its '
          'unfinished parts are deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel transfer'),
          ),
        ],
      ),
    );
    if (ok ?? false) await cancel();
  }
}

class _Preparing extends StatelessWidget {
  const _Preparing({
    required this.text,
    required this.fraction,
    required this.onCancel,
  });

  final String text;
  final double? fraction;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(value: fraction),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
      ],
    ),
  );
}
