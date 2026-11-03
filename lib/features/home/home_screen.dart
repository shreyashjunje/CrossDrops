import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../nearby/nearby_screen.dart';
import '../receive/my_qr_screen.dart';
import '../settings/settings_screen.dart';
import '../transfer/unfinished_transfers.dart';
import 'active_transfers.dart';
import 'receive_status_card.dart';

/// "Ready to receive" with this phone's name and the Receiving switch, the
/// transfers in progress, and one large Send button.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _askedAboutUnfinished = false;

  @override
  Widget build(BuildContext context) {
    // Once per launch: offer to resume what an earlier run left unfinished.
    ref.listen(unfinishedTransfersProvider, (_, next) {
      final sessions = next.value;
      if (_askedAboutUnfinished || sessions == null || sessions.isEmpty) {
        return;
      }
      _askedAboutUnfinished = true;
      showDialog<void>(
        context: context,
        builder: (_) => UnfinishedTransfersDialog(sessions: sessions),
      );
    });
    // Creates the key pair and certificate on first launch, before the
    // user needs them (ARCHITECTURE.md, "Device identity").
    ref.watch(credentialsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('CrossDrop'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => pushScreen<void>(
              context,
              Routes.settings,
              const SettingsScreen(),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ReceiveStatusCard(
                    onShowQr: () => pushScreen<void>(
                      context,
                      Routes.myQr,
                      const MyQrScreen(),
                    ),
                  ),
                  const ActiveTransfers(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: _SendButton(
                onPressed: () => pushScreen<void>(
                  context,
                  Routes.nearby,
                  const NearbyScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.headlineSmall;
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(72),
        textStyle: text,
      ),
      icon: const Icon(Icons.send, size: 28),
      label: const Text('Send'),
    );
  }
}
