import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/version.dart';

/// What CrossDrop is, how it keeps files private, this phone's security
/// key, and the open-source licenses.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fp = ref.watch(credentialsProvider).value?.fingerprint;
    Widget section(String title, String body) => Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 4),
          Text(body, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('CrossDrop', style: theme.textTheme.headlineMedium),
          Text('Version $appVersion', style: theme.textTheme.bodyMedium),
          section(
            'What it does',
            'Sends photos, videos and files between an iPhone and an Android '
                'phone, straight over Wi-Fi or a hotspot, in original '
                'quality. Both phones need CrossDrop open.',
          ),
          section(
            'Private by design',
            'No account and no cloud. Files never leave your local network, '
                'and CrossDrop has no analytics or ads.',
          ),
          section(
            'Secure',
            'Every transfer is encrypted (TLS 1.3). Each phone has its own '
                'security key. The first time two phones connect, you '
                'compare a 6-digit code, and nothing arrives unless you tap '
                'Accept. Every file is checked with SHA-256 before it is '
                'saved.',
          ),
          if (fp != null) ...[
            section(
              "This phone's security key",
              'Other phones know this phone by this key, not by its name.',
            ),
            const SizedBox(height: 4),
            SelectableText(
              _group(fp),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ],
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'CrossDrop',
              applicationVersion: appVersion,
            ),
            child: const Text('Open-source licenses'),
          ),
        ],
      ),
    );
  }

  /// The fingerprint in groups of four, for reading aloud.
  static String _group(String fp) => [
    for (var i = 0; i < fp.length; i += 4)
      fp.substring(i, i + 4 > fp.length ? fp.length : i + 4),
  ].join(' ');
}
