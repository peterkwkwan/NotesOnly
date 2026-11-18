import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelvi_crm/data/database.dart';
import 'package:pelvi_crm/data/database_provider.dart';
import 'package:pelvi_crm/data/sync.dart';
import 'package:pelvi_crm/features/more/web_account_settings.dart';
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

Future<void> _pumpSettle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _writePng(GlobalKey key, File out) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1.25);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await out.parent.create(recursive: true);
  await out.writeAsBytes(bytes!.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture Account scheduling + Practice recall rows',
      (tester) async {
    final media =
        '/cursor/stores/bc-f9c2cc93-7a91-4da4-99f1-9a25cab0491c/media';
    final accountOut = File('$media/account-settings-rows.png');
    final practiceOut = File('$media/practice-settings-rows.png');
    final dropdownOut = File('$media/account-settings-dropdown-open.png');

    final db = AppDatabase(NativeDatabase.memory());
    await db.ensureDefaults();
    await db.setClinicName('Mandy Shum Clinic');
    await db.setPractitionerName('Mandy Shum');
    await db.setSetting(AppDatabase.activeOrgRolesKey, 'owner,practitioner');
    await db.setRecallDays(14);
    await db.setDefaultAppointmentMinutes(60);
    await db.setClinicHoursStart('09:00');
    await db.setClinicHoursEnd('18:00');
    await db.setTimezone('Asia/Hong_Kong');
    await db.setRecallNotificationsEnabled(true);

    Future<void> mount(Widget body, GlobalKey key) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: AppDatabaseProvider(
            database: db,
            syncEngine: const StubSyncEngine(),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: _captureTheme(),
              home: Scaffold(body: body),
            ),
          ),
        ),
      );
      await _pumpSettle(tester);
    }

    final accountKey = GlobalKey();
    await mount(const WebAccountSettings(), accountKey);
    expect(find.text('Account settings'), findsOneWidget);
    await tester.tap(find.text('Scheduling'));
    await _pumpSettle(tester);
    expect(find.text('Default duration'), findsOneWidget);
    expect(find.text('Timezone'), findsOneWidget);
    await tester.runAsync(() => _writePng(accountKey, accountOut));
    expect(accountOut.lengthSync() > 5000, isTrue);

    await tester.tap(find.text('60 minutes').first);
    await _pumpSettle(tester);
    expect(find.text('45 minutes'), findsWidgets);
    expect(find.text('90 minutes'), findsWidgets);
    await tester.runAsync(() => _writePng(accountKey, dropdownOut));
    expect(dropdownOut.lengthSync() > 5000, isTrue);

    final practiceKey = GlobalKey();
    await mount(const WebPracticeSettings(), practiceKey);
    expect(find.text('Practice settings'), findsOneWidget);
    await tester.tap(find.text('Recall management'));
    await _pumpSettle(tester);
    expect(find.text('Recall window'), findsOneWidget);
    expect(find.text('Recall notifications'), findsOneWidget);
    await tester.runAsync(() => _writePng(practiceKey, practiceOut));
    expect(practiceOut.lengthSync() > 5000, isTrue);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
