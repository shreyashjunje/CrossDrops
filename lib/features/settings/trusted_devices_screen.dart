import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/tokens.dart';
import '../../app/ui/ui.dart';
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
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(CdSpace.gutter),
                child: Text(
                  'None yet. When you accept files, tick "Trust this '
                  'device" to skip the code check next time.',
                  textAlign: TextAlign.center,
                  style: CdType.bodyM.copyWith(color: context.cd.text2),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                CdSpace.gutter,
                8,
                CdSpace.gutter,
                CdSpace.l,
              ),
              children: [
                Text(
                  'These phones skip the code check. You still tap Accept, '
                  'unless "Accept without asking" is on.',
                  style: CdType.bodyM.copyWith(color: context.cd.text2),
                ),
                const SizedBox(height: 16),
                for (final d in devices) _DeviceCard(device: d, repo: repo),
                const SizedBox(height: 8),
                Text(
                  'Accept without asking: files from that device are '
                  'saved without the Incoming request. Only for your own '
                  'phones.',
                  style: CdType.small.copyWith(color: context.cd.text3),
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
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: DeviceAvatar(name: d.name, platform: platform, size: 44),
            title: Text(d.name),
            subtitle: Text(
              '${platformLabel(platform)} · key ${shortFingerprint(d.fingerprint)}',
            ),
            trailing: IconButton(
              tooltip: 'Forget ${d.name}',
              icon: Icon(
                Icons.delete_outline_rounded,
                color: context.cd.danger,
              ),
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
          FilledButton(
            style: CdButtonStyles.secondary(context),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            style: CdButtonStyles.danger(context),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (ok ?? false) await repo.remove(device.fingerprint);
  }
}
