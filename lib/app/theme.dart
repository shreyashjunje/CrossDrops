import 'package:flutter/material.dart';

/// The seed for both color schemes. Material 3 derives tones from it that
/// meet WCAG AA contrast for text on its surfaces, in light and dark.
const _seed = Colors.teal;

/// Light or dark theme. Sizes come from the text theme, so the system text
/// size scales everything; nothing has a fixed height.
ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  // At least 48 dp tall (Material and Apple touch-target minimum).
  const minButton = Size(64, 48);
  final padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12);
  return ThemeData(
    colorScheme: scheme,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: minButton, padding: padding),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: minButton, padding: padding),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(vertical: 6)),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 10),
  );
}
