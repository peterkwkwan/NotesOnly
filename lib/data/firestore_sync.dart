import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' hide Query;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'auth.dart';
import 'database.dart';
import 'org.dart';
import 'org_directory.dart';
import 'sync.dart';

/// Drift-first sync: write local → pending → push; pull after the cursor; LWW.
class FirestoreSyncEngine implements SyncEngine {
  FirestoreSyncEngine(this.db, {FirebaseFirestore? firestore})
      : _fs = firestore ?? FirebaseFirestore.instance;

  final AppDatabase db;
  final FirebaseFirestore _fs;
  late final OrgDirectory _orgs = OrgDirectory(firestore: _fs);

  final _statusController = StreamController<SyncStatus>.broadcast();
  SyncStatus _status = SyncStatus.idle;
  String? _lastError;
  Timer? _debounce;
  bool _running = false;
  bool _started = false;
  int _syncGen = 0;
  StreamSubscription<User?>? _authSub;

  static const _collections = [
    'clients',
    'appointments',
    'notes',
    'settings',
    'templates',
  ];
  /// Airplane / flaky network: don't leave UI on Syncing forever.
  static const _syncTimeout = Duration(seconds: 60);
  /// First clients catch-up after a stuck cursor (~500 rows × Drift applies).
  static const _clientsCatchUpTimeout = Duration(minutes: 3);

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
    final gen = ++_syncGen;
    _running = true;
    _setStatus(SyncStatus.syncing);
    try {
      final catchUpClients =
          await db.getSetting(AppDatabase.clientsCursorResetV1Key) !=
              syncPullMarker;
      await _runSync(user).timeout(
        catchUpClients ? _clientsCatchUpTimeout : _syncTimeout,
      );
      if (gen != _syncGen) return _status;
      return _status;
    } on TimeoutException catch (e, st) {
      debugPrint('Firestore sync timed out: $e\n$st');
      if (gen == _syncGen) await _settleUnavailable();
      return _status;
    } catch (e, st) {
      debugPrint('Firestore sync failed: $e\n$st');
      if (gen != _syncGen) return _status;
      if (isTransientSyncFailure(e)) {
        await _settleUnavailable();
      } else {
        _setStatus(SyncStatus.error, error: e.toString());
      }
      return _status;
    } finally {
      if (gen == _syncGen) _running = false;
    }
  }

  Future<void> _runSync(User user) async {
    final bound = await db.getSetting(AppDatabase.syncBoundUidKey);
    if (bound != null && bound.isNotEmpty && bound != user.uid) {
      await db.clearLocalClinicForAccountSwitch();
    }
    await db.setSetting(AppDatabase.syncBoundUidKey, user.uid);

    final orgId = await _ensureActiveOrg(user);
    if (orgId == null) {
      _setStatus(SyncStatus.idle);
      return;
    }
    await _pushAll(orgId, user);
    final catchUpClients = await _resetClientsCursorOnce();
    await _pullAll(orgId, user);
    if (catchUpClients) {
      await db.setSetting(AppDatabase.clientsCursorResetV1Key, syncPullMarker);
    }
    if (await db.getSetting(AppDatabase.legacyImportedKey) != '1') {
      await _importLegacy(user);
      await db.backfillPractitionerUid(user.uid);
      await db.setSetting(AppDatabase.legacyImportedKey, '1');
      await _pushAll(orgId, user);
    }

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
  }

  Future<String?> _ensureActiveOrg(User user) async {
    final existing = await db.getSetting(AppDatabase.activeOrgIdKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final snap = await _fs
        .collection('memberships')
        .where('uid', isEqualTo: user.uid)
        .limit(20)
        .get();
    final active = [
      for (final doc in snap.docs)
        if (doc.data()['active'] == true) doc,
    ];
    if (active.isNotEmpty) {
      active.sort((a, b) {
        final aOwner = _roleList(a).contains('owner') ? 0 : 1;
        final bOwner = _roleList(b).contains('owner') ? 0 : 1;
        return aOwner.compareTo(bOwner);
      });
      final picked = active.first;
      final orgId = picked.data()['orgId'] as String;
      // Settings before bind so the home gate sees practitioner name.
      await _pullCollection(orgId, 'settings');
      await _bindOrg(orgId, _roleList(picked).join(','));
      return orgId;
    }

    final hasLocal = await db.hasClinicalRows();
    var hasRemote = false;
    if (!hasLocal && isPlatformAdminEmail(user.email)) {
      hasRemote = await _legacyHasClinical(user.uid);
    }
    if (!shouldMigrateLegacyBook(
      email: user.email,
      hasMembership: false,
      hasClinical: hasLocal || hasRemote,
    )) {
      return null;
    }

    final practice = (await db.getClinicName())?.trim();
    final name =
        (practice == null || practice.isEmpty) ? 'NotesOnly' : practice;
    final orgId = await _orgs.createMigratedOrg(user: user, name: name);
    await _bindOrg(orgId, 'owner,practitioner');
    await _importLegacy(user);
    await db.backfillPractitionerUid(user.uid);
    await db.markClinicalPending();
    await db.setSetting(AppDatabase.legacyImportedKey, '1');
    return orgId;
  }

  List<String> _roleList(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final raw = doc.data()['roles'];
    if (raw is! List) return const [];
    return [for (final role in raw) role.toString()];
  }

  Future<void> _bindOrg(String orgId, String roles) async {
    final prev = await db.getSetting(AppDatabase.activeOrgIdKey);
    await db.setSetting(AppDatabase.activeOrgIdKey, orgId);
    await db.setSetting(AppDatabase.activeOrgRolesKey, roles);
    if (prev == orgId) return;
    for (final name in _collections) {
      await db.setSetting(AppDatabase.syncCursorKey(name), '');
    }
  }

  Future<bool> _legacyHasClinical(String uid) async {
    for (final name in ['clients', 'appointments', 'notes']) {
      final snap = await _fs
          .collection('users')
          .doc(uid)
          .collection(name)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) return true;
    }
    return false;
  }

  Future<void> _importLegacy(User user) async {
    for (final name in _collections) {
      Query<Map<String, dynamic>> page = _fs
          .collection('users')
          .doc(user.uid)
          .collection(name)
          .orderBy('updatedAt')
          .limit(200);
      while (true) {
        final snap = await page.get();
        if (snap.docs.isEmpty) break;
        for (final doc in snap.docs) {
          final data = doc.data();
          switch (name) {
            case 'clients':
              await _applyClient(doc.id, data, pending: true);
            case 'appointments':
              await _applyAppointment(doc.id, data, pending: true);
            case 'notes':
              await _applyNote(doc.id, data, pending: true);
            case 'settings':
              await _applySetting(doc.id, data, pending: true);
            case 'templates':
              // Org templates are not imported from users/{uid}.
              break;
          }
        }
        if (snap.docs.length < 200) break;
        page = _fs
            .collection('users')
            .doc(user.uid)
            .collection(name)
            .orderBy('updatedAt')
            .startAfterDocument(snap.docs.last)
            .limit(200);
      }
    }
  }

  Future<Set<String>> _roleNames() async {
    final raw = await db.getSetting(AppDatabase.activeOrgRolesKey) ?? '';
    return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();
  }

  bool _seesAllAppointments(Set<String> roles) =>
      roles.contains('owner') || roles.contains('admin');

  bool _seesNotes(Set<String> roles) =>
      roles.contains('owner') || roles.contains('practitioner');

  /// Offline / timeout: Pending if dirty rows, else keep Synced when we have a
  /// last-success stamp — never leave Syncing.
  Future<void> _settleUnavailable() async {
    final pending = await _countPending();
    if (pending > 0) {
      _setStatus(SyncStatus.pending);
      return;
    }
    final last = await db.getSetting(AppDatabase.syncLastSuccessKey);
    if (last != null && last.isNotEmpty) {
      _setStatus(SyncStatus.synced);
    } else {
      _setStatus(SyncStatus.pending);
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
    final templates = await (db.select(db.templates)
          ..where((t) => t.syncStatus.equals(RowSyncStatus.pending.index) |
              t.syncStatus.equals(RowSyncStatus.error.index)))
        .get();
    return clients.length +
        appts.length +
        notes.length +
        cloudSettings.length +
        templates.length;
  }

  CollectionReference<Map<String, dynamic>> _col(String orgId, String name) =>
      _fs.collection('orgs').doc(orgId).collection(name);

  Future<void> _pushAll(String orgId, User user) async {
    final roles = await _roleNames();
    await _pushClients(orgId);
    await _pushAppointments(orgId, user);
    if (_seesNotes(roles)) await _pushNotes(orgId, user);
    await _pushTemplates(orgId, user);
    await _pushSettings(orgId, roles);
  }

  Future<void> _pushClients(String orgId) async {
    final rows = await (db.select(db.clients)
          ..where((t) => t.syncStatus.equals(RowSyncStatus.pending.index) |
              t.syncStatus.equals(RowSyncStatus.error.index)))
        .get();
    for (final row in rows) {
      try {
        await _col(orgId, 'clients').doc(row.remoteId).set({
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

  Future<void> _pushAppointments(String orgId, User user) async {
    final rows = await (db.select(db.appointments)
          ..where((t) => t.syncStatus.equals(RowSyncStatus.pending.index) |
              t.syncStatus.equals(RowSyncStatus.error.index)))
        .get();
    for (final row in rows) {
      final client = await db.getClient(row.clientId);
      if (client == null) continue;
      final practitioner = row.practitionerUid.isEmpty
          ? user.uid
          : row.practitionerUid;
      try {
        await _col(orgId, 'appointments').doc(row.remoteId).set({
          'clientId': client.remoteId,
          'practitionerUid': practitioner,
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

  Future<void> _pushNotes(String orgId, User user) async {
    final rows = await (db.select(db.notes)
          ..where((t) => t.syncStatus.equals(RowSyncStatus.pending.index) |
              t.syncStatus.equals(RowSyncStatus.error.index)))
        .get();
    for (final row in rows) {
      final client = await db.getClient(row.clientId);
      if (client == null) continue;
      String? apptRemote;
      var practitioner = row.practitionerUid;
      if (row.appointmentId != null) {
        final appt = await db.getAppointment(row.appointmentId!);
        apptRemote = appt?.remoteId;
        if (practitioner.isEmpty && appt != null) {
          practitioner = appt.practitionerUid;
        }
      }
      if (practitioner.isEmpty) practitioner = user.uid;
      try {
        await _col(orgId, 'notes').doc(row.remoteId).set({
          'clientId': client.remoteId,
          'appointmentId': apptRemote,
          'practitionerUid': practitioner,
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

  Future<void> _pushTemplates(String orgId, User user) async {
    final rows = await (db.select(db.templates)
          ..where((t) => t.syncStatus.equals(RowSyncStatus.pending.index) |
              t.syncStatus.equals(RowSyncStatus.error.index)))
        .get();
    for (final raw in rows) {
      final row = await db.ensureTemplateCreator(
        raw,
        uid: user.uid,
        name: user.displayName?.trim() ?? '',
      );
      try {
        await _col(orgId, 'templates').doc(row.remoteId).set({
          'name': row.name,
          'description': row.description,
          'fieldsJson': row.fieldsJson,
          'createdBy': row.createdBy,
          'createdByName': row.createdByName,
          'createdAt': _ts(row.createdAt)!,
          'updatedAt': _ts(row.updatedAt)!,
          'deletedAt': _ts(row.deletedAt),
        });
        await (db.update(db.templates)..where((t) => t.id.equals(row.id)))
            .write(
          const TemplatesCompanion(syncStatus: Value(RowSyncStatus.synced)),
        );
      } catch (e) {
        await (db.update(db.templates)..where((t) => t.id.equals(row.id)))
            .write(
          const TemplatesCompanion(syncStatus: Value(RowSyncStatus.error)),
        );
        rethrow;
      }
    }
  }

  Future<void> _pushSettings(String orgId, Set<String> roles) async {
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
        await _col(orgId, 'settings').doc(row.key).set({
          'value': row.value,
          'updatedAt': _ts(row.updatedAt)!,
          'deletedAt': _ts(row.deletedAt),
        });
        if (row.key == AppDatabase.clinicNameKey &&
            (roles.contains('owner') || roles.contains('admin'))) {
          await _fs.collection('orgs').doc(orgId).update({
            'name': row.value,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
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

  /// Clears a clients cursor parked on a shared CSV import timestamp so the
  /// next pull walks the whole collection again (once per install).
  /// Returns true when catch-up must run; marker is written only after pull.
  Future<bool> _resetClientsCursorOnce() async {
    if (await db.getSetting(AppDatabase.clientsCursorResetV1Key) ==
        syncPullMarker) {
      return false;
    }
    await db.setSetting(AppDatabase.syncCursorKey('clients'), '');
    return true;
  }

  Future<void> _pullAll(String orgId, User user) async {
    final roles = await _roleNames();
    for (final name in _collections) {
      if (name == 'notes' && !_seesNotes(roles)) continue;
      final filter = (name == 'appointments' && !_seesAllAppointments(roles)) ||
              (name == 'notes' && !roles.contains('owner'))
          ? user.uid
          : null;
      await _pullCollection(orgId, name, practitionerUid: filter);
    }
  }

  Future<void> _pullCollection(
    String orgId,
    String name, {
    String? practitionerUid,
  }) async {
    final cursorKey = AppDatabase.syncCursorKey(name);
    var cursor = SyncPullCursor.decode(await db.getSetting(cursorKey));

    // Empty clients cursor: page by document id only (same updatedAt is fine).
    if (name == 'clients' && cursor == null) {
      await _pullAllClientsByDocumentId(orgId, cursorKey);
      return;
    }

    QueryDocumentSnapshot<Map<String, dynamic>>? afterDoc;
    var unstuckOnce = false;

    while (true) {
      final snap = await _pullPage(
        orgId,
        name,
        practitionerUid: practitionerUid,
        cursor: afterDoc == null ? cursor : null,
        afterDoc: afterDoc,
      ).get();
      if (snap.docs.isEmpty) return;

      for (final doc in snap.docs) {
        final data = doc.data();
        switch (name) {
          case 'clients':
            await _applyClient(doc.id, data);
          case 'appointments':
            await _applyAppointment(doc.id, data);
          case 'notes':
            await _applyNote(doc.id, data);
          case 'settings':
            await _applySetting(doc.id, data);
          case 'templates':
            await _applyTemplate(doc.id, data);
        }
      }

      final last = snap.docs.last;
      final updated = _readTs(last.data()['updatedAt']);
      if (updated == null) return;
      // Non-advancing page: clear cursor once, then stop (no silent forever stall).
      if (cursor != null && !syncPullCursorBefore(cursor, updated, last.id)) {
        if (!unstuckOnce) {
          unstuckOnce = true;
          cursor = null;
          afterDoc = null;
          await db.setSetting(cursorKey, '');
          if (name == 'clients') {
            await _pullAllClientsByDocumentId(orgId, cursorKey);
            return;
          }
          continue;
        }
        return;
      }
      cursor = SyncPullCursor(updated, last.id);
      await db.setSetting(cursorKey, cursor.encode());
      if (snap.docs.length < syncPullPageSize) return;
      // Full page: keep going from the last doc (exact Timestamp, not re-encoded).
      afterDoc = last;
    }
  }

  /// Full clients download by `__name__` — ignores shared CSV `updatedAt` ties.
  Future<void> _pullAllClientsByDocumentId(
    String orgId,
    String cursorKey,
  ) async {
    QueryDocumentSnapshot<Map<String, dynamic>>? after;
    SyncPullCursor? maxCursor;
    while (true) {
      Query<Map<String, dynamic>> q = _col(orgId, 'clients')
          .orderBy(FieldPath.documentId)
          .limit(syncPullPageSize);
      if (after != null) {
        q = q.startAfterDocument(after);
      }
      final snap = await q.get();
      if (snap.docs.isEmpty) break;
      for (final doc in snap.docs) {
        final data = doc.data();
        await _applyClient(doc.id, data);
        final updated = _readTs(data['updatedAt']);
        if (updated == null) continue;
        if (maxCursor == null ||
            syncPullCursorBefore(maxCursor, updated, doc.id)) {
          maxCursor = SyncPullCursor(updated, doc.id);
        }
      }
      after = snap.docs.last;
      if (snap.docs.length < syncPullPageSize) break;
    }
    if (maxCursor != null) {
      await db.setSetting(cursorKey, maxCursor.encode());
    }
  }

  /// Pages in [syncPullCursorBefore] order. A legacy cursor (no document id)
  /// uses `updatedAt >= t` so equal stamps are included once, then resumed by id.
  /// [afterDoc] continues a full page without re-encoding `updatedAt`.
  Query<Map<String, dynamic>> _pullPage(
    String orgId,
    String name, {
    String? practitionerUid,
    SyncPullCursor? cursor,
    QueryDocumentSnapshot<Map<String, dynamic>>? afterDoc,
  }) {
    Query<Map<String, dynamic>> q = _col(orgId, name);
    if (practitionerUid != null) {
      q = q.where('practitionerUid', isEqualTo: practitionerUid);
    }
    if (afterDoc != null) {
      return q
          .orderBy('updatedAt')
          .orderBy(FieldPath.documentId)
          .startAfterDocument(afterDoc)
          .limit(syncPullPageSize);
    }
    final bound = syncPullBound(cursor);
    final notBefore = bound.notBefore;
    if (notBefore != null) {
      q = q.where(
        'updatedAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(notBefore),
      );
    }
    q = q.orderBy('updatedAt').orderBy(FieldPath.documentId);
    final afterId = bound.afterId;
    if (notBefore != null && afterId != null) {
      q = q.startAfter([Timestamp.fromDate(notBefore), afterId]);
    }
    return q.limit(syncPullPageSize);
  }

  Future<void> _applyClient(
    String remoteId,
    Map<String, dynamic> data, {
    bool pending = false,
  }) async {
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
      syncStatus: Value(pending ? RowSyncStatus.pending : RowSyncStatus.synced),
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
    Map<String, dynamic> data, {
    bool pending = false,
  }) async {
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
      practitionerUid: Value((data['practitionerUid'] as String?) ?? ''),
      startsAt: Value(startsAt),
      endsAt: Value(_readTs(data['endsAt'])),
      status: Value(status),
      notes: Value(data['notes'] as String?),
      createdAt: Value(_readTs(data['createdAt']) ?? remoteUpdated),
      updatedAt: Value(remoteUpdated),
      deletedAt: Value(_readTs(data['deletedAt'])),
      syncStatus: Value(pending ? RowSyncStatus.pending : RowSyncStatus.synced),
    );
    if (existing == null) {
      await db.into(db.appointments).insert(companion);
    } else {
      await (db.update(db.appointments)..where((t) => t.id.equals(existing.id)))
          .write(companion);
    }
  }

  Future<void> _applyNote(
    String remoteId,
    Map<String, dynamic> data, {
    bool pending = false,
  }) async {
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
      practitionerUid: Value((data['practitionerUid'] as String?) ?? ''),
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
      syncStatus: Value(pending ? RowSyncStatus.pending : RowSyncStatus.synced),
    );
    if (existing == null) {
      await db.into(db.notes).insert(companion);
    } else {
      await (db.update(db.notes)..where((t) => t.id.equals(existing.id)))
          .write(companion);
    }
  }

  Future<void> _applyTemplate(
    String remoteId,
    Map<String, dynamic> data, {
    bool pending = false,
  }) async {
    final remoteUpdated = _readTs(data['updatedAt']) ?? DateTime.now().toUtc();
    final nameRaw = (data['name'] as String?)?.trim() ?? '';
    await db.applyRemoteOrgTemplate(
      remoteId: remoteId,
      name: nameRaw.isEmpty ? 'Untitled template' : nameRaw,
      description: (data['description'] as String?) ?? '',
      fieldsJson: (data['fieldsJson'] as String?) ?? '[]',
      createdBy: (data['createdBy'] as String?) ?? '',
      createdByName: (data['createdByName'] as String?) ?? '',
      createdAt: _readTs(data['createdAt']) ?? remoteUpdated,
      updatedAt: remoteUpdated,
      deletedAt: _readTs(data['deletedAt']),
      pending: pending,
    );
  }

  Future<void> _applySetting(
    String key,
    Map<String, dynamic> data, {
    bool pending = false,
  }) async {
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
            syncStatus: Value(
              pending ? RowSyncStatus.pending : RowSyncStatus.synced,
            ),
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
