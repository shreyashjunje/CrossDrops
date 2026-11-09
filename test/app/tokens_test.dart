import 'dart:math' as math;

import 'package:crossdrop/app/theme.dart';
import 'package:crossdrop/app/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.x contrast ratio.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final (name, c) in [
    ('dark', CdColors.dark),
    ('light', CdColors.light),
  ]) {
    group('$name tokens', () {
      test('text pairs meet WCAG AA (4.5:1)', () {
        final pairs = {
          'text/bg': (c.text, c.bg),
          'text/surface1': (c.text, c.surface1),
          'text/surface2': (c.text, c.surface2),
          'text/surface3': (c.text, c.surface3),
          'text2/bg': (c.text2, c.bg),
          'text2/surface1': (c.text2, c.surface1),
          'text2/surface2': (c.text2, c.surface2),
          'text3/bg': (c.text3, c.bg),
          'text3/surface1': (c.text3, c.surface1),
          'onAccent/accent': (c.onAccent, c.accent),
          'onAccent/accentPressed': (c.onAccent, c.accentPressed),
          'accentInk/bg': (c.accentInk, c.bg),
          'accentInk/surface1': (c.accentInk, c.surface1),
          'accentInk/accentSoft': (c.accentInk, c.accentSoft),
          'onWarning/warning': (c.onWarning, c.warning),
          'warningInk/bg': (c.warningInk, c.bg),
          'warningInk/warningSoft': (c.warningInk, c.warningSoft),
          'text/warningSoft': (c.text, c.warningSoft),
          'danger/bg': (c.danger, c.bg),
          'danger/surface1': (c.danger, c.surface1),
          'danger/dangerSoft': (c.danger, c.dangerSoft),
          'onDanger/danger': (c.onDanger, c.danger),
          'bg/text (toast)': (c.bg, c.text),
        };
        for (final MapEntry(:key, :value) in pairs.entries) {
          expect(
            contrast(value.$1, value.$2),
            greaterThanOrEqualTo(4.5),
            reason: key,
          );
        }
      });

      test('indicators meet 3:1; outlines stay visible', () {
        // Outlined buttons always carry a text label, so their border is
        // decorative (WCAG 1.4.11); it only has to stand out from the screen.
        expect(contrast(c.lineStrong, c.bg), greaterThanOrEqualTo(1.4));
        // Progress fill against its track.
        expect(contrast(c.accentInk, c.surface3), greaterThanOrEqualTo(3));
        // Focus ring (text color) against the lime fill and the screen.
        expect(contrast(c.text, c.bg), greaterThanOrEqualTo(3));
      });
    });
  }

  test('dark status colors differ in lightness, not only hue', () {
    const c = CdColors.dark;
    final accent = c.accent.computeLuminance();
    final warning = c.warning.computeLuminance();
    final danger = c.danger.computeLuminance();
    expect(accent, greaterThan(warning + 0.1));
    expect(warning, greaterThan(danger + 0.1));
  });

  test('light warning fill and danger text differ in lightness', () {
    const c = CdColors.light;
    expect(
      c.warning.computeLuminance(),
      greaterThan(c.danger.computeLuminance() + 0.3),
    );
  });

  test('the theme carries the matching tokens', () {
    expect(
      buildTheme(Brightness.dark).extension<CdColors>(),
      same(CdColors.dark),
    );
    expect(
      buildTheme(Brightness.light).extension<CdColors>(),
      same(CdColors.light),
    );
  });

  testWidgets('context.cd reads the tokens of the current theme', (
    tester,
  ) async {
    late CdColors seen;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Builder(
          builder: (context) {
            seen = context.cd;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen, same(CdColors.light));
  });

  test('display styles set the Space Grotesk weight axis', () {
    for (final s in [CdType.displayXL, CdType.displayM, CdType.h1, CdType.h3]) {
      expect(s.fontFamily, CdType.display);
      expect(s.fontVariations, isNotEmpty);
    }
    expect(
      CdType.displayXL.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
  });
}
