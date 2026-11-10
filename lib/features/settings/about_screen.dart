import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/tokens.dart';
import '../../app/version.dart';
import '../usb_import/cable_probe_screen.dart';
import '../usb_import/usb_import_controller.dart';

/// What CrossDrop is, how it keeps files private, this phone's security
/// key, and the open-source licenses.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cd;
    final fp = ref.watch(credentialsProvider).value?.fingerprint;
    Widget card(String title, Widget body) => Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: BorderRadius.circular(CdRadius.button),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: CdType.titleM.copyWith(color: c.text)),
          ),
          const SizedBox(height: 6),
          body,
        ],
      ),
    );
    Widget section(String title, String body) =>
        card(title, Text(body, style: CdType.bodyM.copyWith(color: c.text2)));
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          CdSpace.gutter,
          8,
          CdSpace.gutter,
          CdSpace.l,
        ),
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(CdRadius.button),
                  ),
                  child: Icon(
                    Icons.swap_horiz_rounded,
                    size: 32,
                    color: c.onAccent,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CrossDrop', style: CdType.h2.copyWith(color: c.text)),
                    Text(
                      'Version $appVersion',
                      style: CdType.small.copyWith(color: c.text2),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
          if (fp != null)
            card(
              "This phone's security key",
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    _group(fp),
                    style: CdType.bodyM.copyWith(
                      fontFamily: 'monospace',
                      color: c.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Other phones know this phone by this key, not by its '
                    'name.',
                    style: CdType.small.copyWith(color: c.text3),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          if (ref.watch(usbImportAvailableProvider)) ...[
            OutlinedButton(
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(
                  Size.fromHeight(CdSpace.buttonHeight),
                ),
              ),
              onPressed: () => pushScreen<void>(
                context,
                Routes.settings,
                const CableProbeScreen(),
              ),
              child: const Text('Cable test'),
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton(
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(
                Size.fromHeight(CdSpace.buttonHeight),
              ),
            ),
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
