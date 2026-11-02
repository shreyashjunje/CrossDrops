import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../nearby/nearby_screen.dart';
import '../receive/receive_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void open(Widget screen) =>
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => screen));
    final name = ref.watch(identityProvider).value?.deviceName;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CrossDrop'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => open(const SettingsScreen()),
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
              onPressed: () => open(const ReceiveScreen()),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Receive'),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => open(const NearbyScreen()),
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
