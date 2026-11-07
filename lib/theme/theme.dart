import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';
import 'spacing.dart';

export 'colors.dart';
export 'spacing.dart';

ThemeData pelviLightTheme() {
  final baseText = GoogleFonts.interTextTheme();
  final text = baseText.copyWith(
    displayLarge: baseText.displayLarge?.copyWith(
      fontSize: 25,
      height: 34 / 25,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.7,
      color: PelviColors.ink,
    ),
    headlineMedium: baseText.headlineMedium?.copyWith(
      fontSize: 32,
      height: 28 / 32,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.9,
      color: PelviColors.ink,
    ),
    titleLarge: baseText.titleLarge?.copyWith(
      fontSize: 32,
      height: 28 / 32,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.9,
      color: PelviColors.ink,
    ),
    titleMedium: baseText.titleMedium?.copyWith(
      fontSize: 23,
      height: 28 / 23,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.7,
      color: PelviColors.ink,
    ),
    bodyLarge: baseText.bodyLarge?.copyWith(
      fontSize: 16,
      height: 24 / 16,
      fontWeight: FontWeight.w400,
      color: PelviColors.ink,
    ),
    bodyMedium: baseText.bodyMedium?.copyWith(
      fontSize: 15,
      height: 1.65,
      fontWeight: FontWeight.w400,
      color: PelviColors.ink,
    ),
    labelLarge: baseText.labelLarge?.copyWith(
      fontSize: 15,
      height: 24 / 15,
      fontWeight: FontWeight.w600,
      color: PelviColors.ink,
    ),
    labelMedium: baseText.labelMedium?.copyWith(
      fontSize: 11,
      height: 14 / 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.1,
      color: PelviColors.inkMuted,
    ),
    labelSmall: baseText.labelSmall?.copyWith(
      fontSize: 11,
      height: 14 / 11,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.2,
      color: PelviColors.inkMuted,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: PelviColors.canvas,
    colorScheme: const ColorScheme.light(
      primary: PelviColors.pink700,
      onPrimary: PelviColors.inkInverse,
      primaryContainer: PelviColors.pink50,
      onPrimaryContainer: PelviColors.pink950,
      secondary: PelviColors.purple700,
      onSecondary: PelviColors.inkInverse,
      secondaryContainer: PelviColors.purple50,
      onSecondaryContainer: PelviColors.purple950,
      surface: PelviColors.surface,
      onSurface: PelviColors.ink,
      onSurfaceVariant: PelviColors.inkMuted,
      outline: PelviColors.border,
      error: PelviColors.danger,
      onError: PelviColors.inkInverse,
    ),
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: PelviColors.canvas,
      foregroundColor: PelviColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
      shape: const Border(
        bottom: BorderSide(color: PelviColors.chromeBorder, width: 1),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: PelviColors.border,
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardThemeData(
      color: PelviColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PelviRadius.lg),
        side: const BorderSide(color: PelviColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PelviColors.surface,
      contentPadding: const EdgeInsets.all(PelviSpace.md),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PelviRadius.md),
        borderSide: const BorderSide(color: PelviColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PelviRadius.md),
        borderSide: const BorderSide(color: PelviColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PelviRadius.md),
        borderSide: const BorderSide(color: PelviColors.pink700, width: 1.5),
      ),
      hintStyle: text.bodyMedium?.copyWith(color: PelviColors.inkMuted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: PelviColors.pink700,
        foregroundColor: PelviColors.inkInverse,
        minimumSize: const Size(64, 50),
        textStyle: text.labelLarge?.copyWith(
          color: PelviColors.inkInverse,
          fontSize: 15,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PelviRadius.button),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: PelviColors.pink700,
        side: const BorderSide(color: PelviColors.border),
        minimumSize: const Size(64, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PelviRadius.md),
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: PelviColors.pink700,
      foregroundColor: PelviColors.inkInverse,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PelviRadius.fab),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) {
        return s.contains(WidgetState.selected)
            ? PelviColors.inkInverse
            : PelviColors.surface;
      }),
      trackColor: WidgetStateProperty.resolveWith((s) {
        return s.contains(WidgetState.selected)
            ? PelviColors.pink700
            : PelviColors.surfaceMuted;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) {
        return s.contains(WidgetState.selected)
            ? Colors.transparent
            : PelviColors.border;
      }),
    ),
  );
}
