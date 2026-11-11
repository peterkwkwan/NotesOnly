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

/// Org pulls page this many documents, then continue while the page is full.
const syncPullPageSize = 200;

/// Pull cursor: `updatedAt`, then the last document id.
///
/// A bare ISO-8601 timestamp is a cursor from before tie-breaks. Those resume
/// with `updatedAt >= t` so rows stamped on that instant are not dropped.
class SyncPullCursor {
  const SyncPullCursor(this.updatedAt, [this.docId]);

  final DateTime updatedAt;
  final String? docId;

  static SyncPullCursor? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final tab = raw.indexOf('\t');
    final stamp = tab < 0 ? raw : raw.substring(0, tab);
    final at = DateTime.parse(stamp).toUtc();
    if (tab < 0) return SyncPullCursor(at);
    final id = raw.substring(tab + 1);
    return id.isEmpty ? SyncPullCursor(at) : SyncPullCursor(at, id);
  }

  String encode() {
    final stamp = updatedAt.toUtc().toIso8601String();
    final id = docId;
    if (id == null || id.isEmpty) return stamp;
    return '$stamp\t$id';
  }
}

/// `afterId` null includes every row at [notBefore] (legacy timestamp cursors).
({DateTime? notBefore, String? afterId}) syncPullBound(SyncPullCursor? cursor) {
  final id = cursor?.docId;
  return (
    notBefore: cursor?.updatedAt,
    afterId: (id == null || id.isEmpty) ? null : id,
  );
}

/// Pull order is `updatedAt`, then document id.
/// A cursor with no document id is before every row at that timestamp.
bool syncPullCursorBefore(
  SyncPullCursor cursor,
  DateTime updatedAt,
  String docId,
) {
  final at = updatedAt.toUtc();
  final prev = cursor.updatedAt.toUtc();
  if (at.isAfter(prev)) return true;
  if (at.isBefore(prev)) return false;
  final prevId = cursor.docId;
  if (prevId == null || prevId.isEmpty) return true;
  return docId.compareTo(prevId) > 0;
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
