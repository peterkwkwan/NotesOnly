import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelvi_crm/data/database.dart';
import 'package:pelvi_crm/data/database_provider.dart';
import 'package:pelvi_crm/data/sync.dart';
import 'package:pelvi_crm/features/calendar/web_calendar_page.dart';
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

  testWidgets('capture web Calendar + desktop shell proof png', (tester) async {
    final out = File(
      '/cursor/stores/bc-f9c2cc93-7a91-4da4-99f1-9a25cab0491c/media/web-calendar-figma.png',
    );
    final db = AppDatabase(NativeDatabase.memory());
    await db.ensureDefaults();
    await db.setPractitionerName('Mandy Shum');
    await db.setDefaultAppointmentMinutes(60);

    final steve = await db.insertClient(
      firstName: 'Steve',
      lastName: 'Balmer',
      phone: '83014293',
    );
    await db.insertClient(
      firstName: 'Tom',
      lastName: 'Brady',
      phone: '5550100',
    );

    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    // Place a Sunday 15:00 appointment like the Figma frame.
    final sunday = monday.add(const Duration(days: 6));
    await db.insertAppointment(
      clientId: steve,
      startsAt: DateTime(sunday.year, sunday.month, sunday.day, 15),
    );

    final key = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(1440, 1119));
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
                  size: const Size(1440, 1119),
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
              index: DesktopDest.calendar,
              goTo: (_) {},
              breadcrumb: DesktopDest.breadcrumbFor(DesktopDest.calendar),
              child: SizedBox(
                width: 1440,
                height: 1119,
                child: Scaffold(
                  body: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DesktopSidebar(
                        index: DesktopDest.calendar,
                        onSelect: _noopSelect,
                      ),
                      const Expanded(
                        child: Column(
                          children: [
                            DesktopTopBar(
                              breadcrumb: 'Practice / Calendar',
                            ),
                            Expanded(child: WebCalendarPage()),
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
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('NotesOnly'), findsOneWidget);
    expect(find.text('Calendar'), findsWidgets);
    expect(find.text('Add appointment'), findsOneWidget);
    expect(find.text('New appointment'), findsOneWidget);
    expect(find.text('Week'), findsWidgets);
    expect(find.text('Steve Balmer'), findsWidgets);

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.25);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await out.parent.create(recursive: true);
      await out.writeAsBytes(bytes!.buffer.asUint8List());
    });
    expect(out.lengthSync() > 5000, isTrue);
  }, timeout: const Timeout(Duration(seconds: 90)));
}

void _noopSelect(int _) {}
