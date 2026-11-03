import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../core/client/peer_check.dart';
import '../../core/client/upload_client.dart';
import '../../core/discovery/peer_list.dart';
import '../../core/protocol/connect_payload.dart';
import '../hotspot/hotspot_screens.dart';
import '../transfer/failure_messages.dart';
import '../transfer/widgets.dart';
import 'find_help_screen.dart';
import 'local_network_denied_view.dart';
import 'lookalike_dialog.dart';
import 'manual_address_dialog.dart';
import 'nearby_controller.dart';
import 'qr_scan_screen.dart';

/// Pick who to send to: nearby devices, a QR code, or a typed address.
/// Pops with the checked [ConnectTarget].
class NearbyScreen extends ConsumerStatefulWidget {
  const NearbyScreen({super.key});

  @override
  ConsumerState<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends ConsumerState<NearbyScreen> {
  bool _connecting = false;

  /// A QR code or typed address did not answer (network error).
  bool _addressUnreachable = false;

  NearbyController get _controller =>
      ref.read(nearbyControllerProvider.notifier);

  /// Runs a peer check, then returns the target to the Send screen.
  Future<void> _connect(
    Future<ConnectTarget> Function() check, {
    required bool fromQr,
  }) async {
    if (_connecting) return;
    setState(() => _connecting = true);
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
      _showError(describeConnectError(e.code, fromQr: fromQr));
    } finally {
      if (mounted) setState(() => _connecting = false);
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(nearbyControllerProvider);
    final peers = state.sortedPeers;

    final Widget body;
    if (state.permissionDenied) {
      body = LocalNetworkDeniedView(
        onOpenSettings: () => ref.read(localNetworkProvider).openSettings(),
        onRetry: _controller.refresh,
        onScanQr: _scanQr,
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _controller.refresh,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            if (!state.hasNetwork)
              const _Banner(
                icon: Icons.signal_wifi_off,
                text:
                    'Not connected to Wi-Fi or a hotspot. Join the same '
                    'network as the other phone.',
              ),
            if (state.error != null)
              _Banner(icon: Icons.error_outline, text: state.error!),
            if (suggestHotspot(
              searchedLong: state.searchedLong,
              peerCount: peers.length,
              addressUnreachable: _addressUnreachable,
            ))
              HotspotSuggestion(
                onOpen: () => pushScreen<void>(
                  context,
                  Routes.hotspot,
                  const HotspotModeScreen(),
                ),
              ),
            for (final p in peers)
              _PeerTile(
                peer: p,
                enabled: !_connecting && p.isSupported,
                onTap: () =>
                    _connect(() => _controller.connectToPeer(p), fromQr: false),
              ),
            if (peers.isEmpty)
              _EmptyState(searchedLong: state.searchedLong, onHelp: _openHelp),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Send to'),
        actions: [
          IconButton(
            tooltip: 'Search again',
            onPressed: _controller.refresh,
            icon: const Icon(Icons.refresh),
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _connecting ? null : _scanQr,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan QR code'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _connecting ? null : _enterAddress,
                    icon: const Icon(Icons.keyboard),
                    label: const Text('Enter IP'),
                  ),
                ],
              ),
              TextButton(
                onPressed: _openHelp,
                child: const Text("Can't find the other phone?"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How this phone reaches [host]: iPhone Personal Hotspot hands out
/// 172.20.10.x; anything else found by discovery is on the same network.
String connectionHint(String host) =>
    host.startsWith('172.20.10.') ? 'via iPhone hotspot' : 'same Wi-Fi';

class _PeerTile extends StatelessWidget {
  const _PeerTile({
    required this.peer,
    required this.enabled,
    required this.onTap,
  });

  final Peer peer;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: PlatformIcon(platform: peer.platform, size: 40),
        title: Text(peer.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          peer.isSupported
              ? '${platformLabel(peer.platform)} · '
                    '${connectionHint(peer.host)}'
              : 'Needs a newer CrossDrop on this phone',
        ),
        trailing: const Icon(Icons.chevron_right),
        enabled: enabled,
        onTap: onTap,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.searchedLong, required this.onHelp});

  final bool searchedLong;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          if (!searchedLong) ...[
            const CircularProgressIndicator(
              semanticsLabel: 'Looking for nearby phones',
            ),
            const SizedBox(height: 16),
            Text(
              'Looking for nearby phones…',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Open CrossDrop on the other phone. It must show "Ready to '
              'receive".',
              textAlign: TextAlign.center,
            ),
          ] else ...[
            const Icon(Icons.search_off, size: 48),
            const SizedBox(height: 16),
            Text('No phones found yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Some Wi-Fi networks hide phones from each other. Scan the QR '
              'code on the other phone, or use hotspot mode.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onHelp,
              child: const Text("Can't find the other phone?"),
            ),
          ],
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: WarningBox(icon: icon, text: text),
  );
}
