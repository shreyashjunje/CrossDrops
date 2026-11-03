import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/keep_alive.dart';
import '../../app/providers.dart';
import 'receive_host.dart';

/// This phone's QR code, for a sender whose nearby list does not show it
/// (ARCHITECTURE.md, "QR code payload"). The screen stays on while it is
/// open, so the code stays scannable.
class MyQrScreen extends ConsumerStatefulWidget {
  const MyQrScreen({super.key});

  @override
  ConsumerState<MyQrScreen> createState() => _MyQrScreenState();
}

class _MyQrScreenState extends ConsumerState<MyQrScreen> {
  final Object _screenKey = Object();

  // Read once: ref may not be used in dispose.
  late final KeepAliveCoordinator _keepAlive = ref.read(keepAliveProvider);

  @override
  void initState() {
    super.initState();
    _keepAlive.holdScreen(_screenKey);
  }

  @override
  void dispose() {
    _keepAlive.releaseScreen(_screenKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(receiveStateProvider);
    final theme = Theme.of(context);
    final payload = state.qrPayload;
    final Widget body;
    if (state.receivingOff) {
      body = const _Message(
        'Receiving is off. Turn it on on the home screen to show a code.',
      );
    } else if (state.port == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (payload == null) {
      body = const _Message(
        'This phone is not on Wi-Fi or a hotspot. Join the same network as '
        'the other phone, then come back.',
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'On the other phone, open CrossDrop, tap Send, then Scan QR code.',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Center(
            child: Container(
              // White in dark mode too, so cameras can read it.
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: QrImageView(
                data: payload,
                size: 240,
                semanticsLabel:
                    'QR code to connect to ${state.deviceName ?? 'this phone'}',
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            state.deviceName ?? '',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ExpansionTile(
            title: const Text('No camera? Type the address'),
            childrenPadding: const EdgeInsets.only(bottom: 16),
            children: [
              for (final a in state.addresses)
                SelectableText(
                  '${a.ip}  (${a.interfaceName})',
                  style: theme.textTheme.titleMedium,
                ),
              SelectableText(
                'Port ${state.port}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'On the other phone: Send, then Enter IP. The address changes '
                'each time CrossDrop restarts.',
              ),
            ],
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('My QR code')),
      body: body,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ),
  );
}
