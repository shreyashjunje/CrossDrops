import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../nearby/nearby_screen.dart';
import '../receive/receive_screen.dart';
import '../../app/navigation.dart';
import '../settings/settings_screen.dart';
import '../transfer/unfinished_transfers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _askedAboutUnfinished = false;

  void _open(Widget screen, {String? name}) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: RouteSettings(name: name),
      builder: (_) => screen,
    ),
  );

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
    final name = ref.watch(identityProvider).value?.deviceName;
    // Creates the key pair and certificate on first launch, before the
    // user needs them (ARCHITECTURE.md, "Device identity").
    ref.watch(credentialsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('CrossDrop'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => _open(const SettingsScreen()),
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (name != null) ...[
              Text(
                'This phone: $name',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
            ],
            FilledButton(
              onPressed: () => _open(const ReceiveScreen()),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Receive'),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => _open(const NearbyScreen(), name: Routes.nearby),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Send'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
