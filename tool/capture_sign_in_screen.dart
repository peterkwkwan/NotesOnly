import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelvi_crm/features/auth/sign_in_screen.dart';
import 'package:pelvi_crm/theme/colors.dart';

ThemeData _captureTheme() {
  const p = PelviPalette.light;
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: p.canvas,
    textTheme: Typography.material2021().black.apply(
      bodyColor: p.ink,
      displayColor: p.ink,
    ).copyWith(
      displayLarge: const TextStyle(
        fontSize: 30,
        height: 38 / 30,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.9,
        color: PelviColors.ink,
      ),
      headlineMedium: const TextStyle(
        fontSize: 32,
        height: 1,
        fontWeight: FontWeight.w600,
        letterSpacing: -1.2,
        color: PelviColors.ink,
      ),
      bodyMedium: const TextStyle(
        fontSize: 15,
        height: 1.65,
        fontWeight: FontWeight.w400,
        color: PelviColors.ink,
      ),
      labelLarge: const TextStyle(
        fontSize: 15,
        height: 24 / 15,
        fontWeight: FontWeight.w600,
        color: PelviColors.ink,
      ),
      labelMedium: const TextStyle(
        fontSize: 11,
        height: 1,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.2,
        color: PelviColors.purple700,
      ),
      labelSmall: const TextStyle(
        fontSize: 12,
        height: 19 / 12,
        fontWeight: FontWeight.w400,
        color: PelviColors.inkMuted,
      ),
    ),
    extensions: const [p],
    colorScheme: const ColorScheme.light(
      primary: PelviColors.pink700,
      onPrimary: PelviColors.inkInverse,
      secondary: PelviColors.purple700,
      surface: PelviColors.surface,
      onSurface: PelviColors.ink,
      outline: PelviColors.border,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: PelviColors.ink,
        side: const BorderSide(color: PelviColors.border),
        minimumSize: const Size(64, 54),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture sign-in screen proof png', (tester) async {
    final out = File(
      '/cursor/stores/bc-f9c2cc93-7a91-4da4-99f1-9a25cab0491c/media/sign-in-figma/app-sign-in.png',
    );
    await tester.binding.setSurfaceSize(const Size(412, 892));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _captureTheme(),
        home: RepaintBoundary(
          key: key,
          child: const SizedBox(
            width: 412,
            height: 892,
            child: SignInScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    // Decode brand PNGs before snapshot (Image.asset is async).
    await tester.runAsync(() async {
      final ctx = key.currentContext!;
      await precacheImage(
        const AssetImage('assets/brand/notesonly-monogram.png'),
        ctx,
      );
      await precacheImage(
        const AssetImage('assets/brand/google-g.png'),
        ctx,
      );
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('NotesOnly'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.textContaining('A little less admin'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await out.parent.create(recursive: true);
      await out.writeAsBytes(bytes!.buffer.asUint8List());
    });
    expect(out.lengthSync() > 1000, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(seconds: 30)));
}
