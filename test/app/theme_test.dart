import 'dart:math' as math;

import 'package:crossdrop/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.x contrast ratio.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    test('$brightness: text pairs meet WCAG AA (4.5:1)', () {
      final s = buildTheme(brightness).colorScheme;
      final pairs = {
        'onSurface/surface': (s.onSurface, s.surface),
        'onSurfaceVariant/surface': (s.onSurfaceVariant, s.surface),
        'onPrimary/primary': (s.onPrimary, s.primary),
        'onPrimaryContainer/primaryContainer': (
          s.onPrimaryContainer,
          s.primaryContainer,
        ),
        'onErrorContainer/errorContainer': (
          s.onErrorContainer,
          s.errorContainer,
        ),
        'error/surface': (s.error, s.surface),
        'primary/surface': (s.primary, s.surface),
      };
      for (final MapEntry(:key, :value) in pairs.entries) {
        expect(
          contrast(value.$1, value.$2),
          greaterThanOrEqualTo(4.5),
          reason: key,
        );
      }
    });
  }
}
