import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelvi_crm/data/database.dart';
import 'package:pelvi_crm/data/database_provider.dart';
import 'package:pelvi_crm/data/sync.dart';
import 'package:pelvi_crm/features/notes/web_soap_note_workspace.dart';
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

  testWidgets('capture web SOAP note workspace proof png', (tester) async {
    final out = File(
      '/cursor/stores/bc-f9c2cc93-7a91-4da4-99f1-9a25cab0491c/media/web-soap-note-figma.png',
    );
    final db = AppDatabase(NativeDatabase.memory());
    await db.ensureDefaults();
    await db.setPractitionerName('Mandy Shum');

    final tom = await db.insertClient(
      firstName: 'Tom',
      lastName: 'Brady',
      phone: '5550100',
    );
    // Prefer appointment-linked notes (product rule).
    final when = DateTime(2026, 11, 7, 10);
    final appt = await db.insertAppointment(
      clientId: tom,
      startsAt: when,
    );
    final note = await db.getOrCreateNoteForAppointment(
      appointmentId: appt,
      clientId: tom,
      noteDate: when,
    );

    final key = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const crumb = 'SOAP notes / Tom Brady / 7 Nov 2026';
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
              index: DesktopDest.soapNotes,
              goTo: (_) {},
              breadcrumb: crumb,
              soapNoteId: note.id,
              openSoapNote: (_) {},
              child: SizedBox(
                width: 1440,
                height: 1000,
                child: Scaffold(
                  body: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DesktopSidebar(
                        index: DesktopDest.soapNotes,
                        onSelect: _noopSelect,
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            const DesktopTopBar(),
                            Expanded(
                              child: WebSoapNoteWorkspace(
                                noteId: note.id,
                                onBreadcrumb: (_) {},
                              ),
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
    expect(find.text('SOAP note'), findsWidgets);
    expect(find.text('Tom Brady'), findsWidgets);
    expect(find.text('NOTE OUTLINE'), findsOneWidget);
    expect(find.text('Subjective'), findsWidgets);
    expect(find.text('Note context'), findsOneWidget);
    expect(find.text('Revision history'), findsOneWidget);
    expect(find.text('Save draft'), findsOneWidget);
    expect(find.textContaining('Appointment'), findsWidgets);

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
