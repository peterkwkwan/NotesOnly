import 'package:flutter_test/flutter_test.dart';
import 'package:pelvi_crm/data/appointment_overlap.dart';
import 'package:pelvi_crm/data/database.dart';

void main() {
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
}
