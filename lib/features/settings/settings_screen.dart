import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/protocol/device_name.dart';

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
                const SizedBox(height: 24),
                Text(
                  'Device ID ${device.deviceId.substring(0, 8)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}
