import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelvi_crm/data/database.dart';
import 'package:pelvi_crm/data/database_provider.dart';
import 'package:pelvi_crm/data/sync.dart';
import 'package:pelvi_crm/features/clients/web_client_profile.dart';
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

  testWidgets('capture web Client profile + desktop shell proof png', (tester) async {
    final out = File(
      '/cursor/stores/bc-f9c2cc93-7a91-4da4-99f1-9a25cab0491c/media/web-client-profile-figma.png',
    );
    final db = AppDatabase(NativeDatabase.memory());
    await db.ensureDefaults();
    await db.setPractitionerName('Mandy Shum');

    final clientId = await db.insertClient(
      firstName: 'Stewie',
      lastName: 'Brown',
      phone: '11234951',
      email: 'peopeeep1@gmail.com',
      emergencyContact: 'Becca Chambers',
      notes: 'tttttt',
    );
    await db.setClientsPinned([clientId], true);

    final nov9 = DateTime(2026, 11, 9, 14);
    final oct28 = DateTime(2026, 10, 28, 16);
    await db.insertAppointment(clientId: clientId, startsAt: nov9);
    await db.insertAppointment(clientId: clientId, startsAt: oct28);

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
              index: DesktopDest.clients,
              goTo: (_) {},
              breadcrumb: 'Clients / Stewie Brown',
              child: SizedBox(
                width: 1440,
                height: 1000,
                child: Scaffold(
                  body: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DesktopSidebar(
                        index: DesktopDest.clients,
                        onSelect: _noopSelect,
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            const DesktopTopBar(),
                            Expanded(
                              child: WebClientProfile(clientId: clientId),
                            ),
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
    expect(find.text('Client profile'), findsOneWidget);
    expect(find.text('Stewie Brown'), findsWidgets);
    expect(find.text('Contact & preferences'), findsOneWidget);
    expect(find.text('Visit & note detail'), findsOneWidget);
    expect(find.text('All history'), findsOneWidget);
    expect(find.text('Create SOAP note'), findsOneWidget);

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.25);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await out.parent.create(recursive: true);
      await out.writeAsBytes(bytes!.buffer.asUint8List());
    });
    expect(out.lengthSync() > 5000, isTrue);
    // Drift stream timers trip flutter_test invariants after PNG write (same as capture_web_today).
  }, timeout: const Timeout(Duration(seconds: 60)));
}

void _noopSelect(int _) {}
