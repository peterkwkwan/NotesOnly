import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelvi_crm/data/database.dart';
import 'package:pelvi_crm/data/database_provider.dart';
import 'package:pelvi_crm/data/sync.dart';
import 'package:pelvi_crm/features/more/web_practice_settings.dart';
import 'package:pelvi_crm/features/shell/desktop_chrome.dart';
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

  testWidgets('capture web Practice settings + desktop shell proof png',
      (tester) async {
    final out = File(
      '/cursor/stores/bc-f9c2cc93-7a91-4da4-99f1-9a25cab0491c/media/web-practice-settings-figma.png',
    );
    final db = AppDatabase(NativeDatabase.memory());
    await db.ensureDefaults();
    await db.setPractitionerName('Mandy Shum');
    await db.setRecallDays(14);
    await db.setDefaultAppointmentMinutes(60);
    await db.setClinicHoursStart('09:00');
    await db.setClinicHoursEnd('18:00');
    await db.setTimezone('Asia/Hong_Kong');
    await db.setRecallNotificationsEnabled(true);

    final key = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(1440, 1219));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: AppDatabaseProvider(
          database: db,
          syncEngine: const StubSyncEngine(),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: _captureTheme(),
            builder: (context, child) {
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: const Size(1440, 1219),
                  textScaler: TextScaler.noScaling,
                  disableAnimations: true,
                ),
                child: TickerMode(
                  enabled: false,
                  child: child ?? const SizedBox.shrink(),
                ),
              );
            },
            home: ShellNavigation(
              index: DesktopDest.practiceSettings,
              goTo: (_) {},
              breadcrumb:
                  DesktopDest.breadcrumbFor(DesktopDest.practiceSettings),
              child: SizedBox(
                width: 1440,
                height: 1219,
                child: Scaffold(
                  body: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DesktopSidebar(
                        index: DesktopDest.practiceSettings,
                        onSelect: _noopSelect,
                      ),
                      const Expanded(
                        child: Column(
                          children: [
                            const DesktopTopBar(),
                            Expanded(child: WebPracticeSettings()),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
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
    await tester.pump(const Duration(milliseconds: 50));
    // Wait for async Drift load into form fields.
    for (var i = 0; i < 20; i++) {
      if (find.text('Mandy Shum').evaluate().length >= 2) break;
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('NotesOnly'), findsOneWidget);
    expect(find.text('Practice settings'), findsWidgets);
    expect(find.text('Practice preferences'), findsWidgets);
    expect(find.text('Practitioner name'), findsOneWidget);
    expect(find.text('Scheduling defaults'), findsNothing);
    expect(find.text('Recall window'), findsNothing);
    expect(find.text('Export JSON'), findsNothing);
    expect(find.text('Save changes'), findsOneWidget);
    expect(find.text('Mandy Shum'), findsWidgets);

    await tester.tap(find.text('Members'));
    await tester.pump();
    expect(find.text('Practitioner name'), findsNothing);
    expect(find.text('Scheduling defaults'), findsNothing);

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.25);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await out.parent.create(recursive: true);
      await out.writeAsBytes(bytes!.buffer.asUint8List());
    });
    expect(out.lengthSync() > 5000, isTrue);
  }, timeout: const Timeout(Duration(seconds: 60)));
}

void _noopSelect(int _) {}
