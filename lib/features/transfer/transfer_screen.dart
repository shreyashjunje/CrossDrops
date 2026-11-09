import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/media_providers.dart';
import '../../app/navigation.dart';
import '../../app/tokens.dart';
import '../../app/ui/ui.dart';
import '../../platform/haptics.dart';
import '../../core/media/prepare.dart';
import '../../core/media/save_target.dart';
import '../../core/security/device_identity.dart';
import '../receive/receive_controller.dart';
import '../receive/receive_host.dart';
import '../send/send_controller.dart';
import '../send/send_screen.dart';
import 'failure_messages.dart';
import 'progress_view.dart';
import 'result_view.dart';
import 'skipped_notice.dart';
import 'transfer_format.dart';
import 'transfer_view.dart';

/// One transfer: progress while it runs, then Done or Failed. With no
/// [receiveSessionId] it shows this phone's send.
class TransferScreen extends ConsumerWidget {
  const TransferScreen({super.key, this.receiveSessionId});

  final String? receiveSessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = receiveSessionId;
    _listenForHaptics(ref, id);
    final Widget body;
    if (id == null) {
      final s = ref.watch(sendControllerProvider);
      final view = TransferView.fromSend(
        s.snapshot,
        peerName: s.receiverName ?? 'the other phone',
        peerPlatform: s.receiver?.platform,
        pausedByUser: s.pausedByUser,
        items: s.items,
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
      } else if (view == null && !s.isRunning) {
        body = _NotSent(
          message: s.error ?? 'Nothing was sent.',
          onBack: () => Navigator.of(context).pop(),
        );
      } else if (view == null) {
        body = const Center(child: CircularProgressIndicator());
      } else if (view.stage.isFinished) {
        body = ResultView(
          view: view,
          platform: DevicePlatform.current,
          onAction: (a) => _act(context, ref, a),
          onTrust: s.canTrustReceiver ? send.trustReceiver : null,
          onClose: () => _close(context),
        );
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
      } else if (TransferView.fromIncoming(session) case final view
          when view.stage.isFinished) {
        body = ResultView(
          view: view,
          platform: DevicePlatform.current,
          onOpen: (f) => _open(context, ref, f),
          onAction: (a) => _act(context, ref, a),
          onClose: () => _close(context),
        );
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
    final skipped = id == null
        ? ref.watch(sendControllerProvider.select((s) => s.skipped))
        : const <SkippedItem>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Transfer')),
      body: skipped.isEmpty
          ? body
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: SkippedNotice(skipped),
                ),
                Expanded(child: body),
              ],
            ),
    );
  }

  /// Accepted (sender), done and failed get a haptic (D-069).
  static void _listenForHaptics(WidgetRef ref, String? id) {
    void play(TransferStage? was, TransferStage? now, {required bool sending}) {
      if (now == null || now == was) return;
      final haptics = ref.read(hapticsProvider);
      if (sending &&
          now == TransferStage.running &&
          was == TransferStage.waiting) {
        haptics.play(HapticMoment.accepted);
      } else if (now == TransferStage.done) {
        haptics.play(HapticMoment.done);
      } else if (now == TransferStage.failed || now == TransferStage.rejected) {
        haptics.play(HapticMoment.failed);
      }
    }

    if (id == null) {
      ref.listen<TransferStage?>(
        sendControllerProvider.select(
          (s) => TransferView.fromSend(s.snapshot, peerName: '')?.stage,
        ),
        (was, now) => play(was, now, sending: true),
      );
    } else {
      ref.listen<TransferStage?>(
        receiveStateProvider.select((s) {
          final session = s.sessions[id];
          return session == null
              ? null
              : TransferView.fromIncoming(session).stage;
        }),
        (was, now) => play(was, now, sending: false),
      );
    }
  }

  static void _close(BuildContext context) =>
      Navigator.of(context).popUntil((r) => r.isFirst);

  static Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    TransferFileView file,
  ) async {
    final location = file.location;
    if (location == null) return;
    final messenger = ScaffoldMessenger.of(context);
    if (await ref.read(fileOpenerProvider).open(location)) return;
    final where = formatSavedTo(
      file.savedTo ?? SaveCollection.files,
      null,
      platform: DevicePlatform.current,
    );
    messenger.showSnackBar(
      SnackBar(content: Text('Could not open it here. $where.')),
    );
  }

  /// The button under a failure: the next step from the failure table.
  static void _act(BuildContext context, WidgetRef ref, NextAction action) {
    final navigator = Navigator.of(context);
    switch (action) {
      case NextAction.resume:
        ref.read(sendControllerProvider.notifier).resume();
      case NextAction.sendAgain:
      case NextAction.scanQr:
      case NextAction.findHelp:
        navigator.popUntil((r) => r.isFirst);
        navigator.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: Routes.send),
            builder: (_) => const SendScreen(),
          ),
        );
      case NextAction.none:
        break;
    }
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
          FilledButton(
            style: CdButtonStyles.secondary(context),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep going'),
          ),
          OutlinedButton(
            style: CdButtonStyles.danger(context),
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
  Widget build(BuildContext context) {
    final c = context.cd;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(CdSpace.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Center(
              child: fraction == null
                  ? SizedBox.square(
                      dimension: 72,
                      child: CircularProgressIndicator(
                        strokeWidth: 6,
                        color: c.accentInk,
                        backgroundColor: c.surface3,
                      ),
                    )
                  : ProgressRing(value: fraction!, size: 72, stroke: 6),
            ),
            const SizedBox(height: 24),
            Text(
              'Getting the files ready',
              textAlign: TextAlign.center,
              style: CdType.h2.copyWith(color: c.text),
            ),
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: CdType.bodyM.copyWith(color: c.text2),
              ),
            ),
            const SizedBox(height: 16),
            const NoticeCard(
              icon: Icons.cloud_download_outlined,
              text:
                  'Photos kept only in iCloud download first, in full '
                  'quality. Keep this screen open.',
            ),
            const Spacer(),
            OutlinedButton(
              style: CdButtonStyles.danger(context).merge(CdButtonStyles.wide),
              onPressed: onCancel,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotSent extends StatelessWidget {
  const _NotSent({required this.message, required this.onBack});

  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(CdSpace.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(CdRadius.card),
                  border: Border.all(color: c.line),
                ),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 32,
                  color: c.text2,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: CdType.h3.copyWith(color: c.text),
            ),
            const Spacer(),
            FilledButton(
              style: CdButtonStyles.wide,
              onPressed: onBack,
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}
