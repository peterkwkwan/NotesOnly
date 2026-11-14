import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/auth.dart';
import 'data/database.dart';
import 'data/database_provider.dart';
import 'data/google_calendar_sync.dart';
import 'data/join_token.dart';
import 'data/org.dart';
import 'data/org_directory.dart';
import 'data/sync.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/first_run/first_run_screen.dart';
import 'features/org/org_access_screen.dart';
import 'features/shell/app_shell.dart';
import 'theme/theme.dart';
import 'widgets/show_snack.dart';

export 'data/database_provider.dart';

class _HomeGate {
  const _HomeGate({required this.showClinic, required this.firstRun});

  const _HomeGate.waiting() : showClinic = false, firstRun = false;

  const _HomeGate.shell() : showClinic = true, firstRun = false;

  final bool showClinic;
  final bool firstRun;
}

class PelviApp extends StatefulWidget {
  const PelviApp({
    super.key,
    required this.database,
    this.syncEngine = const StubSyncEngine(),
    this.googleCalendarSync,
    /// Tests only — when set, skips Firebase Auth and treats true as signed in.
    this.signedInOverride,
  });

  final AppDatabase database;
  final SyncEngine syncEngine;
  final GoogleCalendarSync? googleCalendarSync;
  final Stream<bool>? signedInOverride;

  @override
  State<PelviApp> createState() => _PelviAppState();
}

class _PelviAppState extends State<PelviApp> with WidgetsBindingObserver {
  late Future<_HomeGate> _gate;
  StreamSubscription<User?>? _authSub;
  String? _authUid;
  final _navigatorKey = GlobalKey<NavigatorState>();
  DateTime? _lastCalendarSoftErrorAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Stash /join?token= before Google redirect drops the query string.
    captureJoinTokenFromUri();
    _gate = _loadGate();
    widget.syncEngine.start();
    final gcal = widget.googleCalendarSync;
    if (gcal != null) {
      gcal.onSoftError = _onCalendarSoftError;
      gcal.start();
    }
    _authSub = NotesAuth.authStateChanges().listen((user) {
      final uid = user?.uid;
      if (uid == _authUid) return;
      _authUid = uid;
      setState(() {
        _gate = uid == null
            ? Future.value(const _HomeGate.waiting())
            : _loadGate();
      });
    });
  }

  void _onCalendarSoftError(String message) {
    final now = DateTime.now();
    final last = _lastCalendarSoftErrorAt;
    if (last != null && now.difference(last) < const Duration(seconds: 20)) {
      return;
    }
    _lastCalendarSoftErrorAt = now;
    final ctx = _navigatorKey.currentContext;
    if (ctx == null) return;
    showPelviSnackBar(ctx, message);
  }

  /// Magic-link accept (join). create-org that needs a clinic name is handled
  /// on the waiting screen.
  Future<void> _acceptPendingJoinIfAny() async {
    final token = peekPendingJoinToken();
    if (token == null || token.isEmpty) return;
    if (NotesAuth.currentUser == null) return;
    try {
      final accepted = await OrgDirectory().acceptInviteToken(token: token);
      await widget.database.setSetting(
        AppDatabase.activeOrgIdKey,
        accepted.orgId,
      );
      await widget.database.setSetting(
        AppDatabase.activeOrgRolesKey,
        accepted.roles.join(','),
      );
      clearPendingJoinToken();
      replaceJoinUrlWithHome();
      await widget.syncEngine.syncNow();
    } catch (_) {
      // Leave token for OrgAccessScreen to show the error (and clear stale
      // rotated/revoked tokens after the message is visible).
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.syncEngine.stop();
    widget.googleCalendarSync?.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.syncEngine.onAppResumed();
      widget.googleCalendarSync?.onAppResumed();
    }
  }

  Future<_HomeGate> _loadGate() async {
    final db = widget.database;
    await db.ensureDefaults();
    await _acceptPendingJoinIfAny();
    final orgId = await db.getSetting(AppDatabase.activeOrgIdKey);
    final orgReady = orgId != null && orgId.isNotEmpty;
    final clinical = orgReady || await db.hasClinicalRows();
    if (!clinical) return const _HomeGate.waiting();
    final roles =
        parseOrgRoles(await db.getSetting(AppDatabase.activeOrgRolesKey));
    final clinic = (await db.getClinicName())?.trim() ?? '';
    final uid = NotesAuth.currentUser?.uid;
    final display = (await db.getPractitionerName(uid: uid))?.trim() ?? '';
    final canNameClinic = roles.isEmpty ||
        roles.contains(OrgRole.owner) ||
        roles.contains(OrgRole.admin);
    // Clinic label is cloud-synced; only prompt when still empty after pull.
    final needClinic = canNameClinic && clinic.isEmpty;
    // Personal name is per-uid (local + org settings); only prompt when unset.
    final needDisplay = display.isEmpty;
    if (!needClinic && !needDisplay) return const _HomeGate.shell();
    return const _HomeGate(showClinic: true, firstRun: true);
  }

  void _refreshGate() {
    setState(() {
      _gate = _loadGate();
    });
  }

  void _joinedClinic() {
    setState(() {
      _gate = _loadGate();
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
      googleCalendarSync: widget.googleCalendarSync,
      child: StreamBuilder<bool>(
        stream: widget.database.watchDarkModeEnabled(),
        initialData: false,
        builder: (context, snap) {
          final dark = snap.data ?? false;
          _applySystemUi(dark);
          return MaterialApp(
            navigatorKey: _navigatorKey,
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
                return FutureBuilder<_HomeGate>(
                  future: _gate,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      final c = PelviColors.of(context);
                      return Scaffold(
                        body: Center(
                          child: CircularProgressIndicator(color: c.pink700),
                        ),
                      );
                    }
                    final gate = snapshot.data ?? const _HomeGate.waiting();
                    if (!gate.showClinic) {
                      return OrgAccessScreen(
                        waiting: true,
                        onJoined: _joinedClinic,
                      );
                    }
                    if (gate.firstRun) {
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
