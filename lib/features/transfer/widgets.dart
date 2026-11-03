import 'package:flutter/material.dart';

import '../../core/protocol/models.dart';
import '../../core/security/device_identity.dart';
import '../../core/security/peer_auth.dart';

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
  Widget build(BuildContext context) => Icon(
    platformIcon(platform),
    size: size,
    semanticLabel: platformLabel(platform),
  );
}

IconData fileKindIcon(String kind) => switch (kind) {
  FileKind.photo => Icons.image_outlined,
  FileKind.video => Icons.movie_outlined,
  _ => Icons.insert_drive_file_outlined,
};

/// A highlighted notice: warnings use the error container colors, which
/// keep their contrast in light and dark mode.
class WarningBox extends StatelessWidget {
  const WarningBox({super.key, required this.text, this.icon, this.error});

  final String text;
  final IconData? icon;

  /// Defaults to true for warning icons.
  final bool? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isError = error ?? icon != Icons.info_outline;
    final bg = isError ? scheme.errorContainer : scheme.secondaryContainer;
    final fg = isError ? scheme.onErrorContainer : scheme.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, color: fg),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(text, style: TextStyle(color: fg)),
          ),
        ],
      ),
    );
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
        const SizedBox(height: 8),
        Semantics(
          container: true,
          label: 'Code ${code.split('').join(' ')}',
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              formatPairingCode(code),
              textAlign: TextAlign.center,
              style: theme.textTheme.displaySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: 4,
              ),
            ),
          ),
        ),
        if (footer != null) ...[
          const SizedBox(height: 4),
          Text(footer!, style: theme.textTheme.bodyMedium),
        ],
      ],
    );
  }
}
