import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' hide Query;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'auth.dart';
import 'database.dart';
import 'sync.dart';

/// Drift-first sync: write local → pending → push; pull `updatedAt` > cursor; LWW.
class FirestoreSyncEngine implements SyncEngine {
  FirestoreSyncEngine(this.db, {FirebaseFirestore? firestore})
      : _fs = firestore ?? FirebaseFirestore.instance;

  final AppDatabase db;
  final FirebaseFirestore _fs;

  final _statusController = StreamController<SyncStatus>.broadcast();
  SyncStatus _status = SyncStatus.idle;
  String? _lastError;
  Timer? _debounce;
  bool _running = false;
  bool _started = false;
  StreamSubscription<User?>? _authSub;

  static const _collections = ['clients', 'appointments', 'notes', 'settings'];

  @override
  String? get lastError => _lastError;

  @override
  Stream<SyncStatus> watchStatus() async* {
    yield _status;
    yield* _statusController.stream;
  }

  void _setStatus(SyncStatus next, {String? error}) {
    _status = next;
    _lastError = error;
    if (!_statusController.isClosed) _statusController.add(next);
  }

  @override
  void start() {
    if (_started) return;
    _started = true;
    db.onLocalChange = () {
      unawaited(enqueueLocalChange('any', 0));
    };
    _authSub = NotesAuth.authStateChanges().listen((user) {
      if (user != null) {
        unawaited(syncNow());
      } else {
        _setStatus(SyncStatus.idle);
      }
    });
    if (NotesAuth.currentUser != null) {
      unawaited(syncNow());
    }
  }

  @override
  void stop() {
    _started = false;
    db.onLocalChange = null;
    _debounce?.cancel();
    _authSub?.cancel();
    _authSub = null;
  }

  @override
  void onAppResumed() {
    if (!_started || NotesAuth.currentUser == null) return;
    unawaited(syncNow());
  }

  @override
  Future<void> enqueueLocalChange(String entity, int id) async {
    _setStatus(SyncStatus.pending);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(syncNow());
    });
  }

  @override
  Future<SyncStatus> syncNow() async {
    final user = NotesAuth.currentUser;
    if (user == null) {
      _setStatus(SyncStatus.idle);
      return SyncStatus.idle;
    }
    if (_running) return _status;
    _running = true;
    _setStatus(SyncStatus.syncing);
    try {
      final bound = await db.getSetting(AppDatabase.syncBoundUidKey);
      if (bound != null && bound.isNotEmpty && bound != user.uid) {
        final hasData = (await db.select(db.clients).get()).isNotEmpty;
        if (hasData) {
          _setStatus(
            SyncStatus.error,
            error:
                'This device has data for another Google account. '
                'Export a backup, clear app data, then sign in again.',
          );
          return SyncStatus.error;
        }
      }
      await db.setSetting(AppDatabase.syncBoundUidKey, user.uid);

      final uid = user.uid;
      await _pushAll(uid);
      await _pullAll(uid);

      final pending = await _countPending();
      if (pending > 0) {
        _setStatus(SyncStatus.pending);
      } else {
        _setStatus(SyncStatus.synced);
        await db.setSetting(
          AppDatabase.syncLastSuccessKey,
          DateTime.now().toUtc().toIso8601String(),
        );
      }
      return _status;
    } catch (e, st) {
      debugPrint('Firestore sync failed: $e\n$st');
      _setStatus(SyncStatus.error, error: e.toString());
      return SyncStatus.error;
    } finally {
      _running = false;
    }
  }

  Future<int> _countPending() async {
    final clients = await (db.select(db.clients)
          ..where((t) => t.syncStatus.equals(RowSyncStatus.pending.index) |
              t.syncStatus.equals(RowSyncStatus.error.index)))
        .get();
    final appts = await (db.select(db.appointments)
          ..where((t) => t.syncStatus.equals(RowSyncStatus.pending.index) |
              t.syncStatus.equals(RowSyncStatus.error.index)))
        .get();
    final notes = await (db.select(db.notes)
          ..where((t) => t.syncStatus.equals(RowSyncStatus.pending.index) |
              t.syncStatus.equals(RowSyncStatus.error.index)))
        .get();
    final settings = await (db.select(db.settings)
          ..where((t) => t.syncStatus.equals(RowSyncStatus.pending.index) |
              t.syncStatus.equals(RowSyncStatus.error.index)))
        .get();
    final cloudSettings =
        settings.where((s) => AppDatabase.isCloudSyncedSetting(s.key));
    return clients.length + appts.length + notes.length + cloudSettings.length;
  }

  CollectionReference<Map<String, dynamic>> _col(String uid, String name) =>
      _fs.collection('users').doc(uid).collection(name);

  Future<void> _pushAll(String uid) async {
    await _pushClients(uid);
    await _pushAppointments(uid);
    await _pushNotes(uid);
    await _pushSettings(uid);
  }

  Future<void> _pushClients(String uid) async {
    final rows = await (db.select(db.clients)
          ..where((t) => t.syncStatus.equals(RowSyncStatus.pending.index) |
              t.syncStatus.equals(RowSyncStatus.error.index)))
        .get();
    for (final row in rows) {
      try {
        await _col(uid, 'clients').doc(row.remoteId).set({
          'firstName': row.firstName,
          'lastName': row.lastName,
          'phone': row.phone,
          'email': row.email,
          'joinDate': _ts(row.joinDate),
          'birthday': _ts(row.birthday),
          'emergencyContact': row.emergencyContact,
          'emergencyContactPhone': row.emergencyContactPhone,
          'notes': row.notes,
          'createdAt': _ts(row.createdAt)!,
          'updatedAt': _ts(row.updatedAt)!,
          'deletedAt': _ts(row.deletedAt),
        });
        await (db.update(db.clients)..where((t) => t.id.equals(row.id))).write(
          const ClientsCompanion(syncStatus: Value(RowSyncStatus.synced)),
        );
      } catch (e) {
        await (db.update(db.clients)..where((t) => t.id.equals(row.id))).write(
          const ClientsCompanion(syncStatus: Value(RowSyncStatus.error)),
        );
        rethrow;
      }
    }
  }

  Future<void> _pushAppointments(String uid) async {
    final rows = await (db.select(db.appointments)
          ..where((t) => t.syncStatus.equals(RowSyncStatus.pending.index) |
              t.syncStatus.equals(RowSyncStatus.error.index)))
        .get();
    for (final row in rows) {
      final client = await db.getClient(row.clientId);
      if (client == null) continue;
      try {
        await _col(uid, 'appointments').doc(row.remoteId).set({
          'clientId': client.remoteId,
          'startsAt': _ts(row.startsAt)!,
          'endsAt': _ts(row.endsAt),
          'status': row.status.index,
          'notes': row.notes,
          'createdAt': _ts(row.createdAt)!,
          'updatedAt': _ts(row.updatedAt)!,
          'deletedAt': _ts(row.deletedAt),
        });
        await (db.update(db.appointments)..where((t) => t.id.equals(row.id)))
            .write(
          const AppointmentsCompanion(syncStatus: Value(RowSyncStatus.synced)),
        );
      } catch (e) {
        await (db.update(db.appointments)..where((t) => t.id.equals(row.id)))
            .write(
          const AppointmentsCompanion(syncStatus: Value(RowSyncStatus.error)),
        );
        rethrow;
      }
    }
  }

  Future<void> _pushNotes(String uid) async {
    final rows = await (db.select(db.notes)
          ..where((t) => t.syncStatus.equals(RowSyncStatus.pending.index) |
              t.syncStatus.equals(RowSyncStatus.error.index)))
        .get();
    for (final row in rows) {
      final client = await db.getClient(row.clientId);
      if (client == null) continue;
      String? apptRemote;
      if (row.appointmentId != null) {
        final appt = await db.getAppointment(row.appointmentId!);
        apptRemote = appt?.remoteId;
      }
      try {
        await _col(uid, 'notes').doc(row.remoteId).set({
          'clientId': client.remoteId,
          'appointmentId': apptRemote,
          'noteDate': _ts(row.noteDate)!,
          'subjective': row.subjective,
          'objective': row.objective,
          'assessment': row.assessment,
          'plan': row.plan,
          'addendum': row.addendum,
          'status': row.status.index,
          'finalizedAt': _ts(row.finalizedAt),
          'createdAt': _ts(row.createdAt)!,
          'updatedAt': _ts(row.updatedAt)!,
          'deletedAt': _ts(row.deletedAt),
        });
        await (db.update(db.notes)..where((t) => t.id.equals(row.id))).write(
          const NotesCompanion(syncStatus: Value(RowSyncStatus.synced)),
        );
      } catch (e) {
        await (db.update(db.notes)..where((t) => t.id.equals(row.id))).write(
          const NotesCompanion(syncStatus: Value(RowSyncStatus.error)),
        );
        rethrow;
      }
    }
  }

  Future<void> _pushSettings(String uid) async {
    final rows = await (db.select(db.settings)
          ..where((t) => t.syncStatus.equals(RowSyncStatus.pending.index) |
              t.syncStatus.equals(RowSyncStatus.error.index)))
        .get();
    for (final row in rows) {
      if (!AppDatabase.isCloudSyncedSetting(row.key)) {
        await (db.update(db.settings)..where((t) => t.key.equals(row.key)))
            .write(
          const SettingsCompanion(syncStatus: Value(RowSyncStatus.synced)),
        );
        continue;
      }
      try {
        await _col(uid, 'settings').doc(row.key).set({
          'value': row.value,
          'updatedAt': _ts(row.updatedAt)!,
          'deletedAt': _ts(row.deletedAt),
        });
        await (db.update(db.settings)..where((t) => t.key.equals(row.key)))
            .write(
          const SettingsCompanion(syncStatus: Value(RowSyncStatus.synced)),
        );
      } catch (e) {
        await (db.update(db.settings)..where((t) => t.key.equals(row.key)))
            .write(
          const SettingsCompanion(syncStatus: Value(RowSyncStatus.error)),
        );
        rethrow;
      }
    }
  }

  Future<void> _pullAll(String uid) async {
    for (final name in _collections) {
      await _pullCollection(uid, name);
    }
  }

  Future<void> _pullCollection(String uid, String name) async {
    final cursorKey = AppDatabase.syncCursorKey(name);
    final cursorRaw = await db.getSetting(cursorKey);
    final cursor = cursorRaw == null || cursorRaw.isEmpty
        ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
        : DateTime.parse(cursorRaw).toUtc();

    Query<Map<String, dynamic>> q = _col(uid, name)
        .where('updatedAt', isGreaterThan: Timestamp.fromDate(cursor))
        .orderBy('updatedAt');

    // shortcut: single page of 200, upgrade when a practice exceeds that delta
    final snap = await q.limit(200).get();
    DateTime? maxUpdated = cursor;
    for (final doc in snap.docs) {
      final data = doc.data();
      final updated = _readTs(data['updatedAt']) ?? cursor;
      if (updated.isAfter(maxUpdated!)) maxUpdated = updated;
      switch (name) {
        case 'clients':
          await _applyClient(doc.id, data);
        case 'appointments':
          await _applyAppointment(doc.id, data);
        case 'notes':
          await _applyNote(doc.id, data);
        case 'settings':
          await _applySetting(doc.id, data);
      }
    }
    if (maxUpdated != null && maxUpdated.isAfter(cursor)) {
      await db.setSetting(cursorKey, maxUpdated.toIso8601String());
    }
  }

  Future<void> _applyClient(String remoteId, Map<String, dynamic> data) async {
    final remoteUpdated = _readTs(data['updatedAt']) ?? DateTime.now().toUtc();
    final existing = await (db.select(db.clients)
          ..where((t) => t.remoteId.equals(remoteId)))
        .getSingleOrNull();
    if (existing != null &&
        !remoteWinsLww(existing.updatedAt.toUtc(), remoteUpdated)) {
      return;
    }
    final deletedAt = _readTs(data['deletedAt']);
    final companion = ClientsCompanion(
      remoteId: Value(remoteId),
      firstName: Value((data['firstName'] as String?)?.trim() ?? 'Unknown'),
      lastName: Value((data['lastName'] as String?)?.trim() ?? 'Client'),
      phone: Value(data['phone'] as String?),
      email: Value(data['email'] as String?),
      joinDate: Value(_readTs(data['joinDate'])),
      birthday: Value(_readTs(data['birthday'])),
      emergencyContact: Value(data['emergencyContact'] as String?),
      emergencyContactPhone: Value(data['emergencyContactPhone'] as String?),
      notes: Value(data['notes'] as String?),
      createdAt: Value(_readTs(data['createdAt']) ?? remoteUpdated),
      updatedAt: Value(remoteUpdated),
      deletedAt: Value(deletedAt),
      syncStatus: const Value(RowSyncStatus.synced),
    );
    if (existing == null) {
      await db.into(db.clients).insert(companion);
    } else {
      await (db.update(db.clients)..where((t) => t.id.equals(existing.id)))
          .write(companion);
    }
  }

  Future<void> _applyAppointment(
    String remoteId,
    Map<String, dynamic> data,
  ) async {
    final remoteUpdated = _readTs(data['updatedAt']) ?? DateTime.now().toUtc();
    final clientRemote = data['clientId'] as String?;
    if (clientRemote == null) return;
    final client = await (db.select(db.clients)
          ..where((t) => t.remoteId.equals(clientRemote)))
        .getSingleOrNull();
    if (client == null) return;

    final existing = await (db.select(db.appointments)
          ..where((t) => t.remoteId.equals(remoteId)))
        .getSingleOrNull();
    if (existing != null &&
        !remoteWinsLww(existing.updatedAt.toUtc(), remoteUpdated)) {
      return;
    }
    final statusIdx = data['status'];
    final status = statusIdx is int &&
            statusIdx >= 0 &&
            statusIdx < AppointmentStatus.values.length
        ? AppointmentStatus.values[statusIdx]
        : AppointmentStatus.scheduled;
    final startsAt = _readTs(data['startsAt']);
    if (startsAt == null) return;
    final companion = AppointmentsCompanion(
      remoteId: Value(remoteId),
      clientId: Value(client.id),
      startsAt: Value(startsAt),
      endsAt: Value(_readTs(data['endsAt'])),
      status: Value(status),
      notes: Value(data['notes'] as String?),
      createdAt: Value(_readTs(data['createdAt']) ?? remoteUpdated),
      updatedAt: Value(remoteUpdated),
      deletedAt: Value(_readTs(data['deletedAt'])),
      syncStatus: const Value(RowSyncStatus.synced),
    );
    if (existing == null) {
      await db.into(db.appointments).insert(companion);
    } else {
      await (db.update(db.appointments)..where((t) => t.id.equals(existing.id)))
          .write(companion);
    }
  }

  Future<void> _applyNote(String remoteId, Map<String, dynamic> data) async {
    final remoteUpdated = _readTs(data['updatedAt']) ?? DateTime.now().toUtc();
    final clientRemote = data['clientId'] as String?;
    if (clientRemote == null) return;
    final client = await (db.select(db.clients)
          ..where((t) => t.remoteId.equals(clientRemote)))
        .getSingleOrNull();
    if (client == null) return;

    int? appointmentLocalId;
    final apptRemote = data['appointmentId'] as String?;
    if (apptRemote != null) {
      final appt = await (db.select(db.appointments)
            ..where((t) => t.remoteId.equals(apptRemote)))
          .getSingleOrNull();
      appointmentLocalId = appt?.id;
    }

    final existing = await (db.select(db.notes)
          ..where((t) => t.remoteId.equals(remoteId)))
        .getSingleOrNull();
    if (existing != null &&
        !remoteWinsLww(existing.updatedAt.toUtc(), remoteUpdated)) {
      return;
    }
    final statusIdx = data['status'];
    final status = statusIdx is int &&
            statusIdx >= 0 &&
            statusIdx < NoteStatus.values.length
        ? NoteStatus.values[statusIdx]
        : NoteStatus.draft;
    final noteDate = _readTs(data['noteDate']);
    if (noteDate == null) return;
    final companion = NotesCompanion(
      remoteId: Value(remoteId),
      clientId: Value(client.id),
      appointmentId: Value(appointmentLocalId),
      noteDate: Value(noteDate),
      subjective: Value((data['subjective'] as String?) ?? ''),
      objective: Value((data['objective'] as String?) ?? ''),
      assessment: Value((data['assessment'] as String?) ?? ''),
      plan: Value((data['plan'] as String?) ?? ''),
      addendum: Value((data['addendum'] as String?) ?? ''),
      status: Value(status),
      finalizedAt: Value(_readTs(data['finalizedAt'])),
      createdAt: Value(_readTs(data['createdAt']) ?? remoteUpdated),
      updatedAt: Value(remoteUpdated),
      deletedAt: Value(_readTs(data['deletedAt'])),
      syncStatus: const Value(RowSyncStatus.synced),
    );
    if (existing == null) {
      await db.into(db.notes).insert(companion);
    } else {
      await (db.update(db.notes)..where((t) => t.id.equals(existing.id)))
          .write(companion);
    }
  }

  Future<void> _applySetting(String key, Map<String, dynamic> data) async {
    if (!AppDatabase.isCloudSyncedSetting(key)) return;
    final remoteUpdated = _readTs(data['updatedAt']) ?? DateTime.now().toUtc();
    final existing = await (db.select(db.settings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    if (existing != null &&
        !remoteWinsLww(existing.updatedAt.toUtc(), remoteUpdated)) {
      return;
    }
    final value = data['value']?.toString();
    if (value == null) return;
    await db.into(db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: key,
            value: value,
            updatedAt: Value(remoteUpdated),
            deletedAt: Value(_readTs(data['deletedAt'])),
            syncStatus: const Value(RowSyncStatus.synced),
          ),
        );
  }

  static Timestamp? _ts(DateTime? dt) =>
      dt == null ? null : Timestamp.fromDate(dt.toUtc());

  static DateTime? _readTs(Object? raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate().toUtc();
    if (raw is DateTime) return raw.toUtc();
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw)?.toUtc();
    return null;
  }

  void dispose() {
    stop();
    _debounce?.cancel();
    _statusController.close();
  }
}
