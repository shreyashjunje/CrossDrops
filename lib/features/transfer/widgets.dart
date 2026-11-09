import 'package:flutter/material.dart';

import '../../app/ui/ui.dart';
import '../../core/protocol/models.dart';
import '../../core/security/device_identity.dart';

/// "iPhone", "Android phone"; a claim by the other phone, used as a label.
String platformLabel(DevicePlatform? p) => switch (p) {
  DevicePlatform.ios => 'iPhone',
  DevicePlatform.android => 'Android phone',
  null => 'Unknown device',
};

IconData platformIcon(DevicePlatform? p) => switch (p) {
  DevicePlatform.ios => Icons.phone_iphone,
  DevicePlatform.android => Icons.phone_android,
  null => Icons.device_unknown,
};

class PlatformIcon extends StatelessWidget {
  const PlatformIcon({super.key, required this.platform, this.size = 32});

  final DevicePlatform? platform;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: platformLabel(platform),
    child: ExcludeSemantics(
      child: PhoneGlyph(platform: platform, size: size),
    ),
  );
}

IconData fileKindIcon(String kind) => switch (kind) {
  FileKind.photo => Icons.image_outlined,
  FileKind.video => Icons.movie_outlined,
  _ => Icons.insert_drive_file_outlined,
};

/// A highlighted notice. Warnings are amber, errors red, info neutral
/// (D-069); the icon shape tells them apart too.
class WarningBox extends StatelessWidget {
  const WarningBox({super.key, required this.text, this.icon, this.error});

  final String text;
  final IconData? icon;

  /// True: a danger notice. Null: warning, or neutral for an info icon.
  final bool? error;

  @override
  Widget build(BuildContext context) {
    final tone = error == true
        ? NoticeTone.danger
        : icon == Icons.info_outline
        ? NoticeTone.neutral
        : NoticeTone.warning;
    return NoticeCard(text: text, icon: icon, tone: tone);
  }
}

/// The 6-digit pairing code, large, read digit by digit by screen readers.
class PairingCodeBox extends StatelessWidget {
  const PairingCodeBox({
    super.key,
    required this.code,
    required this.caption,
    this.footer,
  });

  final String code;
  final String caption;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(caption, style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        CodeDisplay(code: code),
        if (footer != null) ...[
          const SizedBox(height: 8),
          Text(
            footer!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
