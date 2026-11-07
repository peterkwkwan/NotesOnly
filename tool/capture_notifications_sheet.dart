import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelvi_crm/data/database.dart';
import 'package:pelvi_crm/data/database_provider.dart';
import 'package:pelvi_crm/data/sync_stub.dart';
import 'package:pelvi_crm/features/notifications/notifications_sheet.dart';
import 'package:pelvi_crm/theme/colors.dart';

ThemeData _captureTheme() {
  const p = PelviPalette.light;
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    textTheme: Typography.material2021().black.apply(
      bodyColor: p.ink,
      displayColor: p.ink,
    ).copyWith(
      titleLarge: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.9,
        color: PelviColors.ink,
      ),
      bodyMedium: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: PelviColors.ink,
      ),
    ),
    extensions: const [p],
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

  testWidgets('capture notifications sheet proof png', (tester) async {
    final tmpFile = File('/tmp/notifications-app-after.png');
    final db = AppDatabase(NativeDatabase.memory());
    await db.ensureDefaults();
    final now = DateTime.now();
    final clientId =
        await db.insertClient(firstName: 'Susie', lastName: 'Rose');
    await db.insertAppointment(
      clientId: clientId,
      startsAt: now.subtract(const Duration(days: 92)),
      status: AppointmentStatus.completed,
    );
    db.watchRecallDueClients().listen((_) {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final key = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(412, 916));

    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: AppDatabaseProvider(
          database: db,
          syncEngine: const StubSyncEngine(),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: _captureTheme(),
            home: Builder(
              builder: (context) => Scaffold(
                backgroundColor: PelviColors.canvas,
                body: Center(
                  child: TextButton(
                    onPressed: () => showNotificationsSheet(context),
                    child: const Text('Bell'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Bell'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Recall · Susie Rose'), findsOneWidget);
    expect(find.text('SR'), findsOneWidget);

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await tmpFile.writeAsBytes(bytes!.buffer.asUint8List());
    });
    expect(tmpFile.lengthSync() > 1000, isTrue);

    // Drop the tree; skip db.close — Drift recall stream teardown hangs here.
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(seconds: 20)));
}
