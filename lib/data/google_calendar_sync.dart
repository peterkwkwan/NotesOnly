import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../features/clients/client_format.dart';
import 'appointment_overlap.dart';
import 'auth.dart';
import 'database.dart';
import 'online.dart';

/// One-way NotesOnly → Google primary calendar (client-side, soft-fail).
class GoogleCalendarSync {
  GoogleCalendarSync(this.db, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final AppDatabase db;
  final http.Client _http;

  /// Soft UI message (snackbar). Never blocks Drift.
  void Function(String message)? onSoftError;

  bool _draining = false;
  Timer? _debounce;
  bool _started = false;

  static const _eventsUrl =
      'https://www.googleapis.com/calendar/v3/calendars/primary/events';
  static const _maxAttempts = 8;

  void start() {
    if (_started) return;
    _started = true;
    db.onAppointmentChanged = (id, {deleteGoogleEventId}) {
      unawaited(_onAppointmentChanged(id, deleteGoogleEventId));
    };
  }

  void stop() {
    _started = false;
    db.onAppointmentChanged = null;
    _debounce?.cancel();
  }

  void onAppResumed() {
    if (!_started) return;
    unawaited(drain());
  }

  /// Opt-in: OAuth Calendar scope + backfill. Returns false if denied.
  Future<bool> enable() async {
    final token = await NotesAuth.requestCalendarAccess(interactive: true);
    if (token == null) {
      await db.setGoogleCalendarSyncEnabled(false);
      await db.setGoogleCalendarSyncStatus('needs_permission');
      return false;
    }
    await db.setGoogleCalendarSyncEnabled(true);
    await db.setGoogleCalendarSyncStatus('connected');
    await db.setSetting(AppDatabase.googleCalendarLastErrorKey, '');
    await _enqueueBackfill();
    // Await first drain so enable() reflects push errors (status / soft snackbar)
    // instead of claiming Connected while the outbox never left the device.
    await drain();
    return true;
  }

  /// Stop future pushes. Leaves existing Google events in place (v1).
  Future<void> disable() async {
    await db.setGoogleCalendarSyncEnabled(false);
    await db.setGoogleCalendarSyncStatus('');
    await db.setSetting(AppDatabase.googleCalendarOutboxKey, '[]');
    await NotesAuth.clearCalendarAccessToken();
  }

  Future<void> _onAppointmentChanged(
    int id,
    String? deleteGoogleEventId,
  ) async {
    if (deleteGoogleEventId != null && deleteGoogleEventId.isNotEmpty) {
      final appt = await db.getAppointment(id);
      await _enqueue(
        remoteId: appt?.remoteId.isNotEmpty == true
            ? appt!.remoteId
            : 'orphan-$deleteGoogleEventId',
        op: 'delete',
        googleEventId: deleteGoogleEventId,
      );
    }
    await enqueueForAppointment(id);
    _scheduleDrain();
  }

  Future<void> enqueueForAppointment(int id) async {
    if (!await db.getGoogleCalendarSyncEnabled()) return;
    final self = NotesAuth.currentUser?.uid ?? '';
    if (self.isEmpty) return;
    final appt = await db.getAppointment(id);
    if (appt == null || appt.remoteId.isEmpty) return;
    final owner =
        appt.practitionerUid.isEmpty ? self : appt.practitionerUid;
    if (owner != self) return;

    final gone = appt.deletedAt != null ||
        appt.status == AppointmentStatus.cancelled;
    if (gone) {
      final eventId = appt.googleEventId;
      if (eventId == null || eventId.isEmpty) return;
      await _enqueue(
        remoteId: appt.remoteId,
        op: 'delete',
        googleEventId: eventId,
      );
      return;
    }
    await _enqueue(remoteId: appt.remoteId, op: 'upsert');
  }

  Future<void> _enqueueBackfill() async {
    final self = NotesAuth.currentUser?.uid ?? '';
    if (self.isEmpty) return;
    final rows = await db.myAppointmentsNeedingGoogleEvent(self);
    for (final row in rows) {
      if (row.remoteId.isEmpty) continue;
      await _enqueue(remoteId: row.remoteId, op: 'upsert');
    }
  }

  void _scheduleDrain() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () {
      unawaited(drain());
    });
  }

  Future<void> drain() async {
    if (_draining) return;
    if (!await db.getGoogleCalendarSyncEnabled()) return;
    final queued = await _readOutbox();
    if (queued.isEmpty) return;
    if (!await deviceLooksOnline()) {
      // Previously a silent return left status "Connected" with a full outbox.
      onSoftError?.call(
        "Couldn't update Google Calendar — will retry",
      );
      return;
    }
    _draining = true;
    try {
      var items = queued;
      final now = DateTime.now().millisecondsSinceEpoch;
      final remaining = <Map<String, dynamic>>[];
      var softFailed = false;

      for (final item in items) {
        final nextAt = (item['nextAttemptAt'] as num?)?.toInt() ?? 0;
        if (nextAt > now) {
          remaining.add(item);
          continue;
        }
        try {
          await _process(item);
        } catch (e) {
          softFailed = true;
          final attempts = ((item['attempts'] as num?)?.toInt() ?? 0) + 1;
          if (attempts >= _maxAttempts) {
            await db.setGoogleCalendarSyncStatus('error');
            await db.setSetting(
              AppDatabase.googleCalendarLastErrorKey,
              e.toString(),
            );
            continue;
          }
          final delayMs = (1 << (attempts.clamp(0, 6))) * 1000;
          remaining.add({
            ...item,
            'attempts': attempts,
            'nextAttemptAt': now + delayMs,
          });
        }
      }
      await _writeOutbox(remaining);
      if (softFailed) {
        onSoftError?.call(
          "Couldn't update Google Calendar — will retry",
        );
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _process(Map<String, dynamic> item) async {
    final op = item['op'] as String? ?? 'upsert';
    final remoteId = item['remoteId'] as String? ?? '';
    if (remoteId.isEmpty) return;

    final token = await _token();
    if (token == null) {
      await db.setGoogleCalendarSyncStatus('needs_permission');
      throw StateError('needs_permission');
    }

    if (op == 'delete') {
      final eventId = item['googleEventId'] as String?;
      await _deleteEvent(token, eventId);
      final appt = await _byRemote(remoteId);
      if (appt != null && appt.googleEventId != null) {
        await db.setAppointmentGoogleEventId(appt.id, null);
      }
      await _markOk();
      return;
    }

    final appt = await _byRemote(remoteId);
    if (appt == null) return;
    final self = NotesAuth.currentUser?.uid ?? '';
    final owner =
        appt.practitionerUid.isEmpty ? self : appt.practitionerUid;
    if (owner != self) return;
    if (appt.deletedAt != null ||
        appt.status == AppointmentStatus.cancelled) {
      await _deleteEvent(token, appt.googleEventId);
      if (appt.googleEventId != null) {
        await db.setAppointmentGoogleEventId(appt.id, null);
      }
      await _markOk();
      return;
    }

    final client = await db.getClient(appt.clientId);
    final title = client == null
        ? 'NotesOnly appointment'
        : clientDisplayName(client);
    final mins = await db.getDefaultAppointmentMinutes();
    final tz = await db.getTimezone();
    final end = appointmentEffectiveEnd(appt.startsAt, appt.endsAt, mins);
    final body = <String, dynamic>{
      'summary': title,
      'description': _description(appt),
      'start': _dateTime(appt.startsAt, tz),
      'end': _dateTime(end, tz),
      'extendedProperties': {
        'private': {'notesOnlyRemoteId': appt.remoteId},
      },
    };

    final existingId = appt.googleEventId;
    if (existingId == null || existingId.isEmpty) {
      final id = await _insertEvent(token, body);
      await db.setAppointmentGoogleEventId(appt.id, id);
    } else {
      try {
        await _patchEvent(token, existingId, body);
      } on _CalendarHttpException catch (e) {
        if (e.statusCode == 404) {
          final id = await _insertEvent(token, body);
          await db.setAppointmentGoogleEventId(appt.id, id);
        } else if (e.statusCode == 401) {
          await NotesAuth.clearCalendarAccessToken();
          await db.setGoogleCalendarSyncStatus('needs_permission');
          rethrow;
        } else {
          rethrow;
        }
      }
    }
    await _markOk();
  }

  Future<String?> _token() async {
    final cached = NotesAuth.calendarAccessToken;
    if (cached != null && cached.isNotEmpty) return cached;
    return NotesAuth.requestCalendarAccess(interactive: false);
  }

  Future<void> _markOk() async {
    await db.setGoogleCalendarSyncStatus('connected');
    await db.setSetting(
      AppDatabase.googleCalendarLastOkKey,
      DateTime.now().toUtc().toIso8601String(),
    );
    await db.setSetting(AppDatabase.googleCalendarLastErrorKey, '');
  }

  Future<Appointment?> _byRemote(String remoteId) {
    return (db.select(db.appointments)
          ..where((t) => t.remoteId.equals(remoteId)))
        .getSingleOrNull();
  }

  String _description(Appointment appt) {
    final status = switch (appt.status) {
      AppointmentStatus.scheduled => 'Scheduled',
      AppointmentStatus.completed => 'Completed',
      AppointmentStatus.cancelled => 'Cancelled',
      AppointmentStatus.noShow => 'No-show',
    };
    final notes = appt.notes?.trim();
    if (notes == null || notes.isEmpty) return status;
    return '$status\n$notes';
  }

  Map<String, String> _dateTime(DateTime local, String tz) {
    final stamp =
        '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}T'
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
    return {'dateTime': stamp, 'timeZone': tz};
  }

  Future<String> _insertEvent(
    String token,
    Map<String, dynamic> body,
  ) async {
    final res = await _http.post(
      Uri.parse(_eventsUrl),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    _throwIfBad(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final id = data['id'] as String?;
    if (id == null || id.isEmpty) {
      throw StateError('Calendar insert returned no id');
    }
    return id;
  }

  Future<void> _patchEvent(
    String token,
    String eventId,
    Map<String, dynamic> body,
  ) async {
    final res = await _http.patch(
      Uri.parse('$_eventsUrl/${Uri.encodeComponent(eventId)}'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    _throwIfBad(res);
  }

  Future<void> _deleteEvent(String token, String? eventId) async {
    if (eventId == null || eventId.isEmpty) return;
    final res = await _http.delete(
      Uri.parse('$_eventsUrl/${Uri.encodeComponent(eventId)}'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode == 404 || res.statusCode == 410) return;
    if (res.statusCode == 401) {
      await NotesAuth.clearCalendarAccessToken();
      await db.setGoogleCalendarSyncStatus('needs_permission');
      throw _CalendarHttpException(401, res.body);
    }
    _throwIfBad(res);
  }

  void _throwIfBad(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    if (res.statusCode == 401) {
      throw _CalendarHttpException(401, res.body);
    }
    throw _CalendarHttpException(res.statusCode, res.body);
  }

  Future<List<Map<String, dynamic>>> _readOutbox() async {
    final raw = await db.getSetting(AppDatabase.googleCalendarOutboxKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeOutbox(List<Map<String, dynamic>> items) =>
      db.setSetting(AppDatabase.googleCalendarOutboxKey, jsonEncode(items));

  Future<void> _enqueue({
    required String remoteId,
    required String op,
    String? googleEventId,
  }) async {
    final items = await _readOutbox();
    items.removeWhere(
      (e) => e['remoteId'] == remoteId && e['op'] == op,
    );
    items.add({
      'remoteId': remoteId,
      'op': op,
      if (googleEventId != null) 'googleEventId': googleEventId,
      'attempts': 0,
      'nextAttemptAt': 0,
    });
    await _writeOutbox(items);
  }
}

class _CalendarHttpException implements Exception {
  _CalendarHttpException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  @override
  String toString() {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return 'Calendar HTTP $statusCode';
    final clip =
        trimmed.length > 180 ? '${trimmed.substring(0, 180)}…' : trimmed;
    return 'Calendar HTTP $statusCode: $clip';
  }
}
