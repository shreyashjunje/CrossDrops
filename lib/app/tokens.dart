import 'package:flutter/material.dart';

/// Night Signal colors (D-069). Dark is the reference; light keeps the lime
/// accent as a fill with dark text on it, and uses [accentInk] wherever the
/// accent would be text, an icon or a thin line.
@immutable
class CdColors extends ThemeExtension<CdColors> {
  const CdColors({
    required this.bg,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.line,
    required this.lineStrong,
    required this.text,
    required this.text2,
    required this.text3,
    required this.accent,
    required this.accentPressed,
    required this.onAccent,
    required this.accentInk,
    required this.accentSoft,
    required this.warning,
    required this.onWarning,
    required this.warningInk,
    required this.warningSoft,
    required this.warningLine,
    required this.danger,
    required this.onDanger,
    required this.dangerSoft,
    required this.dangerLine,
    required this.scrim,
  });

  /// Screen background.
  final Color bg;

  /// Cards and sheets.
  final Color surface1;

  /// Raised: dialogs, inputs, code cells.
  final Color surface2;

  /// Pressed states, progress tracks, avatars.
  final Color surface3;

  /// 1 px borders and dividers.
  final Color line;

  /// Outlined buttons, focus-off borders.
  final Color lineStrong;

  /// Primary text, at least 15:1 on [bg].
  final Color text;

  /// Secondary text.
  final Color text2;

  /// Hints and captions; still 4.5:1 on [bg] and [surface1].
  final Color text3;

  /// The one accent. A fill, always with [onAccent] on it.
  final Color accent;
  final Color accentPressed;
  final Color onAccent;

  /// The accent as text, icons and thin indicators.
  final Color accentInk;

  /// Fill behind [accentInk], for "Trusted" and similar badges.
  final Color accentSoft;

  /// Warning fill (first time, reconnecting), with [onWarning] on it.
  final Color warning;
  final Color onWarning;

  /// Warning as text or icon on [bg] or [warningSoft].
  final Color warningInk;
  final Color warningSoft;
  final Color warningLine;

  /// Danger as text or icon (failed, cancel, forget).
  final Color danger;
  final Color onDanger;
  final Color dangerSoft;
  final Color dangerLine;

  /// Behind sheets and dialogs.
  final Color scrim;

  static const dark = CdColors(
    bg: Color(0xFF0E1116),
    surface1: Color(0xFF151A21),
    surface2: Color(0xFF1C222B),
    surface3: Color(0xFF262D38),
    line: Color(0xFF2A313C),
    lineStrong: Color(0xFF3A4350),
    text: Color(0xFFEEF1F5),
    text2: Color(0xFFA6AFBC),
    text3: Color(0xFF808A99),
    accent: Color(0xFFC8F25A),
    accentPressed: Color(0xFFB3DC45),
    onAccent: Color(0xFF0E1116),
    accentInk: Color(0xFFC8F25A),
    accentSoft: Color(0xFF232B17),
    warning: Color(0xFFFFB547),
    onWarning: Color(0xFF0E1116),
    warningInk: Color(0xFFFFB547),
    warningSoft: Color(0xFF2E2414),
    warningLine: Color(0xFF5C4520),
    danger: Color(0xFFFF7B6E),
    onDanger: Color(0xFF0E1116),
    dangerSoft: Color(0xFF2E1A19),
    dangerLine: Color(0xFF5A2E2A),
    scrim: Color(0x99000000),
  );

  static const light = CdColors(
    bg: Color(0xFFF5F6F3),
    surface1: Color(0xFFFFFFFF),
    surface2: Color(0xFFECEEE9),
    surface3: Color(0xFFE0E3DC),
    line: Color(0xFFDADDD5),
    lineStrong: Color(0xFFBFC4BA),
    text: Color(0xFF0E1116),
    text2: Color(0xFF475060),
    text3: Color(0xFF5C6573),
    accent: Color(0xFFC8F25A),
    accentPressed: Color(0xFFB3DC45),
    onAccent: Color(0xFF0E1116),
    accentInk: Color(0xFF4A6600),
    accentSoft: Color(0xFFEEF8D2),
    warning: Color(0xFFFFC94D),
    onWarning: Color(0xFF0E1116),
    warningInk: Color(0xFF6E4700),
    warningSoft: Color(0xFFFFF4DA),
    warningLine: Color(0xFFF0D89A),
    danger: Color(0xFFB42D22),
    onDanger: Color(0xFFFFFFFF),
    dangerSoft: Color(0xFFFDE6E3),
    dangerLine: Color(0xFFF2B8B1),
    scrim: Color(0x660E1116),
  );

  /// Tokens are fixed per brightness; nothing copies them with changes.
  @override
  CdColors copyWith() => this;

  /// Themes switch with the system setting; no cross-fade of tokens.
  @override
  CdColors lerp(ThemeExtension<CdColors>? other, double t) =>
      (other is CdColors && t >= 0.5) ? other : this;
}

extension CdThemeX on BuildContext {
  /// The Night Signal colors of the current theme.
  CdColors get cd =>
      Theme.of(this).extension<CdColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? CdColors.dark
          : CdColors.light);
}

/// 8 px grid.
abstract final class CdSpace {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const s = 12.0;
  static const m = 16.0;
  static const l = 24.0;
  static const xl = 32.0;
  static const xxl = 40.0;
  static const x3 = 48.0;
  static const x4 = 64.0;

  /// Screen side padding; [gutterNarrow] under 360 px wide.
  static const gutter = 24.0;
  static const gutterNarrow = 16.0;

  /// Android and iOS minimum touch target.
  static const minTouch = 48.0;
  static const buttonHeight = 56.0;
}

abstract final class CdRadius {
  static const chip = 8.0;
  static const tile = 12.0;
  static const button = 16.0;
  static const card = 20.0;
  static const dialog = 24.0;
  static const sheet = 28.0;
}

/// Motion stays between 150 and 300 ms; loops stop when the system asks
/// for reduced motion (MediaQuery.disableAnimations).
abstract final class CdMotion {
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 300);
  static const radarPulse = Duration(milliseconds: 2400);
  static const flowLoop = Duration(milliseconds: 1600);
  static const enter = Curves.easeOutCubic;

  /// Small overshoot for the radar lock-on.
  static const lockOn = Curves.easeOutBack;
}

abstract final class CdType {
  static const display = 'SpaceGrotesk';
  static const body = 'Inter';

  static const _tnum = [FontFeature.tabularFigures()];

  /// Space Grotesk ships as a variable font whose default is Light, so the
  /// weight is set on the axis as well as through [FontWeight].
  static const _sg600 = [FontVariation.weight(600)];
  static const _sg700 = [FontVariation.weight(700)];

  /// The 6-digit code and big percentages.
  static const displayXL = TextStyle(
    fontFamily: display,
    fontSize: 64,
    height: 1.0,
    fontWeight: FontWeight.w600,
    fontVariations: _sg600,
    letterSpacing: -1.9,
    fontFeatures: _tnum,
  );

  /// Speed and time left.
  static const displayM = TextStyle(
    fontFamily: display,
    fontSize: 44,
    height: 48 / 44,
    fontWeight: FontWeight.w600,
    fontVariations: _sg600,
    letterSpacing: -0.9,
    fontFeatures: _tnum,
  );

  /// The big Send word on Home.
  static const hero = TextStyle(
    fontFamily: display,
    fontSize: 48,
    height: 52 / 48,
    fontWeight: FontWeight.w700,
    fontVariations: _sg700,
    letterSpacing: -1.4,
  );

  static const h1 = TextStyle(
    fontFamily: display,
    fontSize: 30,
    height: 36 / 30,
    fontWeight: FontWeight.w600,
    fontVariations: _sg600,
    letterSpacing: -0.3,
  );
  static const h2 = TextStyle(
    fontFamily: display,
    fontSize: 24,
    height: 30 / 24,
    fontWeight: FontWeight.w600,
    fontVariations: _sg600,
  );
  static const h3 = TextStyle(
    fontFamily: display,
    fontSize: 20,
    height: 26 / 20,
    fontWeight: FontWeight.w600,
    fontVariations: _sg600,
  );

  static const bodyL = TextStyle(
    fontFamily: body,
    fontSize: 17,
    height: 26 / 17,
    fontWeight: FontWeight.w400,
  );
  static const bodyM = TextStyle(
    fontFamily: body,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w400,
    fontFeatures: _tnum,
  );
  static const titleM = TextStyle(
    fontFamily: body,
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeight.w600,
  );
  static const titleS = TextStyle(
    fontFamily: body,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
  );

  /// Buttons.
  static const label = TextStyle(
    fontFamily: body,
    fontSize: 16,
    height: 20 / 16,
    fontWeight: FontWeight.w600,
  );
  static const small = TextStyle(
    fontFamily: body,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w500,
    fontFeatures: _tnum,
  );
  static const overline = TextStyle(
    fontFamily: body,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.7,
  );
}
