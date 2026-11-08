import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/auth.dart';
import 'data/database.dart';
import 'data/database_provider.dart';
import 'data/sync.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/first_run/first_run_screen.dart';
import 'features/shell/app_shell.dart';
import 'theme/theme.dart';

export 'data/database_provider.dart';

class PelviApp extends StatefulWidget {
  const PelviApp({
    super.key,
    required this.database,
    this.syncEngine = const StubSyncEngine(),
    /// Tests only — when set, skips Firebase Auth and treats true as signed in.
    this.signedInOverride,
  });

  final AppDatabase database;
  final SyncEngine syncEngine;
  final Stream<bool>? signedInOverride;

  @override
  State<PelviApp> createState() => _PelviAppState();
}

class _PelviAppState extends State<PelviApp> with WidgetsBindingObserver {
  late Future<bool> _needsFirstRun;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _needsFirstRun = _checkFirstRun();
    widget.syncEngine.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.syncEngine.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.syncEngine.onAppResumed();
    }
  }

  Future<bool> _checkFirstRun() async {
    await widget.database.ensureDefaults();
    final name = await widget.database.getPractitionerName();
    return name == null || name.trim().isEmpty;
  }

  void _refreshGate() {
    setState(() {
      _needsFirstRun = Future.value(false);
    });
  }

  void _applySystemUi(bool dark) {
    final p = dark ? PelviPalette.dark : PelviPalette.light;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: p.canvas,
        systemNavigationBarIconBrightness:
            dark ? Brightness.light : Brightness.dark,
      ),
    );
  }

  Stream<bool> get _signedIn {
    final override = widget.signedInOverride;
    if (override != null) return override;
    return NotesAuth.authStateChanges().map((User? u) => u != null);
  }

  @override
  Widget build(BuildContext context) {
    return AppDatabaseProvider(
      database: widget.database,
      syncEngine: widget.syncEngine,
      child: StreamBuilder<bool>(
        stream: widget.database.watchDarkModeEnabled(),
        initialData: false,
        builder: (context, snap) {
          final dark = snap.data ?? false;
          _applySystemUi(dark);
          return MaterialApp(
            title: 'NotesOnly',
            debugShowCheckedModeBanner: false,
            theme: pelviLightTheme(),
            darkTheme: pelviDarkTheme(),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: StreamBuilder<bool>(
              stream: _signedIn,
              builder: (context, authSnap) {
                if (authSnap.connectionState == ConnectionState.waiting &&
                    !authSnap.hasData) {
                  final c = PelviColors.of(context);
                  return Scaffold(
                    body: Center(
                      child: CircularProgressIndicator(color: c.pink700),
                    ),
                  );
                }
                if (authSnap.data != true) {
                  return const SignInScreen();
                }
                return FutureBuilder<bool>(
                  future: _needsFirstRun,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      final c = PelviColors.of(context);
                      return Scaffold(
                        body: Center(
                          child: CircularProgressIndicator(color: c.pink700),
                        ),
                      );
                    }
                    if (snapshot.data == true) {
                      return FirstRunScreen(onComplete: _refreshGate);
                    }
                    return const AppShell();
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}
