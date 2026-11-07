import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';
import 'spacing.dart';

export 'colors.dart';
export 'spacing.dart';

ThemeData pelviLightTheme() => _pelviTheme(PelviPalette.light, Brightness.light);

ThemeData pelviDarkTheme() => _pelviTheme(PelviPalette.dark, Brightness.dark);

ThemeData _pelviTheme(PelviPalette p, Brightness brightness) {
  final baseText = GoogleFonts.interTextTheme();
  final text = baseText.copyWith(
    displayLarge: baseText.displayLarge?.copyWith(
      fontSize: 25,
      height: 34 / 25,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.7,
      color: p.ink,
    ),
    headlineMedium: baseText.headlineMedium?.copyWith(
      fontSize: 32,
      height: 28 / 32,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.9,
      color: p.ink,
    ),
    titleLarge: baseText.titleLarge?.copyWith(
      fontSize: 28,
      height: 28 / 28,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.9,
      color: p.ink,
    ),
    titleMedium: baseText.titleMedium?.copyWith(
      fontSize: 23,
      height: 28 / 23,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.7,
      color: p.ink,
    ),
    bodyLarge: baseText.bodyLarge?.copyWith(
      fontSize: 16,
      height: 24 / 16,
      fontWeight: FontWeight.w400,
      color: p.ink,
    ),
    bodyMedium: baseText.bodyMedium?.copyWith(
      fontSize: 15,
      height: 1.65,
      fontWeight: FontWeight.w400,
      color: p.ink,
    ),
    labelLarge: baseText.labelLarge?.copyWith(
      fontSize: 15,
      height: 24 / 15,
      fontWeight: FontWeight.w600,
      color: p.ink,
    ),
    labelMedium: baseText.labelMedium?.copyWith(
      fontSize: 11,
      height: 14 / 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.1,
      color: p.inkMuted,
    ),
    labelSmall: baseText.labelSmall?.copyWith(
      fontSize: 11,
      height: 14 / 11,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.2,
      color: p.inkMuted,
    ),
  );

  final scheme = brightness == Brightness.light
      ? ColorScheme.light(
          primary: p.pink700,
          onPrimary: p.inkInverse,
          primaryContainer: p.pink50,
          onPrimaryContainer: p.pink950,
          secondary: p.purple700,
          onSecondary: p.inkInverse,
          secondaryContainer: p.purple50,
          onSecondaryContainer: p.purple950,
          surface: p.surface,
          onSurface: p.ink,
          onSurfaceVariant: p.inkMuted,
          outline: p.border,
          error: p.danger,
          onError: p.inkInverse,
        )
      : ColorScheme.dark(
          primary: p.pink700,
          onPrimary: p.inkInverse,
          primaryContainer: p.pink50,
          onPrimaryContainer: p.ink,
          secondary: p.purple700,
          onSecondary: p.inkInverse,
          secondaryContainer: p.purple50,
          onSecondaryContainer: p.ink,
          surface: p.surface,
          onSurface: p.ink,
          onSurfaceVariant: p.inkMuted,
          outline: p.border,
          error: p.danger,
          onError: p.ink,
        );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: p.canvas,
    colorScheme: scheme,
    extensions: <ThemeExtension<dynamic>>[p],
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: p.canvas,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
      shape: Border(
        bottom: BorderSide(color: p.chromeBorder, width: 1),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: p.border,
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PelviRadius.lg),
        side: BorderSide(color: p.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      contentPadding: const EdgeInsets.all(PelviSpace.md),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PelviRadius.md),
        borderSide: BorderSide(color: p.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PelviRadius.md),
        borderSide: BorderSide(color: p.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PelviRadius.md),
        borderSide: BorderSide(color: p.pink700, width: 1.5),
      ),
      hintStyle: text.bodyMedium?.copyWith(color: p.inkMuted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.pink700,
        foregroundColor: p.inkInverse,
        minimumSize: const Size(64, 50),
        textStyle: text.labelLarge?.copyWith(
          color: p.inkInverse,
          fontSize: 15,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PelviRadius.button),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.pink700,
        side: BorderSide(color: p.border),
        minimumSize: const Size(64, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PelviRadius.md),
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.pink700,
      foregroundColor: p.inkInverse,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PelviRadius.fab),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) {
        return s.contains(WidgetState.selected) ? p.inkInverse : p.surface;
      }),
      trackColor: WidgetStateProperty.resolveWith((s) {
        return s.contains(WidgetState.selected) ? p.pink700 : p.surfaceMuted;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) {
        return s.contains(WidgetState.selected)
            ? Colors.transparent
            : p.border;
      }),
    ),
  );
}
