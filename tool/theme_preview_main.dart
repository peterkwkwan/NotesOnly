import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:pelvi_crm/data/database.dart';
import 'package:pelvi_crm/data/database_provider.dart';
import 'package:pelvi_crm/data/sync.dart';
import 'package:pelvi_crm/features/more/more_screen.dart';
import 'package:pelvi_crm/features/today/today_screen.dart';
import 'package:pelvi_crm/theme/theme.dart';

/// Preview harness for light/dark screenshots (phone frame on desktop).
///
/// ```
/// flutter build linux -t tool/theme_preview_main.dart \
///   --dart-define=DARK=1 --dart-define=SCREEN=settings
/// ```
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase(NativeDatabase.memory());
  await db.ensureDefaults();
  await db.setPractitionerName('Mandy Shum');
  final dark = const String.fromEnvironment('DARK', defaultValue: '0') == '1';
  final screen = const String.fromEnvironment('SCREEN', defaultValue: 'settings');
  await db.setDarkModeEnabled(dark);
  final phone = screen == 'today' ? const TodayScreen() : const MoreScreen();
  runApp(
    AppDatabaseProvider(
      database: db,
      syncEngine: const StubSyncEngine(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: pelviLightTheme(),
        darkTheme: pelviDarkTheme(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: Scaffold(
          backgroundColor: dark ? PelviPalette.dark.canvas : PelviPalette.light.canvas,
          body: Center(
            child: SizedBox(width: 412, height: 916, child: phone),
          ),
        ),
      ),
    ),
  );
}
