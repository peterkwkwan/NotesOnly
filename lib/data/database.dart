import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'appointment_overlap.dart';
import 'recall.dart';
import 'remote_id.dart';

export 'recall.dart';

part 'database.g.dart';

/// Thrown when a create/update would overlap another appointment.
class AppointmentConflictException implements Exception {
  AppointmentConflictException(this.appointment, this.client);

  final Appointment appointment;
  final Client client;

  @override
  String toString() => 'AppointmentConflictException';
}

/// Appointment lifecycle statuses for MVP.
enum AppointmentStatus {
  scheduled,
  completed,
  cancelled,
  noShow,
}

/// Legacy note status; unused (notes stay editable).
enum NoteStatus {
  draft,
  finalized,
}

/// Per-row cloud sync flag (Drift ↔ Firestore).
enum RowSyncStatus {
  synced,
  pending,
  error,
}

class Clients extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().withDefault(const Constant(''))();
  TextColumn get firstName => text().withLength(min: 1, max: 120)();
  TextColumn get lastName => text().withLength(min: 1, max: 120)();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  DateTimeColumn get joinDate => dateTime().nullable()();
  DateTimeColumn get birthday => dateTime().nullable()();
  TextColumn get emergencyContact => text().nullable()();
  TextColumn get emergencyContactPhone => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get syncStatus => intEnum<RowSyncStatus>()
      .withDefault(Constant(RowSyncStatus.pending.index))();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

class Appointments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().withDefault(const Constant(''))();
  IntColumn get clientId => integer().references(Clients, #id)();
  DateTimeColumn get startsAt => dateTime()();
  DateTimeColumn get endsAt => dateTime().nullable()();
  IntColumn get status => intEnum<AppointmentStatus>()
      .withDefault(Constant(AppointmentStatus.scheduled.index))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get syncStatus => intEnum<RowSyncStatus>()
      .withDefault(Constant(RowSyncStatus.pending.index))();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().withDefault(const Constant(''))();
  IntColumn get clientId => integer().references(Clients, #id)();
  IntColumn get appointmentId =>
      integer().nullable().references(Appointments, #id)();
  DateTimeColumn get noteDate => dateTime()();
  TextColumn get subjective => text().withDefault(const Constant(''))();
  TextColumn get objective => text().withDefault(const Constant(''))();
  TextColumn get assessment => text().withDefault(const Constant(''))();
  TextColumn get plan => text().withDefault(const Constant(''))();
  /// Legacy column; unused (notes stay editable).
  TextColumn get addendum => text().withDefault(const Constant(''))();
  /// Legacy draft/final; unused (no lock).
  IntColumn get status =>
      intEnum<NoteStatus>().withDefault(Constant(NoteStatus.draft.index))();
  DateTimeColumn get finalizedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get syncStatus => intEnum<RowSyncStatus>()
      .withDefault(Constant(RowSyncStatus.pending.index))();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

/// Key/value settings (practitioner name, recall days, …).
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get syncStatus => intEnum<RowSyncStatus>()
      .withDefault(Constant(RowSyncStatus.synced.index))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(tables: [Clients, Appointments, Notes, Settings])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? _openConnection());

  /// Fired after a local mutation that may need a cloud push.
  void Function()? onLocalChange;

  void _notifyDirty() => onLocalChange?.call();

  @override
  int get schemaVersion => 5;

  /// True if [column] already exists on [table] (for idempotent migrations).
  Future<bool> hasSqliteColumn(String table, String column) async {
    final rows = await customSelect('PRAGMA table_info("$table")').get();
    return rows.any((r) => r.read<String>('name') == column);
  }

  Future<void> _addColumnIfMissing(
    Migrator m,
    TableInfo<Table, dynamic> table,
    GeneratedColumn<Object> column,
  ) async {
    if (await hasSqliteColumn(table.actualTableName, column.name)) return;
    await m.addColumn(table, column);
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await _addColumnIfMissing(m, notes, notes.addendum);
          }
          if (from < 3) {
            await _addColumnIfMissing(m, clients, clients.notes);
          }
          if (from < 4) {
            await _addColumnIfMissing(
              m,
              clients,
              clients.emergencyContactPhone,
            );
          }
          if (from < 5) {
            // Idempotent: a crashed prior run may have added some columns
            // without bumping user_version.
            await _addColumnIfMissing(m, clients, clients.remoteId);
            await _addColumnIfMissing(m, clients, clients.syncStatus);
            await _addColumnIfMissing(m, clients, clients.deletedAt);
            await _addColumnIfMissing(m, appointments, appointments.remoteId);
            await _addColumnIfMissing(m, appointments, appointments.syncStatus);
            await _addColumnIfMissing(m, appointments, appointments.deletedAt);
            await _addColumnIfMissing(m, notes, notes.remoteId);
            await _addColumnIfMissing(m, notes, notes.syncStatus);
            await _addColumnIfMissing(m, notes, notes.deletedAt);
            await _addColumnIfMissing(m, settings, settings.updatedAt);
            await _addColumnIfMissing(m, settings, settings.syncStatus);
            await _addColumnIfMissing(m, settings, settings.deletedAt);

            final now = DateTime.now();
            for (final c in await select(clients).get()) {
              if (c.remoteId.isNotEmpty) continue;
              await (update(clients)..where((t) => t.id.equals(c.id))).write(
                ClientsCompanion(
                  remoteId: Value(newRemoteId()),
                  syncStatus: const Value(RowSyncStatus.pending),
                  updatedAt: Value(now),
                ),
              );
            }
            for (final a in await select(appointments).get()) {
              if (a.remoteId.isNotEmpty) continue;
              await (update(appointments)..where((t) => t.id.equals(a.id)))
                  .write(
                AppointmentsCompanion(
                  remoteId: Value(newRemoteId()),
                  syncStatus: const Value(RowSyncStatus.pending),
                  updatedAt: Value(now),
                ),
              );
            }
            for (final n in await select(notes).get()) {
              if (n.remoteId.isNotEmpty) continue;
              await (update(notes)..where((t) => t.id.equals(n.id))).write(
                NotesCompanion(
                  remoteId: Value(newRemoteId()),
                  syncStatus: const Value(RowSyncStatus.pending),
                  updatedAt: Value(now),
                ),
              );
            }
            for (final s in await select(settings).get()) {
              // Re-mark cloud settings pending only when still default-synced
              // after a half-applied migrate; skip if already pending/error.
              if (s.syncStatus != RowSyncStatus.synced) continue;
              if (!isCloudSyncedSetting(s.key)) continue;
              await (update(settings)..where((t) => t.key.equals(s.key))).write(
                SettingsCompanion(
                  updatedAt: Value(now),
                  syncStatus: const Value(RowSyncStatus.pending),
                ),
              );
            }
          }
        },
      );

  static const practitionerNameKey = 'practitioner_name';
  static const recallDaysKey = 'recall_days';
  static const defaultRecallDays = '30';
  static const defaultAppointmentMinutesKey = 'default_appointment_minutes';
  static const defaultAppointmentMinutes = '60';
  static const clinicHoursStartKey = 'clinic_hours_start';
  static const clinicHoursEndKey = 'clinic_hours_end';
  static const defaultClinicHoursStart = '09:00';
  static const defaultClinicHoursEnd = '18:00';
  static const timezoneKey = 'timezone';
  /// Display/label only — wall clock still uses device local.
  static const defaultTimezone = 'Asia/Hong_Kong';
  static const recallNotificationsKey = 'recall_notifications_enabled';
  static const defaultRecallNotifications = '1';
  /// `light` | `dark` — Account Settings toggle; default light.
  static const themeModeKey = 'theme_mode';
  static const defaultThemeMode = 'light';
  /// Comma-separated client ids with recalls muted (hidden from Due + bell).
  static const recallMutedIdsKey = 'recall_muted_client_ids';
  /// Comma-separated client ids cleared from the notifications inbox.
  static const recallClearedIdsKey = 'recall_cleared_client_ids';
  /// Comma-separated client ids, most recently opened first.
  static const recentClientIdsKey = 'recent_client_ids';
  static const recentClientLimit = 8;
  /// Comma-separated pinned (favourite) client ids, most recently pinned first.
  static const pinnedClientIdsKey = 'pinned_client_ids';

  /// Firebase Auth uid this local book is bound to (account-switch guard).
  static const syncBoundUidKey = 'sync_bound_uid';
  static const syncLastSuccessKey = 'sync_last_success';
  static String syncCursorKey(String collection) => 'sync_cursor_$collection';

  /// Settings that mirror to Firestore (excludes device-local id lists + sync meta).
  static bool isCloudSyncedSetting(String key) {
    if (key.startsWith('sync_')) return false;
    const localOnly = {
      recentClientIdsKey,
      pinnedClientIdsKey,
      recallMutedIdsKey,
      recallClearedIdsKey,
    };
    return !localOnly.contains(key);
  }

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'pelvi_crm');
  }

  Future<String?> getSetting(String key) async {
    final row = await (select(settings)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Stream<String?> watchSetting(String key) {
    return (select(settings)..where((t) => t.key.equals(key)))
        .watch()
        .map((rows) => rows.isEmpty ? null : rows.first.value);
  }

  Future<void> setSetting(String key, String value) async {
    final cloud = isCloudSyncedSetting(key);
    await into(settings).insertOnConflictUpdate(
      SettingsCompanion.insert(
        key: key,
        value: value,
        updatedAt: Value(DateTime.now()),
        syncStatus: Value(
          cloud ? RowSyncStatus.pending : RowSyncStatus.synced,
        ),
      ),
    );
    if (cloud) _notifyDirty();
  }

  Future<String?> getPractitionerName() => getSetting(practitionerNameKey);

  Future<void> setPractitionerName(String name) =>
      setSetting(practitionerNameKey, name.trim());

  Future<int> getRecallDays() async {
    final raw = await getSetting(recallDaysKey);
    return int.tryParse(raw ?? defaultRecallDays) ?? 30;
  }

  /// [days] `0` = Never (recalls off). Positive = window length.
  Future<void> setRecallDays(int days) async {
    final clamped = days < 0 ? 0 : days;
    await setSetting(recallDaysKey, '$clamped');
  }

  Stream<int>? _recallDaysStream;

  Stream<int> watchRecallDays() {
    return _recallDaysStream ??= (select(settings)
          ..where((t) => t.key.equals(recallDaysKey)))
        .watch()
        .map((rows) {
          final raw = rows.isEmpty ? null : rows.first.value;
          return int.tryParse(raw ?? defaultRecallDays) ?? 30;
        })
        .asBroadcastStream();
  }

  Stream<List<RecallDueEntry>>? _recallDueStream;
  List<RecallDueEntry>? _lastRecallDue;
  final _recallDueSubs = <StreamSubscription<Object?>>[];

  /// Seen clients with no non-cancelled appointment/note inside the recall window.
  ///
  /// Cached broadcast that seeds each new listener with the latest list —
  /// a plain broadcast (no replay) left the Today bell sheet spinning forever.
  Stream<List<RecallDueEntry>> watchRecallDueClients() {
    if (_recallDueStream != null) return _recallDueStream!;
    final controller = StreamController<List<RecallDueEntry>>.broadcast();
    var emitting = false;
    var queued = false;

    Future<void> emit() async {
      if (emitting) {
        queued = true;
        return;
      }
      emitting = true;
      do {
        queued = false;
        try {
          final due = await getRecallDueClients();
          _lastRecallDue = due;
          if (!controller.isClosed) controller.add(due);
        } catch (e, st) {
          if (!controller.isClosed) controller.addError(e, st);
        }
      } while (queued);
      emitting = false;
    }

    void ping() => emit();
    _recallDueSubs.addAll([
      select(clients).watch().listen((_) => ping()),
      select(appointments).watch().listen((_) => ping()),
      select(notes).watch().listen((_) => ping()),
      (select(settings)..where((t) => t.key.equals(recallDaysKey)))
          .watch()
          .listen((_) => ping()),
      (select(settings)..where((t) => t.key.equals(recallMutedIdsKey)))
          .watch()
          .listen((_) => ping()),
      (select(settings)..where((t) => t.key.equals(recallClearedIdsKey)))
          .watch()
          .listen((_) => ping()),
    ]);

    _recallDueStream = Stream<List<RecallDueEntry>>.multi((multi) {
      final last = _lastRecallDue;
      if (last != null) {
        // Microtask: sync add during StreamBuilder.subscribe → setState-in-build.
        scheduleMicrotask(() {
          if (!multi.isClosed) multi.add(last);
        });
      } else {
        emit();
      }
      final sub = controller.stream.listen(
        multi.add,
        onError: multi.addError,
        onDone: multi.close,
      );
      multi.onCancel = sub.cancel;
    }, isBroadcast: true);
    return _recallDueStream!;
  }

  Future<List<RecallDueEntry>> getRecallDueClients({DateTime? now}) async {
    final clientsList = await (select(clients)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.asc(t.lastName),
            (t) => OrderingTerm.asc(t.firstName),
          ]))
        .get();
    final appts =
        await (select(appointments)..where((t) => t.deletedAt.isNull())).get();
    final notesList =
        await (select(notes)..where((t) => t.deletedAt.isNull())).get();
    final days = await getRecallDays();
    final muted = await getRecallMutedIds();
    return computeRecallDue(
      clients: clientsList,
      appointments: appts,
      notes: notesList,
      recallDays: days,
      now: now ?? DateTime.now(),
      mutedClientIds: muted,
    );
  }

  /// Due recalls minus cleared inbox items (Today bell + Notifications sheet).
  Future<List<RecallDueEntry>> getRecallInboxClients({DateTime? now}) async {
    final due = await getRecallDueClients(now: now);
    final cleared = await getRecallClearedIds();
    if (cleared.isEmpty) return due;
    return [for (final e in due) if (!cleared.contains(e.client.id)) e];
  }

  /// Inbox list; replays via [watchRecallDueClients] (cleared key also pings due).
  Stream<List<RecallDueEntry>> watchRecallInboxClients() {
    return watchRecallDueClients().asyncMap((due) async {
      final cleared = await getRecallClearedIds();
      if (cleared.isEmpty) return due;
      return [for (final e in due) if (!cleared.contains(e.client.id)) e];
    });
  }

  static Set<int> parseIdSet(String? raw) =>
      parseRecentClientIds(raw).toSet();

  Future<Set<int>> getRecallMutedIds() async =>
      parseIdSet(await getSetting(recallMutedIdsKey));

  Future<Set<int>> getRecallClearedIds() async =>
      parseIdSet(await getSetting(recallClearedIdsKey));

  Future<bool> isRecallMuted(int clientId) async =>
      (await getRecallMutedIds()).contains(clientId);

  Stream<bool> watchRecallMuted(int clientId) {
    return (select(settings)..where((t) => t.key.equals(recallMutedIdsKey)))
        .watch()
        .map((rows) {
          final raw = rows.isEmpty ? null : rows.first.value;
          return parseIdSet(raw).contains(clientId);
        });
  }

  Future<void> setRecallMuted(int clientId, bool muted) async {
    final ids = Set<int>.of(await getRecallMutedIds());
    if (muted) {
      ids.add(clientId);
    } else {
      ids.remove(clientId);
    }
    await setSetting(recallMutedIdsKey, ids.join(','));
  }

  /// Hide one due recall from the notifications inbox / bell (not Due tab).
  ///
  /// shortcut: cleared id stays forever, upgrade when re-notify after clear is needed
  Future<void> clearRecallInboxItem(int clientId) async {
    final ids = Set<int>.of(await getRecallClearedIds())..add(clientId);
    await setSetting(recallClearedIdsKey, ids.join(','));
  }

  @override
  Future<void> close() async {
    for (final s in _recallDueSubs) {
      await s.cancel();
    }
    _recallDueSubs.clear();
    _lastRecallDue = null;
    _recallDueStream = null;
    _recallDaysStream = null;
    await super.close();
  }

  Future<int> getDefaultAppointmentMinutes() async {
    final raw = await getSetting(defaultAppointmentMinutesKey);
    return int.tryParse(raw ?? defaultAppointmentMinutes) ?? 60;
  }

  Future<void> setDefaultAppointmentMinutes(int minutes) async {
    final clamped = minutes < 5 ? 5 : minutes;
    await setSetting(defaultAppointmentMinutesKey, '$clamped');
  }

  Stream<int> watchDefaultAppointmentMinutes() {
    return (select(settings)
          ..where((t) => t.key.equals(defaultAppointmentMinutesKey)))
        .watch()
        .map((rows) {
          final raw = rows.isEmpty ? null : rows.first.value;
          return int.tryParse(raw ?? defaultAppointmentMinutes) ?? 60;
        });
  }

  Future<String> getClinicHoursStart() async =>
      await getSetting(clinicHoursStartKey) ?? defaultClinicHoursStart;

  Future<void> setClinicHoursStart(String hhmm) =>
      setSetting(clinicHoursStartKey, hhmm);

  Future<String> getClinicHoursEnd() async =>
      await getSetting(clinicHoursEndKey) ?? defaultClinicHoursEnd;

  Future<void> setClinicHoursEnd(String hhmm) =>
      setSetting(clinicHoursEndKey, hhmm);

  Stream<(String, String)> watchClinicHours() {
    return select(settings).watch().asyncMap((_) async {
      return (await getClinicHoursStart(), await getClinicHoursEnd());
    });
  }

  Future<String> getTimezone() async =>
      await getSetting(timezoneKey) ?? defaultTimezone;

  Future<void> setTimezone(String iana) => setSetting(timezoneKey, iana);

  Stream<String> watchTimezone() {
    return (select(settings)..where((t) => t.key.equals(timezoneKey)))
        .watch()
        .map((rows) {
          if (rows.isEmpty) return defaultTimezone;
          return rows.first.value;
        });
  }

  Future<bool> getRecallNotificationsEnabled() async {
    final raw = await getSetting(recallNotificationsKey);
    return (raw ?? defaultRecallNotifications) != '0';
  }

  Future<void> setRecallNotificationsEnabled(bool enabled) =>
      setSetting(recallNotificationsKey, enabled ? '1' : '0');

  Stream<bool> watchRecallNotificationsEnabled() {
    return (select(settings)
          ..where((t) => t.key.equals(recallNotificationsKey)))
        .watch()
        .map((rows) {
          final raw = rows.isEmpty ? null : rows.first.value;
          return (raw ?? defaultRecallNotifications) != '0';
        });
  }

  Future<bool> getDarkModeEnabled() async {
    final raw = await getSetting(themeModeKey);
    return (raw ?? defaultThemeMode) == 'dark';
  }

  Future<void> setDarkModeEnabled(bool enabled) =>
      setSetting(themeModeKey, enabled ? 'dark' : 'light');

  Stream<bool> watchDarkModeEnabled() {
    return (select(settings)..where((t) => t.key.equals(themeModeKey)))
        .watch()
        .map((rows) {
          final raw = rows.isEmpty ? null : rows.first.value;
          return (raw ?? defaultThemeMode) == 'dark';
        });
  }

  Stream<String?> watchPractitionerName() {
    return (select(settings)
          ..where((t) => t.key.equals(practitionerNameKey)))
        .watch()
        .map((rows) => rows.isEmpty ? null : rows.first.value);
  }

  Future<void> ensureDefaults() async {
    final existing = await getSetting(recallDaysKey);
    if (existing == null) {
      await setSetting(recallDaysKey, defaultRecallDays);
    }
    final duration = await getSetting(defaultAppointmentMinutesKey);
    if (duration == null) {
      await setSetting(
        defaultAppointmentMinutesKey,
        defaultAppointmentMinutes,
      );
    }
    if (await getSetting(clinicHoursStartKey) == null) {
      await setSetting(clinicHoursStartKey, defaultClinicHoursStart);
    }
    if (await getSetting(clinicHoursEndKey) == null) {
      await setSetting(clinicHoursEndKey, defaultClinicHoursEnd);
    }
    if (await getSetting(timezoneKey) == null) {
      await setSetting(timezoneKey, defaultTimezone);
    }
    if (await getSetting(recallNotificationsKey) == null) {
      await setSetting(recallNotificationsKey, defaultRecallNotifications);
    }
    if (await getSetting(themeModeKey) == null) {
      await setSetting(themeModeKey, defaultThemeMode);
    }
  }

  Stream<List<Client>> watchClients() {
    return (select(clients)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.asc(t.lastName),
            (t) => OrderingTerm.asc(t.firstName),
          ]))
        .watch();
  }

  Future<Client?> getClient(int id) {
    return (select(clients)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Stream<Client?> watchClient(int id) {
    return (select(clients)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .watch()
        .map((rows) => rows.isEmpty ? null : rows.first);
  }

  static List<int> parseRecentClientIds(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return [
      for (final part in raw.split(','))
        if (int.tryParse(part.trim()) != null) int.parse(part.trim()),
    ];
  }

  Stream<List<int>> watchRecentClientIds() {
    return (select(settings)
          ..where((t) => t.key.equals(recentClientIdsKey)))
        .watch()
        .map(
          (rows) => parseRecentClientIds(
            rows.isEmpty ? null : rows.first.value,
          ),
        );
  }

  /// Record a profile open for the Clients recent strip.
  Future<void> touchRecentClient(int id) async {
    final current = List<int>.of(
      parseRecentClientIds(await getSetting(recentClientIdsKey)),
    );
    current.remove(id);
    current.insert(0, id);
    if (current.length > recentClientLimit) {
      current.removeRange(recentClientLimit, current.length);
    }
    await setSetting(recentClientIdsKey, current.join(','));
  }

  Future<List<int>> getPinnedClientIds() async =>
      parseRecentClientIds(await getSetting(pinnedClientIdsKey));

  Stream<List<int>> watchPinnedClientIds() {
    return (select(settings)
          ..where((t) => t.key.equals(pinnedClientIdsKey)))
        .watch()
        .map(
          (rows) => parseRecentClientIds(
            rows.isEmpty ? null : rows.first.value,
          ),
        );
  }

  Future<void> setClientsPinned(Iterable<int> ids, bool pinned) async {
    final current = List<int>.of(await getPinnedClientIds());
    for (final id in ids) {
      current.remove(id);
      if (pinned) current.insert(0, id);
    }
    await setSetting(pinnedClientIdsKey, current.join(','));
  }

  /// Soft-delete client and owned appointments/notes; scrub id from settings lists.
  Future<void> deleteClient(int id) async {
    final now = DateTime.now();
    await (update(notes)..where((t) => t.clientId.equals(id))).write(
      NotesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(RowSyncStatus.pending),
      ),
    );
    await (update(appointments)..where((t) => t.clientId.equals(id))).write(
      AppointmentsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(RowSyncStatus.pending),
      ),
    );
    await (update(clients)..where((t) => t.id.equals(id))).write(
      ClientsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(RowSyncStatus.pending),
      ),
    );
    await _scrubClientIdFromSettings(id);
    _notifyDirty();
  }

  Future<void> _scrubClientIdFromSettings(int id) async {
    for (final key in [
      recentClientIdsKey,
      pinnedClientIdsKey,
      recallMutedIdsKey,
      recallClearedIdsKey,
    ]) {
      final ids = List<int>.of(parseRecentClientIds(await getSetting(key)))
        ..remove(id);
      await setSetting(key, ids.join(','));
    }
  }

  Future<int> insertClient({
    required String firstName,
    required String lastName,
    String? phone,
    String? email,
    String? emergencyContact,
    String? emergencyContactPhone,
    String? notes,
  }) async {
    final id = await into(clients).insert(
      ClientsCompanion.insert(
        remoteId: Value(newRemoteId()),
        firstName: firstName.trim(),
        lastName: lastName.trim(),
        phone: Value(_blankToNull(phone)),
        email: Value(_blankToNull(email)),
        emergencyContact: Value(_blankToNull(emergencyContact)),
        emergencyContactPhone: Value(_blankToNull(emergencyContactPhone)),
        notes: Value(_blankToNull(notes)),
        syncStatus: const Value(RowSyncStatus.pending),
      ),
    );
    _notifyDirty();
    return id;
  }

  Future<bool> updateClient({
    required int id,
    required String firstName,
    required String lastName,
    String? phone,
    String? email,
    String? emergencyContact,
    String? emergencyContactPhone,
    String? notes,
  }) async {
    final n = await (update(clients)..where((t) => t.id.equals(id))).write(
      ClientsCompanion(
        firstName: Value(firstName.trim()),
        lastName: Value(lastName.trim()),
        phone: Value(_blankToNull(phone)),
        email: Value(_blankToNull(email)),
        emergencyContact: Value(_blankToNull(emergencyContact)),
        emergencyContactPhone: Value(_blankToNull(emergencyContactPhone)),
        notes: Value(_blankToNull(notes)),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value(RowSyncStatus.pending),
      ),
    );
    if (n > 0) _notifyDirty();
    return n > 0;
  }

  Stream<List<Appointment>> watchAppointmentsForClient(int clientId) {
    return (select(appointments)
          ..where((t) => t.clientId.equals(clientId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.startsAt)]))
        .watch();
  }

  /// Appointments whose [Appointments.startsAt] falls on [day] (local date).
  Stream<List<({Appointment appointment, Client client})>>
      watchAppointmentsWithClientOnDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final query = select(appointments).join([
      innerJoin(clients, clients.id.equalsExp(appointments.clientId)),
    ])
      ..where(
        appointments.startsAt.isBiggerOrEqualValue(start) &
            appointments.startsAt.isSmallerThanValue(end) &
            appointments.deletedAt.isNull() &
            clients.deletedAt.isNull(),
      )
      ..orderBy([OrderingTerm.asc(appointments.startsAt)]);
    return query.watch().map(
          (rows) => [
            for (final row in rows)
              (
                appointment: row.readTable(appointments),
                client: row.readTable(clients),
              ),
          ],
        );
  }

  /// Per-day appointment counts for [month] (any day in that calendar month).
  Stream<Map<DateTime, int>> watchAppointmentCountsForMonth(DateTime month) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return (select(appointments)
          ..where(
            (t) =>
                t.startsAt.isBiggerOrEqualValue(start) &
                t.startsAt.isSmallerThanValue(end) &
                t.deletedAt.isNull(),
          ))
        .watch()
        .map((rows) {
          final counts = <DateTime, int>{};
          for (final a in rows) {
            final d = DateTime(a.startsAt.year, a.startsAt.month, a.startsAt.day);
            counts[d] = (counts[d] ?? 0) + 1;
          }
          return counts;
        });
  }

  /// First overlapping appointment in the solo book, if any.
  ///
  /// shortcut: scans all rows, upgrade when diary is large
  Future<({Appointment appointment, Client client})?>
      findOverlappingAppointment({
    required DateTime startsAt,
    DateTime? endsAt,
    int? excludeId,
  }) async {
    final minutes = await getDefaultAppointmentMinutes();
    final newEnd = appointmentEffectiveEnd(startsAt, endsAt, minutes);
    final query = select(appointments).join([
      innerJoin(clients, clients.id.equalsExp(appointments.clientId)),
    ])
      ..where(appointments.deletedAt.isNull() & clients.deletedAt.isNull());
    final rows = await query.get();
    for (final row in rows) {
      final other = row.readTable(appointments);
      if (excludeId != null && other.id == excludeId) continue;
      if (other.status == AppointmentStatus.cancelled) continue;
      final otherEnd =
          appointmentEffectiveEnd(other.startsAt, other.endsAt, minutes);
      if (appointmentsOverlap(
        startsAt,
        newEnd,
        other.startsAt,
        otherEnd,
      )) {
        return (
          appointment: other,
          client: row.readTable(clients),
        );
      }
    }
    return null;
  }

  Future<int> insertAppointment({
    required int clientId,
    required DateTime startsAt,
    DateTime? endsAt,
    AppointmentStatus status = AppointmentStatus.scheduled,
  }) async {
    final conflict = await findOverlappingAppointment(
      startsAt: startsAt,
      endsAt: endsAt,
    );
    if (conflict != null) {
      throw AppointmentConflictException(
        conflict.appointment,
        conflict.client,
      );
    }
    final id = await into(appointments).insert(
      AppointmentsCompanion.insert(
        remoteId: Value(newRemoteId()),
        clientId: clientId,
        startsAt: startsAt,
        endsAt: Value(endsAt),
        status: Value(status),
        syncStatus: const Value(RowSyncStatus.pending),
      ),
    );
    _notifyDirty();
    return id;
  }

  Future<bool> updateAppointment({
    required int id,
    required DateTime startsAt,
    DateTime? endsAt,
    AppointmentStatus? status,
  }) async {
    final existing = await getAppointment(id);
    if (existing == null) return false;
    final conflict = await findOverlappingAppointment(
      startsAt: startsAt,
      endsAt: endsAt ?? existing.endsAt,
      excludeId: id,
    );
    if (conflict != null) {
      throw AppointmentConflictException(
        conflict.appointment,
        conflict.client,
      );
    }
    final n = await (update(appointments)..where((t) => t.id.equals(id))).write(
      AppointmentsCompanion(
        startsAt: Value(startsAt),
        endsAt: endsAt == null ? const Value.absent() : Value(endsAt),
        status: status == null ? const Value.absent() : Value(status),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value(RowSyncStatus.pending),
      ),
    );
    if (n > 0) _notifyDirty();
    return n > 0;
  }

  Future<Appointment?> getAppointment(int id) {
    return (select(appointments)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Soft-deletes the appointment; unlinks any SOAP note (note kept).
  Future<void> deleteAppointment(int id) async {
    final now = DateTime.now();
    await (update(notes)..where((t) => t.appointmentId.equals(id))).write(
      NotesCompanion(
        appointmentId: const Value(null),
        updatedAt: Value(now),
        syncStatus: const Value(RowSyncStatus.pending),
      ),
    );
    await (update(appointments)..where((t) => t.id.equals(id))).write(
      AppointmentsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(RowSyncStatus.pending),
      ),
    );
    _notifyDirty();
  }

  Stream<Note?> watchNote(int id) {
    return (select(notes)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .watch()
        .map((rows) => rows.isEmpty ? null : rows.first);
  }

  Future<Note?> getNote(int id) {
    return (select(notes)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<Note?> getNoteForAppointment(int appointmentId) {
    return (select(notes)
          ..where(
            (t) =>
                t.appointmentId.equals(appointmentId) & t.deletedAt.isNull(),
          ))
        .getSingleOrNull();
  }

  /// Visit history: notes for a client, newest first.
  Stream<List<Note>> watchNotesForClient(int clientId) {
    return (select(notes)
          ..where((t) => t.clientId.equals(clientId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.noteDate)]))
        .watch();
  }

  /// Most recent note for [clientId], excluding [exceptNoteId] when set.
  Future<Note?> getLastNoteForClient(int clientId, {int? exceptNoteId}) async {
    final query = select(notes)
      ..where((t) => t.clientId.equals(clientId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.noteDate)])
      ..limit(5);
    final rows = await query.get();
    for (final n in rows) {
      if (exceptNoteId != null && n.id == exceptNoteId) continue;
      return n;
    }
    return null;
  }

  /// Open existing note for the appointment, or create a draft.
  Future<Note> getOrCreateNoteForAppointment({
    required int appointmentId,
    required int clientId,
    DateTime? noteDate,
  }) async {
    final existing = await getNoteForAppointment(appointmentId);
    if (existing != null) return existing;
    final id = await into(notes).insert(
      NotesCompanion.insert(
        remoteId: Value(newRemoteId()),
        clientId: clientId,
        appointmentId: Value(appointmentId),
        noteDate: noteDate ?? DateTime.now(),
        syncStatus: const Value(RowSyncStatus.pending),
      ),
    );
    _notifyDirty();
    return (await getNote(id))!;
  }

  Future<void> updateNoteSoap({
    required int id,
    required String subjective,
    required String objective,
    required String assessment,
    required String plan,
  }) async {
    final note = await getNote(id);
    if (note == null) return;
    await (update(notes)..where((t) => t.id.equals(id))).write(
      NotesCompanion(
        subjective: Value(subjective),
        objective: Value(objective),
        assessment: Value(assessment),
        plan: Value(plan),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value(RowSyncStatus.pending),
      ),
    );
    _notifyDirty();
  }

  /// Copy S/O/A/P from [source] into [targetId] (same-client caller checks).
  Future<bool> copySoapIntoNote({
    required int targetId,
    required Note source,
  }) async {
    final target = await getNote(targetId);
    if (target == null) return false;
    await (update(notes)..where((t) => t.id.equals(targetId))).write(
      NotesCompanion(
        subjective: Value(source.subjective),
        objective: Value(source.objective),
        assessment: Value(source.assessment),
        plan: Value(source.plan),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value(RowSyncStatus.pending),
      ),
    );
    _notifyDirty();
    return true;
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}
