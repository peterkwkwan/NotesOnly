import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelvi_crm/data/database.dart';
import 'package:pelvi_crm/data/database_provider.dart';
import 'package:pelvi_crm/data/sync_stub.dart';
import 'package:pelvi_crm/features/clients/clients_screen.dart';
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
      titleLarge: const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.9,
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
        height: 14 / 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.1,
        color: PelviColors.inkMuted,
      ),
      bodyMedium: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: PelviColors.ink,
      ),
    ),
    extensions: const [p],
    appBarTheme: const AppBarTheme(
      backgroundColor: PelviColors.canvas,
      foregroundColor: PelviColors.ink,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.9,
        color: PelviColors.ink,
      ),
    ),
    colorScheme: const ColorScheme.light(
      primary: PelviColors.pink700,
      onPrimary: PelviColors.inkInverse,
      secondary: PelviColors.purple700,
      surface: PelviColors.surface,
      onSurface: PelviColors.ink,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture clients screen proof png', (tester) async {
    final tmpFile = File('/tmp/clients-app-after.png');
    final db = AppDatabase(NativeDatabase.memory());
    await db.ensureDefaults();

    final steve = await db.insertClient(
      firstName: 'Steve',
      lastName: 'Balmer',
      phone: '83014293',
      email: 'petiowne@gmail.com',
    );
    final susan = await db.insertClient(
      firstName: 'Susan',
      lastName: 'Johnson',
      phone: '91234567',
      email: 'susan@example.com',
    );
    final tom = await db.insertClient(
      firstName: 'Tom',
      lastName: 'Brady',
      phone: '5550100',
      email: 'tom@example.com',
    );
    final stewie = await db.insertClient(
      firstName: 'Stewie',
      lastName: 'Brown',
      phone: '5550200',
      email: 'stewie@example.com',
    );
    final peter = await db.insertClient(
      firstName: 'Peter',
      lastName: 'Kwan',
      phone: '5550300',
      email: 'peter@example.com',
    );
    await db.setClientsPinned([steve, susan, tom, stewie, peter], true);
    await db.touchRecentClient(steve);
    await db.touchRecentClient(susan);
    await db.touchRecentClient(tom);
    await db.touchRecentClient(stewie);
    // Keep a stream subscription alive like the notifications capture.
    db.watchClients().listen((_) {});

    final key = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(390, 844));

    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: AppDatabaseProvider(
          database: db,
          syncEngine: const StubSyncEngine(),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: _captureTheme(),
            home: const ClientsScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Clients'), findsOneWidget);
    expect(find.text('PINNED'), findsOneWidget);
    expect(find.text('SB'), findsWidgets);

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await tmpFile.writeAsBytes(bytes!.buffer.asUint8List());
    });
    expect(tmpFile.lengthSync() > 1000, isTrue);

    // Drop the tree; skip db.close — Drift stream teardown hangs here.
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(seconds: 20)));
}
