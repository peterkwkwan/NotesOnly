import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelvi_crm/features/templates/web_template_builder.dart';
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
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture web Template builder proof png', (tester) async {
    final out = File(
      '/cursor/stores/bc-f9c2cc93-7a91-4da4-99f1-9a25cab0491c/media/web-template-builder-figma.png',
    );

    final key = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _captureTheme(),
          home: const WebTemplateBuilder(onBackToLibrary: _noop),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() async {
      final ctx = key.currentContext!;
      await precacheImage(
        const AssetImage('assets/brand/notesonly-monogram.png'),
        ctx,
      );
    });
    await tester.pump();

    expect(find.text('NotesOnly'), findsNothing);
    expect(find.byTooltip('Templates'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('OUTLINE'), findsOneWidget);
    expect(find.text('+ Add question'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Presenting concerns'), findsWidgets);
    expect(find.text('Client goals'), findsOneWidget);
    expect(find.text('Live preview'), findsNothing);
    expect(find.text('Clinical interpretation'), findsNothing);

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await out.parent.create(recursive: true);
      await out.writeAsBytes(bytes!.buffer.asUint8List());
    });
    expect(out.lengthSync() > 5000, isTrue);

    await tester.tap(find.text('Objective'));
    await tester.pump();
    expect(find.text('Observations'), findsWidgets);
    expect(find.text('Presenting concerns'), findsNothing);

    await tester.tap(find.text('Subjective'));
    await tester.pump();
    expect(find.text('Presenting concerns'), findsWidgets);
    await tester.tap(find.text('More'));
    await tester.pump();
    expect(find.text('Help text'), findsOneWidget);
    expect(find.text('Placeholder'), findsOneWidget);
    expect(find.text('Required'), findsOneWidget);
    expect(find.text('Delete question'), findsOneWidget);

    await tester.tap(find.text('Preview'));
    await tester.pump();
    expect(find.text('Clinical interpretation'), findsOneWidget);
    await tester.tap(find.text('Preview'));
    await tester.pump();
    expect(find.text('Clinical interpretation'), findsNothing);

    await tester.tap(find.text('+ Add question'));
    await tester.pump();
    expect(find.text('New question'), findsWidgets);

    await tester.tap(find.text('Long text').last);
    await tester.pumpAndSettle();
    expect(find.text('Short text'), findsWidgets);
    expect(find.text('Single choice'), findsOneWidget);
    expect(find.text('Multiple choice'), findsOneWidget);
    expect(find.text('Numeric'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));
}

void _noop() {}
