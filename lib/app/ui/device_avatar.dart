import 'package:flutter/material.dart';

import '../../core/security/device_identity.dart';
import '../tokens.dart';
import 'phone_glyph.dart';

/// The other phone as a person: a circle with the first letter of its
/// name and a small platform badge (D-069). [locked] is the radar's
/// lock-on look: lime fill and a ring around it.
///
/// Decoration only: the row or button around it carries the label, for
/// example "Alex's Pixel 8, Android, same Wi-Fi".
class DeviceAvatar extends StatelessWidget {
  const DeviceAvatar({
    super.key,
    required this.name,
    required this.platform,
    this.size = 56,
    this.locked = false,
    this.showBadge = true,
  });

  final String name;
  final DevicePlatform? platform;
  final double size;
  final bool locked;
  final bool showBadge;

  /// First visible character of [name], upper case; "?" when empty.
  static String initialOf(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final badge = (size * 0.44).roundToDouble();
    final circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: locked ? c.accent : c.surface3,
        border: locked ? null : Border.all(color: c.lineStrong),
      ),
      child: Text(
        initialOf(name),
        textScaler: TextScaler.noScaling,
        style: CdType.h3.copyWith(
          fontSize: size * 0.36,
          height: 1,
          color: locked ? c.onAccent : c.text,
        ),
      ),
    );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size + (locked ? 14 : 0),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (locked)
              Container(
                width: size + 14,
                height: size + 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: c.accent, width: 2),
                ),
              ),
            circle,
            if (showBadge && !locked)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: badge,
                  height: badge,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.bg,
                    border: Border.all(color: c.lineStrong),
                  ),
                  child: PhoneGlyph(
                    platform: platform,
                    size: badge * 0.62,
                    color: c.text,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
