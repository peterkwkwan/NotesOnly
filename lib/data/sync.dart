import 'dart:async';

/// Sync surface for Drift ↔ Firestore (offline-first).
abstract class SyncEngine {
  /// Kick a debounced push/pull when local rows become dirty.
  Future<void> enqueueLocalChange(String entity, int id);

  /// Push pending + pull since cursors. No-op when signed out.
  Future<SyncStatus> syncNow();

  Stream<SyncStatus> watchStatus();

  /// Last error message when [SyncStatus.error], else null.
  String? get lastError;

  /// Bind lifecycle: call when user is signed in; stop when signed out.
  void start();

  void stop();

  /// App resumed — pull/push if signed in.
  void onAppResumed();
}

enum SyncStatus {
  idle,
  pending,
  syncing,
  synced,
  error,
}

/// Last-write-wins: remote wins when its `updatedAt` is >= local.
bool remoteWinsLww(DateTime localUpdatedAt, DateTime remoteUpdatedAt) {
  return !remoteUpdatedAt.isBefore(localUpdatedAt);
}

/// Timeouts / unavailable / socket failures — UI should show pending, not Syncing.
bool isTransientSyncFailure(Object error) {
  if (error is TimeoutException) return true;
  final s = error.toString().toLowerCase();
  if (s.contains('unavailable')) return true;
  if (s.contains('deadline-exceeded')) return true;
  if (s.contains('network')) return true;
  if (s.contains('socket')) return true;
  if (s.contains('offline')) return true;
  if (s.contains('connection')) return true;
  return false;
}

/// No-op sync — tests / unsigned tooling.
class StubSyncEngine implements SyncEngine {
  const StubSyncEngine();

  @override
  String? get lastError => null;

  @override
  Future<void> enqueueLocalChange(String entity, int id) async {}

  @override
  Future<SyncStatus> syncNow() async => SyncStatus.idle;

  @override
  Stream<SyncStatus> watchStatus() => Stream.value(SyncStatus.idle);

  @override
  void start() {}

  @override
  void stop() {}

  @override
  void onAppResumed() {}
}
