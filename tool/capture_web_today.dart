import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelvi_crm/data/database.dart';
import 'package:pelvi_crm/data/database_provider.dart';
import 'package:pelvi_crm/data/sync.dart';
import 'package:pelvi_crm/features/shell/desktop_chrome.dart';
import 'package:pelvi_crm/features/today/web_today_dashboard.dart';
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

  testWidgets('capture web Today + desktop shell proof png', (tester) async {
    final out = File(
      '/cursor/stores/bc-f9c2cc93-7a91-4da4-99f1-9a25cab0491c/media/web-today-figma.png',
    );
    final db = AppDatabase(NativeDatabase.memory());
    await db.ensureDefaults();
    await db.setPractitionerName('Mandy Shum');
    await db.setRecallDays(14);

    final steve = await db.insertClient(
      firstName: 'Steve',
      lastName: 'Balmer',
      phone: '83014293',
    );
    final tom = await db.insertClient(
      firstName: 'Tom',
      lastName: 'Brady',
      phone: '5550100',
    );
    final stewie = await db.insertClient(
      firstName: 'Stewie',
      lastName: 'Brown',
      phone: '5550200',
    );
    final dueClient = await db.insertClient(
      firstName: 'Alex',
      lastName: 'Ng',
      phone: '5550300',
    );

    final now = DateTime.now();
    await db.insertAppointment(
      clientId: steve,
      startsAt: DateTime(now.year, now.month, now.day, 15),
    );

    final yesterday = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));
    final tomAppt = await db.insertAppointment(
      clientId: tom,
      startsAt: DateTime(yesterday.year, yesterday.month, yesterday.day, 10),
    );
    await db.getOrCreateNoteForAppointment(
      appointmentId: tomAppt,
      clientId: tom,
      noteDate: yesterday,
    );

    final tomorrow = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    await db.insertAppointment(
      clientId: stewie,
      startsAt: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 14),
    );

    // Past the 14-day recall window so Client recalls shows a Due count.
    final old = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 21));
    await db.insertAppointment(
      clientId: dueClient,
      startsAt: DateTime(old.year, old.month, old.day, 11),
    );

    final key = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
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
                  size: const Size(1440, 1000),
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
              index: DesktopDest.today,
              goTo: (_) {},
              breadcrumb: DesktopDest.breadcrumbFor(DesktopDest.today),
              child: SizedBox(
                width: 1440,
                height: 1000,
                child: Scaffold(
                  body: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DesktopSidebar(
                        index: DesktopDest.today,
                        onSelect: _noopSelect,
                      ),
                      const Expanded(
                        child: Column(
                          children: [
                            DesktopTopBar(
                              breadcrumb: 'Practice / Today',
                            ),
                            Expanded(child: WebTodayDashboard()),
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
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.text('NotesOnly'), findsOneWidget);
    expect(find.text('A little more room for care.'), findsOneWidget);
    expect(find.text('Your agenda'), findsOneWidget);
    expect(find.text('Open SOAP drafts'), findsOneWidget);
    expect(find.text('Client recalls'), findsOneWidget);
    expect(find.text('Up next'), findsOneWidget);
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
    // Drift stream timers trip flutter_test invariants after PNG write (same as other captures).
  }, timeout: const Timeout(Duration(seconds: 60)));
}

void _noopSelect(int _) {}
