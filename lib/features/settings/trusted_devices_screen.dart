import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/security/device_identity.dart';
import '../../core/security/fingerprint.dart';
import '../../core/storage/trust_repository.dart';
import '../transfer/widgets.dart';

/// Trusted devices, with auto-accept and Forget. A device is listed by
/// name but known by its key, shown shortened under the name
/// (ARCHITECTURE.md, "Trust").
class TrustedDevicesScreen extends ConsumerWidget {
  const TrustedDevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(trustedDevicesProvider).value ?? const [];
    final repo = ref.read(trustRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Trusted devices')),
      body: devices.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'None yet. When you accept files, tick "Trust this '
                  'device" to skip the code check next time.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final d in devices) _DeviceCard(device: d, repo: repo),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Accept without asking: files from that device are '
                    'saved without the Incoming request. Only for your own '
                    'phones.',
                  ),
                ),
              ],
            ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.repo});

  final TrustedDevice device;
  final TrustRepository repo;

  @override
  Widget build(BuildContext context) {
    final d = device;
    final platform = DevicePlatform.tryParse(d.platform);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          ListTile(
            leading: PlatformIcon(platform: platform),
            title: Text(d.name),
            subtitle: Text(
              '${platformLabel(platform)} · key ${shortFingerprint(d.fingerprint)}',
            ),
            trailing: IconButton(
              tooltip: 'Forget ${d.name}',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _forget(context),
            ),
          ),
          SwitchListTile(
            title: const Text('Accept without asking'),
            value: d.autoAccept,
            onChanged: (v) => repo.setAutoAccept(d.fingerprint, v),
          ),
        ],
      ),
    );
  }

  Future<void> _forget(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Forget ${device.name}?'),
        content: const Text(
          'Its next transfer needs the code check and your Accept again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (ok ?? false) await repo.remove(device.fingerprint);
  }
}
