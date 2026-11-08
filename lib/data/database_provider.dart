import 'package:flutter/material.dart';

import 'database.dart';
import 'sync.dart';

/// Inherited access to the opened [AppDatabase] and sync engine.
class AppDatabaseProvider extends InheritedWidget {
  const AppDatabaseProvider({
    super.key,
    required this.database,
    required this.syncEngine,
    required super.child,
  });

  final AppDatabase database;
  final SyncEngine syncEngine;

  static AppDatabase of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<AppDatabaseProvider>();
    assert(provider != null, 'AppDatabaseProvider not found in tree');
    return provider!.database;
  }

  static SyncEngine syncOf(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<AppDatabaseProvider>();
    assert(provider != null, 'AppDatabaseProvider not found in tree');
    return provider!.syncEngine;
  }

  @override
  bool updateShouldNotify(AppDatabaseProvider oldWidget) =>
      database != oldWidget.database || syncEngine != oldWidget.syncEngine;
}
