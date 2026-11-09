import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/media_providers.dart';
import '../../app/navigation.dart';
import '../../core/log.dart';
import '../../platform/share_inbox.dart';
import '../transfer/unfinished_transfers.dart';
import 'send_screen.dart';
import 'send_controller.dart';

final shareInboxProvider = Provider<ShareInbox?>((ref) {
  if (Platform.isAndroid) {
    return AndroidShareInbox(ref.read(androidSourcesProvider));
  }
  if (Platform.isIOS) {
    return ref.watch(iosShareInboxProvider);
  }
  return null;
});

/// Opens the Send flow with files shared from another app preselected
/// (ARCHITECTURE.md, "Share from other apps").
class ShareListener extends ConsumerStatefulWidget {
  const ShareListener({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ShareListener> createState() => _ShareListenerState();
}

class _ShareListenerState extends ConsumerState<ShareListener>
    with WidgetsBindingObserver {
  StreamSubscription<void>? _sub;
  bool _taking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The iOS inbox exists once the app folders are known.
    ref.listenManual<ShareInbox?>(shareInboxProvider, (_, inbox) {
      _sub?.cancel();
      _sub = inbox?.arrivals.listen((_) => _take());
      // The app may have been started by a share.
      if (inbox != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _take());
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS: the Share Extension may have left files while the app was in
    // the background, without being able to open it.
    if (state == AppLifecycleState.resumed) _take();
  }

  Future<void> _take() async {
    final inbox = ref.read(shareInboxProvider);
    if (inbox == null || _taking) return;
    _taking = true;
    try {
      // The launch cleanup deletes staging folders that no unfinished send
      // uses. A share moved into staging before it ran would go with them
      // ("N files ready", then nothing to send; review H4).
      try {
        await ref.read(unfinishedTransfersProvider.future);
      } catch (_) {
        // The cleanup logs its own failures; take the share anyway.
      }
      if (!mounted) return;
      final shared = await inbox.takePending();
      if (!mounted || shared.isEmpty) return;
      _handle(shared);
    } catch (e) {
      logEvent('share', 'could not take shared files: ${e.runtimeType}');
    } finally {
      _taking = false;
    }
  }

  void _handle(SharedFiles shared) {
    final notes = <String>[
      if (shared.rejected > 0)
        '${shared.rejected} shared item(s) could not be used.',
      if (shared.truncated > 0)
        '${shared.truncated} item(s) left out: at most 10,000 at a time.',
    ];
    if (shared.files.isEmpty) {
      _snack(
        shared.textOnly
            ? 'CrossDrop sends files. Share a photo, video or file instead.'
            : notes.join(' '),
      );
      return;
    }
    final send = ref.read(sendControllerProvider);
    if (send.isRunning) {
      _snack('A send is still running. Share again when it has finished.');
      return;
    }
    ref.read(sendControllerProvider.notifier).addShared(shared.files);
    final top = topRouteObserver.top;
    final opened = top != Routes.nearby && top != Routes.send;
    if (opened) {
      // On top of whatever is open, so a running receive keeps going.
      // Straight to the radar: the files are already chosen (D-069).
      navigatorKey.currentState?.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: Routes.send),
          builder: (_) => const SendScreen(chooseOnOpen: true),
        ),
      );
    }
    final n = shared.files.length;
    final files = '$n ${n == 1 ? 'file' : 'files'}';
    _snack(
      [
        top == Routes.nearby || opened
            ? '$files ready. Tap the other phone.'
            : '$files ready. Tap Send to choose the phone.',
        ...notes,
      ].join(' '),
    );
  }

  void _snack(String text) {
    if (text.isEmpty) return;
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
