import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/protocol/device_name.dart';
import '../../core/security/fingerprint.dart';
import '../../core/storage/trust_repository.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _name = TextEditingController();
  bool _loaded = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final clean = sanitizeDeviceName(_name.text);
    if (clean.isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    await ref.read(identityProvider.notifier).rename(clean);
    if (!mounted) return;
    _name.text = clean;
    setState(() => _error = null);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Name saved')));
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(identityProvider);
    final device = identity.value;
    if (device != null && !_loaded) {
      _loaded = true;
      _name.text = device.deviceName;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: device == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: 'Device name',
                    helperText: 'Other phones on the same Wi-Fi see this name.',
                    errorText: _error,
                  ),
                  maxLength: maxDeviceNameBytes,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 8),
                FilledButton(onPressed: _save, child: const Text('Save')),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Receiving'),
                  subtitle: const Text(
                    'Off: this phone is hidden and refuses transfers from '
                    'devices you have not trusted.',
                  ),
                  value: ref.watch(receivingEnabledProvider).value ?? true,
                  onChanged: (on) => ref
                      .read(settingsRepositoryProvider)
                      .setReceivingEnabled(on),
                ),
                const SizedBox(height: 16),
                Text(
                  'Trusted devices',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const _TrustedDevices(),
                const SizedBox(height: 24),
                Text(
                  'Device ID ${device.deviceId.substring(0, 8)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (ref.watch(credentialsProvider).value?.fingerprint
                    case final fp?)
                  Text(
                    'Security key ${shortFingerprint(fp)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
    );
  }
}

/// Trusted devices with their auto-accept switch. A device is listed by
/// name, but known by its key, shown shortened under the name.
class _TrustedDevices extends ConsumerWidget {
  const _TrustedDevices();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(trustedDevicesProvider).value ?? const [];
    if (devices.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'None yet. After a transfer, choose "Trust this device" to skip '
          'the code check next time.',
        ),
      );
    }
    final repo = ref.read(trustRepositoryProvider);
    return Column(
      children: [
        for (final d in devices)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              d.platform == 'ios' ? Icons.phone_iphone : Icons.phone_android,
            ),
            title: Text(d.name),
            subtitle: Text(shortFingerprint(d.fingerprint)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: 'Accept files without asking',
                  child: Switch(
                    value: d.autoAccept,
                    onChanged: (v) => repo.setAutoAccept(d.fingerprint, v),
                  ),
                ),
                IconButton(
                  tooltip: 'Forget',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _forget(context, repo, d),
                ),
              ],
            ),
          ),
        const Text(
          'Auto-accept: files from that device are saved without the Accept '
          'prompt.',
        ),
      ],
    );
  }

  static Future<void> _forget(
    BuildContext context,
    TrustRepository repo,
    TrustedDevice d,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Forget ${d.name}?'),
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
    if (ok ?? false) await repo.remove(d.fingerprint);
  }
}
