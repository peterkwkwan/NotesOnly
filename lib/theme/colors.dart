import 'package:flutter/material.dart';

/// Pelvi brand + neutral color tokens.
///
/// Light values match Figma cream / dusty-pink SoT.
/// Dark neutrals + accents from Figma journey `34:2` (`#17141c` canvas, etc.).
/// Prefer [PelviColors.of] in widgets so chrome follows [ThemeMode].
class PelviColors {
  PelviColors._();

  // Brand — dusty pink (primary) / purple (secondary) — light defaults
  static const pink950 = Color(0xFF8A2E56);
  static const pink700 = Color(0xFFB63C70);
  static const pink400 = Color(0xFFD48AA8);
  static const pink200 = Color(0xFFE8C4D4);
  static const pink50 = Color(0xFFF8EAF0);

  static const purple950 = Color(0xFF5A4578);
  static const purple700 = Color(0xFF7B609F);
  static const purple400 = Color(0xFFA892C0);
  static const purple50 = Color(0xFFF1ECF6);

  // Neutrals (Figma cream canvas)
  static const canvas = Color(0xFFFFFCFA);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF6F2F2);
  static const ink = Color(0xFF302931);
  static const inkMuted = Color(0xFF827780);
  static const inkInverse = Color(0xFFFFFFFF);
  static const border = Color(0xFFEDE5E8);
  static const chromeBorder = Color(0xFFEDE5E8);
  static const overlay = Color(0x73302931); // ~45% ink

  // Semantic
  static const success = Color(0xFF007A33);
  static const danger = Color(0xFFB42318);
  static const warning = Color(0xFFB54708);

  /// Theme-resolved palette (light or dark).
  static PelviPalette of(BuildContext context) {
    return Theme.of(context).extension<PelviPalette>() ?? PelviPalette.light;
  }
}

/// Resolved chrome + accents for the active brightness.
class PelviPalette extends ThemeExtension<PelviPalette> {
  const PelviPalette({
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.ink,
    required this.inkMuted,
    required this.inkInverse,
    required this.border,
    required this.chromeBorder,
    required this.overlay,
    required this.pink950,
    required this.pink700,
    required this.pink400,
    required this.pink200,
    required this.pink50,
    required this.purple950,
    required this.purple700,
    required this.purple400,
    required this.purple50,
    required this.success,
    required this.danger,
    required this.warning,
  });

  final Color canvas;
  final Color surface;
  final Color surfaceMuted;
  final Color ink;
  final Color inkMuted;
  final Color inkInverse;
  final Color border;
  final Color chromeBorder;
  final Color overlay;
  final Color pink950;
  final Color pink700;
  final Color pink400;
  final Color pink200;
  final Color pink50;
  final Color purple950;
  final Color purple700;
  final Color purple400;
  final Color purple50;
  final Color success;
  final Color danger;
  final Color warning;

  /// Cream / dusty-pink light tokens.
  static const light = PelviPalette(
    canvas: PelviColors.canvas,
    surface: PelviColors.surface,
    surfaceMuted: PelviColors.surfaceMuted,
    ink: PelviColors.ink,
    inkMuted: PelviColors.inkMuted,
    inkInverse: PelviColors.inkInverse,
    border: PelviColors.border,
    chromeBorder: PelviColors.chromeBorder,
    overlay: PelviColors.overlay,
    pink950: PelviColors.pink950,
    pink700: PelviColors.pink700,
    pink400: PelviColors.pink400,
    pink200: PelviColors.pink200,
    pink50: PelviColors.pink50,
    purple950: PelviColors.purple950,
    purple700: PelviColors.purple700,
    purple400: PelviColors.purple400,
    purple50: PelviColors.purple50,
    success: PelviColors.success,
    danger: PelviColors.danger,
    warning: PelviColors.warning,
  );

  /// Figma dark chrome (`34:2`): canvas `#17141c`, surface `#25212c`,
  /// ink `#f2ecf4`, muted `#beb2c6`, border `#786b80`, primary `#f29bbf`.
  static const dark = PelviPalette(
    canvas: Color(0xFF17141C),
    surface: Color(0xFF25212C),
    surfaceMuted: Color(0xFF3A2533),
    ink: Color(0xFFF2ECF4),
    inkMuted: Color(0xFFBEB2C6),
    inkInverse: Color(0xFF291523),
    border: Color(0xFF786B80),
    chromeBorder: Color(0xFF786B80),
    overlay: Color(0xB317141C),
    pink950: Color(0xFFF29BBF),
    pink700: Color(0xFFF29BBF),
    pink400: Color(0xFFD48AA8),
    pink200: Color(0xFF5A3A48),
    pink50: Color(0xFF3A2533),
    purple950: Color(0xFFC4B0E0),
    purple700: Color(0xFFA892C0),
    purple400: Color(0xFFA892C0),
    purple50: Color(0xFF2E2840),
    success: PelviColors.success,
    danger: Color(0xFFF97066),
    warning: PelviColors.warning,
  );

  @override
  PelviPalette copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceMuted,
    Color? ink,
    Color? inkMuted,
    Color? inkInverse,
    Color? border,
    Color? chromeBorder,
    Color? overlay,
    Color? pink950,
    Color? pink700,
    Color? pink400,
    Color? pink200,
    Color? pink50,
    Color? purple950,
    Color? purple700,
    Color? purple400,
    Color? purple50,
    Color? success,
    Color? danger,
    Color? warning,
  }) {
    return PelviPalette(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      inkInverse: inkInverse ?? this.inkInverse,
      border: border ?? this.border,
      chromeBorder: chromeBorder ?? this.chromeBorder,
      overlay: overlay ?? this.overlay,
      pink950: pink950 ?? this.pink950,
      pink700: pink700 ?? this.pink700,
      pink400: pink400 ?? this.pink400,
      pink200: pink200 ?? this.pink200,
      pink50: pink50 ?? this.pink50,
      purple950: purple950 ?? this.purple950,
      purple700: purple700 ?? this.purple700,
      purple400: purple400 ?? this.purple400,
      purple50: purple50 ?? this.purple50,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
    );
  }

  @override
  PelviPalette lerp(ThemeExtension<PelviPalette>? other, double t) {
    if (other is! PelviPalette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return PelviPalette(
      canvas: mix(canvas, other.canvas),
      surface: mix(surface, other.surface),
      surfaceMuted: mix(surfaceMuted, other.surfaceMuted),
      ink: mix(ink, other.ink),
      inkMuted: mix(inkMuted, other.inkMuted),
      inkInverse: mix(inkInverse, other.inkInverse),
      border: mix(border, other.border),
      chromeBorder: mix(chromeBorder, other.chromeBorder),
      overlay: mix(overlay, other.overlay),
      pink950: mix(pink950, other.pink950),
      pink700: mix(pink700, other.pink700),
      pink400: mix(pink400, other.pink400),
      pink200: mix(pink200, other.pink200),
      pink50: mix(pink50, other.pink50),
      purple950: mix(purple950, other.purple950),
      purple700: mix(purple700, other.purple700),
      purple400: mix(purple400, other.purple400),
      purple50: mix(purple50, other.purple50),
      success: mix(success, other.success),
      danger: mix(danger, other.danger),
      warning: mix(warning, other.warning),
    );
  }
}
