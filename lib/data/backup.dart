import 'dart:convert';

import 'package:drift/drift.dart';

import 'database.dart';
import 'remote_id.dart';

/// Backup format version — bump when shape changes.
const backupFormatVersion = 1;

/// Build a JSON-ready map of clients, appointments, notes, and settings.
Future<Map<String, Object?>> buildBackupMap(AppDatabase db) async {
  final clients = await db.watchClients().first;
  final appointments = await db.select(db.appointments).get();
  final notes = await db.select(db.notes).get();
  final settingsRows = await db.select(db.settings).get();

  return {
    'format': 'pelvi_crm_backup',
    'version': backupFormatVersion,
    'exportedAt': DateTime.now().toIso8601String(),
    'clients': [
      for (final c in clients)
        {
          'id': c.id,
          'firstName': c.firstName,
          'lastName': c.lastName,
          'phone': c.phone,
          'email': c.email,
          'joinDate': c.joinDate?.toIso8601String(),
          'birthday': c.birthday?.toIso8601String(),
          'emergencyContact': c.emergencyContact,
          'emergencyContactPhone': c.emergencyContactPhone,
          'notes': c.notes,
          'createdAt': c.createdAt.toIso8601String(),
          'updatedAt': c.updatedAt.toIso8601String(),
        },
    ],
    'appointments': [
      for (final a in appointments)
        {
          'id': a.id,
          'clientId': a.clientId,
          'practitionerUid': a.practitionerUid,
          'startsAt': a.startsAt.toIso8601String(),
          'endsAt': a.endsAt?.toIso8601String(),
          'status': a.status.index,
          'notes': a.notes,
          'createdAt': a.createdAt.toIso8601String(),
          'updatedAt': a.updatedAt.toIso8601String(),
        },
    ],
    'notes': [
      for (final n in notes)
        {
          'id': n.id,
          'clientId': n.clientId,
          'appointmentId': n.appointmentId,
          'practitionerUid': n.practitionerUid,
          'noteDate': n.noteDate.toIso8601String(),
          'subjective': n.subjective,
          'objective': n.objective,
          'assessment': n.assessment,
          'plan': n.plan,
          'addendum': n.addendum,
          'status': n.status.index,
          'finalizedAt': n.finalizedAt?.toIso8601String(),
          'createdAt': n.createdAt.toIso8601String(),
          'updatedAt': n.updatedAt.toIso8601String(),
        },
    ],
    'settings': {
      for (final s in settingsRows) s.key: s.value,
    },
  };
}

String encodeBackupJson(Map<String, Object?> map) =>
    const JsonEncoder.withIndent('  ').convert(map);

Map<String, Object?> decodeBackupJson(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('Backup root must be a JSON object');
  }
  final map = Map<String, Object?>.from(decoded);
  if (map['format'] != 'pelvi_crm_backup') {
    throw const FormatException('Not a NotesOnly backup file');
  }
  final version = map['version'];
  if (version is! int || version < 1 || version > backupFormatVersion) {
    throw FormatException('Unsupported backup version: $version');
  }
  return map;
}

String _csvEscape(Object? value) {
  final s = value?.toString() ?? '';
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String _csvLine(List<Object?> cells) =>
    cells.map(_csvEscape).join(',');

/// CSV dumps for spreadsheet escape hatches (three tables).
Future<({String clients, String appointments, String notes})> buildBackupCsv(
  AppDatabase db,
) async {
  final clients = await db.watchClients().first;
  final appointments = await db.select(db.appointments).get();
  final notes = await db.select(db.notes).get();

  final clientsCsv = StringBuffer()
    ..writeln(_csvLine([
      'id',
      'firstName',
      'lastName',
      'phone',
      'email',
      'emergencyContact',
      'emergencyContactPhone',
      'notes',
      'createdAt',
      'updatedAt',
    ]));
  for (final c in clients) {
    clientsCsv.writeln(_csvLine([
      c.id,
      c.firstName,
      c.lastName,
      c.phone,
      c.email,
      c.emergencyContact,
      c.emergencyContactPhone,
      c.notes,
      c.createdAt.toIso8601String(),
      c.updatedAt.toIso8601String(),
    ]));
  }

  final apptsCsv = StringBuffer()
    ..writeln(_csvLine([
      'id',
      'clientId',
      'startsAt',
      'endsAt',
      'status',
      'notes',
      'createdAt',
      'updatedAt',
    ]));
  for (final a in appointments) {
    apptsCsv.writeln(_csvLine([
      a.id,
      a.clientId,
      a.startsAt.toIso8601String(),
      a.endsAt?.toIso8601String(),
      a.status.name,
      a.notes,
      a.createdAt.toIso8601String(),
      a.updatedAt.toIso8601String(),
    ]));
  }

  final notesCsv = StringBuffer()
    ..writeln(_csvLine([
      'id',
      'clientId',
      'appointmentId',
      'noteDate',
      'subjective',
      'objective',
      'assessment',
      'plan',
      'createdAt',
      'updatedAt',
    ]));
  for (final n in notes) {
    notesCsv.writeln(_csvLine([
      n.id,
      n.clientId,
      n.appointmentId,
      n.noteDate.toIso8601String(),
      n.subjective,
      n.objective,
      n.assessment,
      n.plan,
      n.createdAt.toIso8601String(),
      n.updatedAt.toIso8601String(),
    ]));
  }

  return (
    clients: clientsCsv.toString(),
    appointments: apptsCsv.toString(),
    notes: notesCsv.toString(),
  );
}

DateTime? _parseDate(Object? raw) {
  if (raw == null) return null;
  if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
  return null;
}

/// Replace local clinical data with [map] from [decodeBackupJson].
///
/// shortcut: wipe-then-insert (not merge); upgrade if multi-device sync lands
Future<void> restoreBackupMap(AppDatabase db, Map<String, Object?> map) async {
  final clientsRaw = map['clients'];
  final apptsRaw = map['appointments'];
  final notesRaw = map['notes'];
  if (clientsRaw is! List || apptsRaw is! List || notesRaw is! List) {
    throw const FormatException('Backup missing clients/appointments/notes');
  }

  await db.transaction(() async {
    await db.delete(db.notes).go();
    await db.delete(db.appointments).go();
    await db.delete(db.clients).go();

    for (final row in clientsRaw) {
      if (row is! Map) continue;
      final m = Map<String, Object?>.from(row);
      final id = m['id'];
      if (id is! int) continue;
      await db.into(db.clients).insert(
            ClientsCompanion.insert(
              id: Value(id),
              remoteId: Value(
                (m['remoteId'] as String?)?.trim().isNotEmpty == true
                    ? (m['remoteId'] as String).trim()
                    : newRemoteId(),
              ),
              firstName: (m['firstName'] as String?)?.trim() ?? 'Unknown',
              lastName: (m['lastName'] as String?)?.trim() ?? 'Client',
              phone: Value(m['phone'] as String?),
              email: Value(m['email'] as String?),
              joinDate: Value(_parseDate(m['joinDate'])),
              birthday: Value(_parseDate(m['birthday'])),
              emergencyContact: Value(m['emergencyContact'] as String?),
              emergencyContactPhone: Value(m['emergencyContactPhone'] as String?),
              notes: Value(m['notes'] as String?),
              createdAt: Value(_parseDate(m['createdAt']) ?? DateTime.now()),
              updatedAt: Value(_parseDate(m['updatedAt']) ?? DateTime.now()),
              syncStatus: const Value(RowSyncStatus.pending),
            ),
          );
    }

    for (final row in apptsRaw) {
      if (row is! Map) continue;
      final m = Map<String, Object?>.from(row);
      final id = m['id'];
      final clientId = m['clientId'];
      final startsAt = _parseDate(m['startsAt']);
      if (id is! int || clientId is! int || startsAt == null) continue;
      final statusIdx = m['status'];
      final status = statusIdx is int &&
              statusIdx >= 0 &&
              statusIdx < AppointmentStatus.values.length
          ? AppointmentStatus.values[statusIdx]
          : AppointmentStatus.scheduled;
      await db.into(db.appointments).insert(
            AppointmentsCompanion.insert(
              id: Value(id),
              remoteId: Value(
                (m['remoteId'] as String?)?.trim().isNotEmpty == true
                    ? (m['remoteId'] as String).trim()
                    : newRemoteId(),
              ),
              clientId: clientId,
              practitionerUid: Value((m['practitionerUid'] as String?) ?? ''),
              startsAt: startsAt,
              endsAt: Value(_parseDate(m['endsAt'])),
              status: Value(status),
              notes: Value(m['notes'] as String?),
              createdAt: Value(_parseDate(m['createdAt']) ?? DateTime.now()),
              updatedAt: Value(_parseDate(m['updatedAt']) ?? DateTime.now()),
              syncStatus: const Value(RowSyncStatus.pending),
            ),
          );
    }

    for (final row in notesRaw) {
      if (row is! Map) continue;
      final m = Map<String, Object?>.from(row);
      final id = m['id'];
      final clientId = m['clientId'];
      final noteDate = _parseDate(m['noteDate']);
      if (id is! int || clientId is! int || noteDate == null) continue;
      final statusIdx = m['status'];
      final status = statusIdx is int &&
              statusIdx >= 0 &&
              statusIdx < NoteStatus.values.length
          ? NoteStatus.values[statusIdx]
          : NoteStatus.draft;
      await db.into(db.notes).insert(
            NotesCompanion.insert(
              id: Value(id),
              remoteId: Value(
                (m['remoteId'] as String?)?.trim().isNotEmpty == true
                    ? (m['remoteId'] as String).trim()
                    : newRemoteId(),
              ),
              clientId: clientId,
              appointmentId: Value(m['appointmentId'] as int?),
              practitionerUid: Value((m['practitionerUid'] as String?) ?? ''),
              noteDate: noteDate,
              subjective: Value((m['subjective'] as String?) ?? ''),
              objective: Value((m['objective'] as String?) ?? ''),
              assessment: Value((m['assessment'] as String?) ?? ''),
              plan: Value((m['plan'] as String?) ?? ''),
              addendum: Value((m['addendum'] as String?) ?? ''),
              status: Value(status),
              finalizedAt: Value(_parseDate(m['finalizedAt'])),
              createdAt: Value(_parseDate(m['createdAt']) ?? DateTime.now()),
              updatedAt: Value(_parseDate(m['updatedAt']) ?? DateTime.now()),
              syncStatus: const Value(RowSyncStatus.pending),
            ),
          );
    }

    final settingsRaw = map['settings'];
    if (settingsRaw is Map) {
      for (final e in settingsRaw.entries) {
        final key = e.key.toString();
        final value = e.value?.toString();
        if (value == null) continue;
        await db.setSetting(key, value);
      }
    }
  });

  await db.ensureDefaults();
  db.onLocalChange?.call();
}
