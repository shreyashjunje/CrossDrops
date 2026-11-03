import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/media_providers.dart';
import '../../core/log.dart';
import '../../platform/share_inbox.dart';
import '../nearby/nearby_screen.dart';
import 'send_controller.dart';

/// The app's navigator and snack bars, for events that start outside any
/// screen (a share from another app).
final navigatorKey = GlobalKey<NavigatorState>();
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Route names, so a share does not open a second Send flow.
abstract final class Routes {
  static const nearby = 'nearby';
  static const send = 'send';
}

/// Tracks the top route's name.
class TopRouteObserver extends NavigatorObserver {
  final List<String?> _stack = [];

  String? get top => _stack.isEmpty ? null : _stack.last;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _stack.add(route.settings.name);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_stack.isNotEmpty) _stack.removeLast();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final i = _stack.lastIndexOf(route.settings.name);
    if (i >= 0) _stack.removeAt(i);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (_stack.isNotEmpty) _stack.removeLast();
    _stack.add(newRoute?.settings.name);
  }
}

final topRouteObserver = TopRouteObserver();

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
    if (top != Routes.nearby && top != Routes.send) {
      // On top of whatever is open, so a running receive keeps going.
      navigatorKey.currentState?.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: Routes.nearby),
          builder: (_) => const NearbyScreen(),
        ),
      );
    }
    final n = shared.files.length;
    _snack(
      [
        '$n ${n == 1 ? 'file' : 'files'} ready. Choose the phone to send to.',
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
