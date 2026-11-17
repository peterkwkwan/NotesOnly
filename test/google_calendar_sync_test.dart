import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelvi_crm/data/appointment_overlap.dart';
import 'package:pelvi_crm/data/database.dart';
import 'package:pelvi_crm/data/google_calendar_sync.dart';

void main() {
  test('outbox retry delay uses earliest future nextAttemptAt', () {
    const now = 1_000_000;
    expect(googleCalendarOutboxRetryDelay([], now), isNull);
    expect(
      googleCalendarOutboxRetryDelay([
        {'nextAttemptAt': now},
        {'nextAttemptAt': now - 1},
      ], now),
      isNull,
    );
    expect(
      googleCalendarOutboxRetryDelay([
        {'nextAttemptAt': now + 8000},
        {'nextAttemptAt': now + 2000},
        {'nextAttemptAt': now - 50},
      ], now),
      const Duration(milliseconds: 2000),
    );
  });

  test('effective end fills null endsAt for Calendar payload', () {
    final start = DateTime(2026, 11, 14, 10, 0);
    expect(
      appointmentEffectiveEnd(start, null, 60),
      DateTime(2026, 11, 14, 11, 0),
    );
    expect(
      appointmentEffectiveEnd(start, start.add(const Duration(minutes: 45)), 60),
      DateTime(2026, 11, 14, 10, 45),
    );
  });

  test('google calendar settings keys stay device-local', () {
    expect(
      AppDatabase.isCloudSyncedSetting(
        AppDatabase.googleCalendarSyncEnabledKey,
      ),
      isFalse,
    );
    expect(
      AppDatabase.isCloudSyncedSetting(AppDatabase.googleCalendarOutboxKey),
      isFalse,
    );
  });

  test('backfill includes empty practitionerUid and empty googleEventId', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureDefaults();
    const uid = 'practitioner-1';
    final clientId = await db.insertClient(
      firstName: 'Angie',
      lastName: 'Baecker',
    );
    // Legacy row: empty owner + empty event id string should still backfill.
    final id = await db.into(db.appointments).insert(
      AppointmentsCompanion.insert(
        remoteId: const Value('remote-angie'),
        clientId: clientId,
        practitionerUid: const Value(''),
        startsAt: DateTime(2026, 11, 14, 21, 30),
        googleEventId: const Value(''),
        syncStatus: const Value(RowSyncStatus.pending),
      ),
    );
    expect(id, greaterThan(0));

    final needing = await db.myAppointmentsNeedingGoogleEvent(uid);
    expect(needing, hasLength(1));
    expect(needing.single.remoteId, 'remote-angie');

    final other = await db.myAppointmentsNeedingGoogleEvent('someone-else');
    expect(other, isEmpty);
  });
}
