import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/client/peer_check.dart';
import '../../core/client/upload_client.dart';
import '../../core/discovery/peer_list.dart';
import '../../core/protocol/connect_payload.dart';
import '../../core/security/device_identity.dart';
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_message(e, fromQr: fromQr))));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  static String _message(UploadException e, {required bool fromQr}) =>
      switch (e.code) {
        'network' when fromQr =>
          'Could not connect. This Wi-Fi may block phone-to-phone traffic, '
              'or a VPN is on. Try a hotspot.',
        'network' =>
          'Could not reach that phone. Check that Receive is open on it and '
              'that both phones are on the same Wi-Fi.',
        'pin_mismatch' =>
          "This isn't the device you scanned: its security key is "
              'different. Nothing was sent.',
        'identity_mismatch' when fromQr =>
          "This isn't the device you scanned. Scan the code again.",
        'identity_mismatch' =>
          'A different device answered. Pull down to refresh the list.',
        'version' => 'Update CrossDrop on the other phone.',
        _ => 'The other phone gave an unexpected answer.',
      };

  Future<void> _scanQr() async {
    final payload = await Navigator.of(context).push<ConnectPayload>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (payload == null || !mounted) return;
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
            for (final p in peers)
              _PeerTile(
                peer: p,
                enabled: !_connecting && p.isSupported,
                onTap: () =>
                    _connect(() => _controller.connectToPeer(p), fromQr: false),
              ),
            if (peers.isEmpty) _EmptyState(searchedLong: state.searchedLong),
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
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: body,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _connecting ? null : _scanQr,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR code'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _connecting ? null : _enterAddress,
                  icon: const Icon(Icons.keyboard),
                  label: const Text('Enter IP'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    final icon = switch (peer.platform) {
      DevicePlatform.ios => Icons.phone_iphone,
      DevicePlatform.android => Icons.phone_android,
      null => Icons.device_unknown,
    };
    return ListTile(
      leading: Icon(icon, size: 36),
      title: Text(peer.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        peer.isSupported
            ? '${peer.host}:${peer.port}'
            : 'Needs a newer CrossDrop on this phone',
      ),
      enabled: enabled,
      onTap: onTap,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.searchedLong});

  final bool searchedLong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          if (!searchedLong) ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Looking for nearby phones…',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Open CrossDrop on the other phone and tap Receive.',
              textAlign: TextAlign.center,
            ),
          ] else ...[
            const Icon(Icons.search_off, size: 48),
            const SizedBox(height: 16),
            Text('No phones found yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Check that the other phone shows Receive and is on the same '
              'Wi-Fi. Some Wi-Fi networks hide phones from each other: scan '
              'the QR code on the other phone instead.',
              textAlign: TextAlign.center,
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: Icon(icon, color: scheme.onErrorContainer),
        title: Text(text, style: TextStyle(color: scheme.onErrorContainer)),
      ),
    );
  }
}
