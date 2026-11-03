import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../core/server/receive_server.dart';
import '../transfer/transfer_screen.dart';
import 'incoming_request_screen.dart';
import 'receive_controller.dart';

/// Receiving may start: false until onboarding has explained the Local
/// Network permission, so its iOS prompt comes right after (D-050).
final receiveAllowedProvider = Provider<bool>(
  (ref) => ref.watch(onboardingDoneProvider).value ?? false,
);

/// What screens show about receiving. Use this, not
/// [receiveControllerProvider], in widgets: watching the controller starts
/// the server, which must wait for [receiveAllowedProvider].
final receiveStateProvider = Provider.autoDispose<ReceiveState>(
  (ref) => ref.watch(receiveAllowedProvider)
      ? ref.watch(receiveControllerProvider)
      : const ReceiveState(),
);

/// Keeps receiving running wherever the user is in the app (D-046), and
/// shows each incoming offer on top of whatever is open. Sits above the
/// navigator.
class ReceiveHost extends ConsumerStatefulWidget {
  const ReceiveHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ReceiveHost> createState() => _ReceiveHostState();
}

class _ReceiveHostState extends ConsumerState<ReceiveHost> {
  ProviderSubscription<ReceiveState>? _sub;

  /// Session whose prompt is open.
  String? _prompting;

  @override
  void initState() {
    super.initState();
    ref.listenManual<bool>(receiveAllowedProvider, (_, allowed) {
      if (allowed && _sub == null) {
        _sub = ref.listenManual(
          receiveControllerProvider,
          _onState,
          fireImmediately: true,
        );
      } else if (!allowed) {
        _sub?.close();
        _sub = null;
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _sub?.close();
    super.dispose();
  }

  void _onState(ReceiveState? prev, ReceiveState next) {
    if (prev?.pendingOffers != next.pendingOffers) {
      // After this frame: a listener may not push routes while building.
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybePrompt());
    }
    final notice = next.notice;
    if (notice != null && prev?.notice != notice) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(notice)),
      );
      ref.read(receiveControllerProvider.notifier).clearNotice();
    }
  }

  Future<void> _maybePrompt() async {
    final navigator = navigatorKey.currentState;
    if (!mounted || navigator == null) return;
    final pending = ref.read(receiveControllerProvider).pendingOffers;
    final open = _prompting;
    if (open != null) {
      // The offer timed out or was withdrawn while the prompt was open.
      if (!pending.any((o) => o.sessionId == open)) {
        _prompting = null;
        navigator.popUntil((r) => r.settings.name != Routes.incoming);
      }
      return;
    }
    if (pending.isEmpty) return;
    final offer = pending.first;
    _prompting = offer.sessionId;
    final decision = await _ask(navigator, offer);
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
        if (decision.accept) {
          unawaited(
            navigator.push(
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: Routes.transfer),
                builder: (_) =>
                    TransferScreen(receiveSessionId: offer.sessionId),
              ),
            ),
          );
        }
      }
    }
    // Another offer may be waiting.
    await _maybePrompt();
  }

  Future<AcceptDecision?> _ask(NavigatorState navigator, IncomingOffer offer) =>
      navigator.push<AcceptDecision>(
        MaterialPageRoute(
          settings: const RouteSettings(name: Routes.incoming),
          fullscreenDialog: true,
          builder: (_) => IncomingRequestScreen(offer: offer),
        ),
      );

  @override
  Widget build(BuildContext context) => widget.child;
}
