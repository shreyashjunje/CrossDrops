import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/media_providers.dart';
import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/tokens.dart';
import '../../app/ui/ui.dart';
import '../../core/client/peer_check.dart';
import '../../core/client/upload_client.dart';
import '../../core/discovery/peer_list.dart';
import '../../core/protocol/connect_payload.dart';
import '../../platform/haptics.dart';
import '../hotspot/hotspot_screens.dart';
import '../send/send_controller.dart';
import '../send/send_screen.dart';
import '../transfer/failure_messages.dart';
import 'find_help_screen.dart';
import 'local_network_denied_view.dart';
import 'lookalike_dialog.dart';
import 'manual_address_dialog.dart';
import 'nearby_controller.dart';
import 'qr_scan_screen.dart';
import 'radar.dart';

/// Pick who to send to: nearby devices on a radar, a QR code, or a typed
/// address (D-069). Tapping a phone locks on to it while it is checked,
/// then pops with the checked [ConnectTarget].
class NearbyScreen extends ConsumerStatefulWidget {
  const NearbyScreen({super.key});

  @override
  ConsumerState<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends ConsumerState<NearbyScreen> {
  bool _connecting = false;

  /// The phone being checked, shown locked on the radar.
  String? _lockedId;

  /// A QR code or typed address did not answer (network error).
  bool _addressUnreachable = false;

  NearbyController get _controller =>
      ref.read(nearbyControllerProvider.notifier);

  /// Runs a peer check, then returns the target to the Send screen.
  Future<void> _connect(
    Future<ConnectTarget> Function() check, {
    required bool fromQr,
    String? lockId,
  }) async {
    if (_connecting) return;
    setState(() {
      _connecting = true;
      _lockedId = lockId;
    });
    if (lockId != null) ref.read(hapticsProvider).play(HapticMoment.lockOn);
    try {
      final target = await check();
      if (!mounted) return;
      if (!await confirmLookalike(context, target) || !mounted) return;
      Navigator.of(context).pop(target);
    } on UploadException catch (e) {
      if (!mounted) return;
      if (e.code == 'network' && !_addressUnreachable) {
        setState(() => _addressUnreachable = true);
      }
      ref.read(hapticsProvider).play(HapticMoment.failed);
      _showError(describeConnectError(e.code, fromQr: fromQr));
    } finally {
      if (mounted) {
        setState(() {
          _connecting = false;
          _lockedId = null;
        });
      }
    }
  }

  void _showError(FailureMessage m) {
    final (label, run) = switch (m.action) {
      NextAction.scanQr => ('Scan QR', _scanQr),
      NextAction.findHelp => ('Help', _openHelp),
      _ => (null, null),
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text('${m.title}. ${m.reason} ${m.next}'),
        action: label == null
            ? null
            : SnackBarAction(label: label, onPressed: run!),
      ),
    );
  }

  Future<void> _openHelp() async {
    final result = await pushScreen<FindHelpResult>(
      context,
      Routes.findHelp,
      const FindHelpScreen(),
    );
    if (result == FindHelpResult.scanQr && mounted) await _scanQr();
  }

  Future<void> _scanQr() async {
    final payload = await Navigator.of(context).push<ConnectPayload>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (payload == null || !mounted) return;
    // An Android hotspot code: join its network first (D-055).
    if (payload.wifi != null && Platform.isIOS) {
      final joined = await pushScreen<bool>(
        context,
        Routes.hotspot,
        JoinHotspotScreen(payload: payload, popWhenConnected: true),
      );
      if (joined != true || !mounted) return;
    }
    await _connect(() => _controller.connectToQr(payload), fromQr: true);
  }

  Future<void> _enterAddress() async {
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (_) => const ManualAddressDialog(),
    );
    if (result == null || !mounted) return;
    final (host, port) = result;
    await _connect(
      () => _controller.connectToAddress(host, port),
      fromQr: false,
    );
  }

  void _tapPeer(Peer p) => _connect(
    () => _controller.connectToPeer(p),
    fromQr: false,
    lockId: p.deviceId,
  );

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final state = ref.watch(nearbyControllerProvider);
    final peers = state.sortedPeers;
    // A new phone on the radar: a light tick (throttled in Haptics).
    ref.listen(nearbyControllerProvider.select((s) => s.peers.length), (
      was,
      now,
    ) {
      if (now > (was ?? 0)) {
        ref.read(hapticsProvider).play(HapticMoment.deviceFound);
      }
    });
    final picked = ref.watch(sendControllerProvider.select((s) => s.picked));

    final Widget body;
    if (state.permissionDenied) {
      body = LocalNetworkDeniedView(
        onOpenSettings: () => ref.read(localNetworkProvider).openSettings(),
        onRetry: _controller.refresh,
        onScanQr: _scanQr,
      );
    } else {
      final noneYet = peers.isEmpty;
      final asList = useRadarList(context);
      final radarPeers = [
        for (final p in peers)
          RadarPeer(
            id: p.deviceId,
            name: p.name,
            platform: p.platform,
            hint: p.isSupported
                ? _capitalised(connectionHint(p.host))
                : 'Needs an update',
            enabled: p.isSupported && !_connecting,
          ),
      ];
      body = RefreshIndicator(
        onRefresh: _controller.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            CdSpace.gutter,
            4,
            CdSpace.gutter,
            CdSpace.l,
          ),
          children: [
            Text(
              noneYet && state.searchedLong
                  ? 'No phones found yet'
                  : 'Tap the other phone',
              style: CdType.h1.copyWith(color: c.text),
            ),
            const SizedBox(height: 6),
            Text(
              picked.isEmpty
                  ? 'Phones with CrossDrop open show up here.'
                  : 'Sending ${summarizePicked(picked)}',
              style: CdType.bodyM.copyWith(color: c.text2),
            ),
            if (!state.hasNetwork) ...[
              const SizedBox(height: 16),
              const NoticeCard(
                tone: NoticeTone.warning,
                icon: Icons.signal_wifi_off_rounded,
                title: 'Not on Wi-Fi',
                text:
                    'Join the same Wi-Fi as the other phone. No Wi-Fi around? '
                    'Use hotspot mode: one phone makes a network for the other.',
              ),
            ],
            if (state.error != null) ...[
              const SizedBox(height: 16),
              NoticeCard(
                tone: NoticeTone.danger,
                icon: Icons.error_outline_rounded,
                text: state.error!,
              ),
            ],
            const SizedBox(height: 20),
            if (asList)
              for (final p in radarPeers)
                _PeerCard(
                  peer: p,
                  locked: p.id == _lockedId,
                  onTap: p.enabled
                      ? () => _tapPeer(
                          peers.firstWhere((x) => x.deviceId == p.id),
                        )
                      : null,
                )
            else ...[
              Radar(
                peers: radarPeers,
                searching: state.searching,
                lockedId: _lockedId,
                onTap: (p) =>
                    _tapPeer(peers.firstWhere((x) => x.deviceId == p.id)),
              ),
              // More phones than the radar has room for.
              for (final p in radarPeers.skip(radarSlots))
                _PeerCard(
                  peer: p,
                  locked: p.id == _lockedId,
                  onTap: p.enabled
                      ? () => _tapPeer(
                          peers.firstWhere((x) => x.deviceId == p.id),
                        )
                      : null,
                ),
            ],
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                _statusLine(peers.length, state.searchedLong),
                textAlign: TextAlign.center,
                style: CdType.bodyM.copyWith(color: c.text2),
              ),
            ),
            if (noneYet && state.searchedLong) ...[
              const SizedBox(height: 16),
              const NoticeCard(
                icon: Icons.phone_android_rounded,
                title: 'Open CrossDrop on the other phone',
                text:
                    'It must show "Ready to receive". Some Wi-Fi networks hide '
                    'phones from each other: the QR code gets around that.',
              ),
            ],
            if (suggestHotspot(
              searchedLong: state.searchedLong,
              peerCount: peers.length,
              addressUnreachable: _addressUnreachable,
            )) ...[
              const SizedBox(height: 16),
              HotspotSuggestion(
                onOpen: () => pushScreen<void>(
                  context,
                  Routes.hotspot,
                  const HotspotModeScreen(),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          TextButton.icon(
            onPressed: _connecting ? null : _scanQr,
            style: TextButton.styleFrom(foregroundColor: c.text),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Scan QR'),
          ),
          IconButton(
            tooltip: 'Search again',
            onPressed: _controller.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: _connecting
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(semanticsLabel: 'Connecting'),
              )
            : null,
      ),
      body: body,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            CdSpace.gutter,
            8,
            CdSpace.gutter,
            12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                style: CdButtonStyles.wide,
                onPressed: _openHelp,
                icon: const Icon(Icons.help_outline_rounded),
                label: const Text("Can't find the other phone?"),
              ),
              TextButton(
                onPressed: _connecting ? null : _enterAddress,
                child: const Text('Type the address instead'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _statusLine(int found, bool searchedLong) {
    if (found == 0) {
      return searchedLong
          ? 'Still looking on this network…'
          : 'Looking for nearby phones…';
    }
    final phones = found == 1 ? '1 phone' : '$found phones';
    return '$phones found · still looking';
  }

  static String _capitalised(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// How this phone reaches [host]: iPhone Personal Hotspot hands out
/// 172.20.10.x; anything else found by discovery is on the same network.
String connectionHint(String host) =>
    host.startsWith('172.20.10.') ? 'via iPhone hotspot' : 'same Wi-Fi';

/// A phone in the list fallback (large text, screen readers, or more
/// phones than the radar holds).
class _PeerCard extends StatelessWidget {
  const _PeerCard({required this.peer, required this.locked, this.onTap});

  final RadarPeer peer;
  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final platform = switch (peer.platform) {
      null => 'Unknown phone',
      final p => p.name == 'ios' ? 'iPhone' : 'Android',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: locked ? c.accentSoft : c.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CdRadius.button),
          side: BorderSide(color: locked ? c.accent : c.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                DeviceAvatar(
                  name: peer.name,
                  platform: peer.platform,
                  size: 44,
                  locked: locked,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        peer.name,
                        style: CdType.titleM.copyWith(color: c.text),
                      ),
                      Text(
                        locked ? 'Connecting…' : '$platform · ${peer.hint}',
                        style: CdType.small.copyWith(color: c.text2),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.text3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
