import 'package:flutter/material.dart';

import 'tokens.dart';

/// Night Signal, light or dark (D-069). Sizes come from the text theme, so
/// the system text size scales everything; nothing has a fixed height
/// except minimum touch targets.
ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final c = dark ? CdColors.dark : CdColors.light;

  // primary is what Material uses for text, icons, focus and selection, so
  // it is the readable accent ink. Lime fills are set per component below
  // and through primaryContainer, always with dark text.
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accentInk,
    onPrimary: dark ? c.onAccent : const Color(0xFFFFFFFF),
    primaryContainer: c.accent,
    onPrimaryContainer: c.onAccent,
    secondary: c.text2,
    onSecondary: c.bg,
    secondaryContainer: c.surface3,
    onSecondaryContainer: c.text,
    tertiary: c.warningInk,
    onTertiary: dark ? c.onWarning : const Color(0xFFFFFFFF),
    tertiaryContainer: c.warning,
    onTertiaryContainer: c.onWarning,
    error: c.danger,
    onError: c.onDanger,
    errorContainer: c.dangerSoft,
    onErrorContainer: c.text,
    surface: c.surface1,
    onSurface: c.text,
    onSurfaceVariant: c.text2,
    surfaceContainerLowest: c.bg,
    surfaceContainerLow: c.bg,
    surfaceContainer: c.surface1,
    surfaceContainerHigh: c.surface2,
    surfaceContainerHighest: c.surface3,
    outline: c.lineStrong,
    outlineVariant: c.line,
    inverseSurface: c.text,
    onInverseSurface: c.bg,
    inversePrimary: c.accent,
    scrim: c.scrim,
    shadow: const Color(0x00000000),
  );

  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(CdRadius.button),
  );
  // Full-width primary actions are 56 tall; inline ones keep the 48 minimum.
  const minButton = Size(64, CdSpace.minTouch);
  const padding = EdgeInsets.symmetric(horizontal: 20, vertical: 14);

  final textTheme = const TextTheme(
    displayLarge: CdType.displayXL,
    displayMedium: CdType.displayM,
    displaySmall: CdType.h1,
    headlineLarge: CdType.h1,
    headlineMedium: CdType.h2,
    headlineSmall: CdType.h3,
    titleLarge: CdType.h3,
    titleMedium: CdType.titleM,
    titleSmall: CdType.titleS,
    bodyLarge: CdType.bodyL,
    bodyMedium: CdType.bodyM,
    bodySmall: CdType.small,
    labelLarge: CdType.label,
    labelMedium: CdType.small,
    labelSmall: CdType.overline,
  ).apply(bodyColor: c.text, displayColor: c.text);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [c],
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    fontFamily: CdType.body,
    textTheme: textTheme,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    splashFactory: NoSplash.splashFactory,
    dividerColor: c.line,
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.text,
      surfaceTintColor: const Color(0x00000000),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: CdType.h3.copyWith(color: c.text),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        disabledBackgroundColor: c.surface2,
        disabledForegroundColor: c.text3,
        minimumSize: minButton,
        padding: padding,
        shape: buttonShape,
        elevation: 0,
        textStyle: CdType.label,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: c.surface3,
        foregroundColor: c.text,
        minimumSize: minButton,
        padding: padding,
        shape: buttonShape,
        elevation: 0,
        textStyle: CdType.label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text,
        side: BorderSide(color: c.lineStrong),
        minimumSize: minButton,
        padding: padding,
        shape: buttonShape,
        textStyle: CdType.label,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accentInk,
        minimumSize: const Size(CdSpace.minTouch, CdSpace.minTouch),
        textStyle: CdType.label,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: c.text,
        minimumSize: const Size(CdSpace.minTouch, CdSpace.minTouch),
      ),
    ),
    cardTheme: CardThemeData(
      color: c.surface1,
      surfaceTintColor: const Color(0x00000000),
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: c.line),
        borderRadius: BorderRadius.circular(CdRadius.card),
      ),
    ),
    listTileTheme: ListTileThemeData(
      minVerticalPadding: 10,
      iconColor: c.text2,
      textColor: c.text,
      titleTextStyle: CdType.titleM.copyWith(color: c.text),
      subtitleTextStyle: CdType.small.copyWith(color: c.text2),
    ),
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.lineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.lineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.text, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.danger),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface1,
      surfaceTintColor: const Color(0x00000000),
      showDragHandle: true,
      dragHandleColor: c.lineStrong,
      elevation: 0,
      modalBarrierColor: c.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CdRadius.sheet),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface2,
      surfaceTintColor: const Color(0x00000000),
      elevation: 0,
      barrierColor: c.scrim,
      titleTextStyle: CdType.h3.copyWith(color: c.text),
      contentTextStyle: CdType.bodyM.copyWith(color: c.text2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CdRadius.dialog),
        side: BorderSide(color: c.line),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.text,
      contentTextStyle: CdType.bodyM.copyWith(color: c.bg),
      actionTextColor: c.bg,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.bg,
      surfaceTintColor: const Color(0x00000000),
      indicatorColor: c.accent,
      elevation: 0,
      height: 72,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? c.onAccent : c.text2,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => CdType.overline.copyWith(
          letterSpacing: 0,
          color: s.contains(WidgetState.selected) ? c.text : c.text2,
        ),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.accentInk,
      linearTrackColor: c.surface3,
      circularTrackColor: c.surface3,
      linearMinHeight: 10,
      borderRadius: BorderRadius.circular(5),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : c.surface3,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected) ? c.accentPressed : c.lineStrong,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.onAccent : c.text2,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : null,
      ),
      checkColor: WidgetStatePropertyAll(c.onAccent),
      side: BorderSide(color: c.lineStrong, width: 2),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surface1,
      selectedColor: c.text,
      side: BorderSide(color: c.lineStrong),
      labelStyle: CdType.titleS.copyWith(color: c.text),
      secondaryLabelStyle: CdType.titleS.copyWith(color: c.bg),
      shape: const StadiumBorder(),
    ),
  );
}
