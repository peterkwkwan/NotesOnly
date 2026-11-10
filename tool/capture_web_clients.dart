import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelvi_crm/data/database.dart';
import 'package:pelvi_crm/data/database_provider.dart';
import 'package:pelvi_crm/data/sync.dart';
import 'package:pelvi_crm/features/clients/web_clients_dashboard.dart';
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

  testWidgets('capture web Clients + desktop shell proof png', (tester) async {
    final out = File(
      '/cursor/stores/bc-f9c2cc93-7a91-4da4-99f1-9a25cab0491c/media/web-clients-figma.png',
    );
    final db = AppDatabase(NativeDatabase.memory());
    await db.ensureDefaults();
    await db.setPractitionerName('Mandy Shum');
    await db.setRecallDays(14);

    final stewie = await db.insertClient(
      firstName: 'Stewie',
      lastName: 'Brown',
      phone: '11234951',
      email: 'peopeeep1@gmail.com',
    );
    final steph = await db.insertClient(
      firstName: 'Steph',
      lastName: 'Curry',
      phone: '10491231',
      email: 'petiownet@gmail.com',
    );
    final susan = await db.insertClient(
      firstName: 'Susan',
      lastName: 'Johnson',
      phone: '60174382',
      email: 'peterkwkwan@gmail.com',
    );
    final peter = await db.insertClient(
      firstName: 'Peter',
      lastName: 'Kwan',
      phone: '60174382',
      email: 'peterkwkwan@gmail.com',
    );
    final tom = await db.insertClient(
      firstName: 'Tom',
      lastName: 'Brady',
    );
    await db.insertClient(
      firstName: 'Steve',
      lastName: 'Balmer',
      phone: '83014293',
      email: 'petiowne@gmail.com',
    );
    final susie = await db.insertClient(
      firstName: 'Susie',
      lastName: 'Rose',
      phone: '5550400',
    );

    await db.setClientsPinned([stewie], true);
    await db.touchRecentClient(susie);
    await db.touchRecentClient(tom);
    await db.touchRecentClient(steph);
    await db.touchRecentClient(peter);

    final now = DateTime.now();
    final old = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 21));
    await db.insertAppointment(
      clientId: susan,
      startsAt: DateTime(old.year, old.month, old.day, 11),
    );

    final key = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(1440, 1175));
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
                  size: const Size(1440, 1175),
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
              index: DesktopDest.clients,
              goTo: (_) {},
              breadcrumb: DesktopDest.breadcrumbFor(DesktopDest.clients),
              child: SizedBox(
                width: 1440,
                height: 1175,
                child: Scaffold(
                  body: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DesktopSidebar(
                        index: DesktopDest.clients,
                        onSelect: _noopSelect,
                      ),
                      const Expanded(
                        child: Column(
                          children: [
                            const DesktopTopBar(),
                            Expanded(child: WebClientsDashboard()),
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
    expect(find.text('Keep people, contact details and recalls in one place'),
        findsOneWidget);
    expect(find.text('Recall review'), findsOneWidget);
    expect(find.text('Your recall window'), findsOneWidget);
    expect(find.text('PINNED'), findsOneWidget);
    expect(find.text('Due (1)'), findsOneWidget);
    expect(find.text('Stewie Brown'), findsWidgets);
    expect(find.text('14 days'), findsOneWidget);

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.25);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await out.parent.create(recursive: true);
      await out.writeAsBytes(bytes!.buffer.asUint8List());
    });
    expect(out.lengthSync() > 5000, isTrue);
    // Drift stream timers trip flutter_test invariants after PNG write (same as Today capture).
  }, timeout: const Timeout(Duration(seconds: 60)));
}

void _noopSelect(int _) {}
