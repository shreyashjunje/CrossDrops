import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/tokens.dart';
import '../../core/bench/bench.dart';
import '../../core/protocol/device_name.dart';
import '../../core/security/device_identity.dart';
import '../bench/bench_screen.dart';
import '../nearby/find_help_screen.dart';
import '../onboarding/onboarding_screen.dart';
import 'about_screen.dart';
import 'trusted_devices_screen.dart';

/// Device name, the Receiving setting, photo formats (iPhone), trusted
/// devices, help and About (docs/features/settings.md).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.platform});

  /// This phone; defaults to the real platform. Set in tests.
  final DevicePlatform? platform;

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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Name saved. Other phones see it the next time they '
          'search.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(identityProvider).value;
    if (device != null && !_loaded) {
      _loaded = true;
      _name.text = device.deviceName;
    }
    final me = widget.platform ?? DevicePlatform.current;
    final trusted = ref.watch(trustedDevicesProvider).value?.length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: device == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                CdSpace.gutter,
                0,
                CdSpace.gutter,
                CdSpace.l,
              ),
              children: [
                const _Header('This phone'),
                _Group(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: TextField(
                        controller: _name,
                        decoration: InputDecoration(
                          labelText: 'Device name',
                          helperText: 'Other phones see this name.',
                          errorText: _error,
                          suffixIcon: IconButton(
                            tooltip: 'Save name',
                            icon: const Icon(Icons.check),
                            onPressed: _save,
                          ),
                        ),
                        maxLength: maxDeviceNameBytes,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _save(),
                      ),
                    ),
                  ],
                ),
                const _Header('Receiving'),
                _Group(
                  children: [
                    SwitchListTile(
                      title: const Text(
                        'Ready to receive when CrossDrop is open',
                      ),
                      subtitle: const Text(
                        'Off: this phone is hidden from other phones and refuses '
                        'files from devices you have not trusted. Same as the '
                        'switch on the home screen.',
                      ),
                      value: ref.watch(receivingEnabledProvider).value ?? true,
                      onChanged: (on) => ref
                          .read(settingsRepositoryProvider)
                          .setReceivingEnabled(on),
                    ),
                  ],
                ),
                if (me == DevicePlatform.ios) const _FormatSettings(),
                const _Header('Security'),
                _Group(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.verified_user_outlined),
                      title: const Text('Trusted devices'),
                      subtitle: Text(
                        trusted == 0
                            ? 'None'
                            : '$trusted ${trusted == 1 ? 'device' : 'devices'}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => pushScreen<void>(
                        context,
                        Routes.settings,
                        const TrustedDevicesScreen(),
                      ),
                    ),
                  ],
                ),
                const _Header('Help'),
                _Group(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.help_outline),
                      title: const Text("Can't find the other phone?"),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => pushScreen<void>(
                        context,
                        Routes.findHelp,
                        FindHelpScreen(platform: me),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.school_outlined),
                      title: const Text('Show the introduction'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => pushScreen<void>(
                        context,
                        Routes.settings,
                        OnboardingScreen(replay: true, platform: me),
                      ),
                    ),
                    if (benchBuild)
                      ListTile(
                        leading: const Icon(Icons.speed),
                        title: const Text('Benchmark (test build)'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => pushScreen<void>(
                          context,
                          Routes.settings,
                          const BenchScreen(),
                        ),
                      ),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('About CrossDrop'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => pushScreen<void>(
                        context,
                        Routes.settings,
                        const AboutScreen(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// A settings section: one card, rows split by hairlines.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return Container(
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: BorderRadius.circular(CdRadius.button),
        border: Border.all(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, child) in children.indexed) ...[
              if (i > 0) Divider(height: 1, color: c.line),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
    child: Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        semanticsLabel: text,
        style: CdType.overline.copyWith(color: context.cd.text2),
      ),
    ),
  );
}

/// Format choices for photos sent from this iPhone to an Android phone
/// (D-039). Android phones send their files unchanged.
class _FormatSettings extends ConsumerWidget {
  const _FormatSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(formatSettingsProvider).value;
    final repo = ref.read(settingsRepositoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Header('Sending photos to Android'),
        _Group(
          children: [
            SwitchListTile(
              title: const Text('Convert HEIC to JPEG'),
              subtitle: const Text(
                'Lowers quality and removes HDR: each photo is re-encoded. Only '
                'for older Android galleries that cannot open HEIC. Off '
                '(recommended): photos are sent in original quality, unchanged.',
              ),
              value: settings?.convertHeicToJpeg ?? false,
              onChanged: settings == null ? null : repo.setConvertHeicToJpeg,
            ),
            SwitchListTile(
              title: const Text('Send Live Photo videos'),
              subtitle: const Text(
                'Also send the short video of each Live Photo, as a separate '
                'file. Android cannot play them as Live Photos. Off: only the '
                'photo is sent.',
              ),
              value: settings?.sendLivePhotoVideo ?? false,
              onChanged: settings == null ? null : repo.setSendLivePhotoVideo,
            ),
          ],
        ),
      ],
    );
  }
}
