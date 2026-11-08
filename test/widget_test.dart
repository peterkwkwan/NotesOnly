import 'package:drift/drift.dart' show Migrator;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelvi_crm/app.dart';
import 'package:pelvi_crm/data/appointment_overlap.dart';
import 'package:pelvi_crm/data/backup.dart';
import 'package:pelvi_crm/data/database.dart';
import 'package:pelvi_crm/data/database_provider.dart';
import 'package:pelvi_crm/data/sync.dart';
import 'package:pelvi_crm/data/remote_id.dart';
import 'package:pelvi_crm/features/appointments/appointment_agenda_row.dart';
import 'package:pelvi_crm/features/appointments/appointment_form_screen.dart';
import 'package:pelvi_crm/features/calendar/calendar_screen.dart';
import 'package:pelvi_crm/features/clients/client_format.dart';
import 'package:pelvi_crm/features/clients/client_profile_screen.dart';
import 'package:pelvi_crm/features/clients/clients_screen.dart';
import 'package:pelvi_crm/features/notes/note_editor_screen.dart';
import 'package:pelvi_crm/features/notes/note_format.dart';
import 'package:pelvi_crm/features/notes/soap_dictation.dart';
import 'package:pelvi_crm/features/notes/soap_templates.dart';
import 'package:pelvi_crm/features/notifications/notifications_sheet.dart';
import 'package:pelvi_crm/theme/theme.dart';
import 'package:pelvi_crm/widgets/show_snack.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('top snack slot grows when conflict copy wraps', (tester) async {
    const message = 'Overlapping appointment: Peter Kwan at 15:00';
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              appBar: AppBar(title: const Text('New appointment')),
              body: Center(
                child: TextButton(
                  onPressed: () => showPelviSnackBar(context, message),
                  child: const Text('Show'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    final snack = tester.widget<SnackBar>(find.byType(SnackBar));
    final margin = snack.margin! as EdgeInsets;
    final slot = 640 - margin.top - margin.bottom;
    // Old helper hard-capped at 56 and clipped the time on wrap.
    expect(slot, greaterThan(56));
    expect(find.text(message), findsOneWidget);
  });

  test('LWW remote wins when updatedAt >= local', () {
    final older = DateTime.utc(2026, 1, 1);
    final newer = DateTime.utc(2026, 1, 2);
    expect(remoteWinsLww(older, newer), isTrue);
    expect(remoteWinsLww(newer, older), isFalse);
    expect(remoteWinsLww(newer, newer), isTrue);
  });

  test('newRemoteId is UUID-shaped and unique', () {
    final a = newRemoteId();
    final b = newRemoteId();
    expect(a, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(a, isNot(b));
  });

  test('insertClient assigns remoteId and pending sync', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureDefaults();
    final id = await db.insertClient(firstName: 'Ada', lastName: 'Lovelace');
    final client = await db.getClient(id);
    expect(client, isNotNull);
    expect(client!.remoteId, isNotEmpty);
    expect(client.syncStatus, RowSyncStatus.pending);
  });

  test('v5 column adds are idempotent via pragma check', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(await db.hasSqliteColumn('clients', 'remote_id'), isTrue);
    expect(await db.hasSqliteColumn('appointments', 'sync_status'), isTrue);
    expect(await db.hasSqliteColumn('notes', 'deleted_at'), isTrue);
    expect(await db.hasSqliteColumn('settings', 'updated_at'), isTrue);
    expect(await db.hasSqliteColumn('clients', 'no_such_col'), isFalse);

    // Re-adding existing sync columns must not throw (half-applied migrate).
    final m = Migrator(db);
    await db.migration.onUpgrade(m, 4, 5);
    await db.migration.onUpgrade(m, 4, 5);
    expect(await db.hasSqliteColumn('clients', 'remote_id'), isTrue);
  });

  test('dateTime ADD COLUMN uses constant unix default', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customStatement(
      'CREATE TABLE t_probe (id INTEGER NOT NULL PRIMARY KEY)',
    );
    await db.customStatement('INSERT INTO t_probe (id) VALUES (1)');
    await db.addDateTimeColumnConstDefault(
      table: 't_probe',
      column: 'updated_at',
    );
    expect(await db.hasSqliteColumn('t_probe', 'updated_at'), isTrue);
    // Idempotent second call (would throw if non-constant DEFAULT were used twice).
    await db.addDateTimeColumnConstDefault(
      table: 't_probe',
      column: 'updated_at',
    );
    final row = await db.customSelect('SELECT updated_at FROM t_probe').getSingle();
    expect(row.read<int>('updated_at'), greaterThan(0));
  });

  test('formatNoteDate is EEE, d MMM yyyy', () {
    expect(
      formatNoteDate(DateTime(2026, 10, 28)),
      'Wed, 28 Oct 2026',
    );
  });

  test('formatApptWhen is weekday date · HH:mm', () {
    expect(
      formatApptWhen(DateTime(2026, 11, 9, 14, 0)),
      'Mon, 9 Nov 2026 · 14:00',
    );
  });

  test('appendSoapTranscript joins with newline', () {
    expect(appendSoapTranscript('', '  pain on stairs  '), 'pain on stairs');
    expect(appendSoapTranscript('Sx: LBP', 'worse AM'), 'Sx: LBP\nworse AM');
    expect(appendSoapTranscript('keep', '  '), 'keep');
  });

  test('soap templates map S/O/A/P markers and preserve newlines', () {
    expect(soapTemplates.map((t) => t.label).toList(), [
      'Blank',
      'Postnatal Check',
      'Pelvic Floor',
      'DRAM',
    ]);
    expect(soapTemplateBlank.isBlank, isTrue);
    expect(soapTemplateBlank.hasFill, isFalse);

    final pn = soapTemplatePostnatal;
    expect(pn.subjective, contains('OBGYN'));
    expect(pn.subjective, contains('Coping/mood'));
    expect(pn.objective, contains('Obs / posture'));
    expect(pn.objective, contains('PF PERFECT'));
    expect(pn.assessment, contains('1. Postnatal check:'));
    expect(pn.assessment, contains('2. Home exercise program:'));
    expect(pn.plan, isEmpty);
    expect(pn.subjective, contains('\n'));

    final pf = soapTemplatePelvicFloor;
    expect(pf.subjective, isEmpty);
    expect(pf.objective, contains('Obs / posture'));
    expect(pf.objective, contains('DRAM Manual (head lift)l:'));
    expect(pf.objective, contains('PF PERFECT'));
    expect(pf.assessment, isEmpty);
    expect(pf.plan, isEmpty);

    final dram = soapTemplateDram;
    expect(dram.subjective, isEmpty);
    expect(dram.objective, contains('Obs / posture -'));
    expect(dram.objective, contains('Linea alba:'));
    expect(dram.objective, contains('DRAM Manual (head lift)l:'));
    expect(dram.objective, contains('C-section scar -'));
    expect(dram.assessment, isEmpty);
    expect(dram.plan, isEmpty);
  });

  test('nextWholeHour rounds past the hour, keeps exact hour', () {
    expect(
      nextWholeHour(DateTime(2026, 10, 28, 12, 48)),
      const TimeOfDay(hour: 13, minute: 0),
    );
    expect(
      nextWholeHour(DateTime(2026, 10, 28, 9, 0)),
      const TimeOfDay(hour: 9, minute: 0),
    );
    expect(
      nextWholeHour(DateTime(2026, 10, 28, 23, 1)),
      const TimeOfDay(hour: 0, minute: 0),
    );
  });

  test('appointment overlap uses default duration when end missing', () {
    final aStart = DateTime(2026, 10, 28, 9);
    final aEnd = appointmentEffectiveEnd(aStart, null, 60);
    final bStart = DateTime(2026, 10, 28, 9, 30);
    final bEnd = appointmentEffectiveEnd(bStart, null, 60);
    expect(appointmentsOverlap(aStart, aEnd, bStart, bEnd), isTrue);
    expect(
      appointmentsOverlap(
        aStart,
        aEnd,
        DateTime(2026, 10, 28, 10),
        DateTime(2026, 10, 28, 11),
      ),
      isFalse,
    );
    expect(
      appointmentConflictCopy(
        clientName: 'Ada Lovelace',
        startsAt: aStart,
      ),
      'Overlapping appointment: Ada Lovelace at 09:00',
    );
  });

  test('insertAppointment blocks overlapping slot', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureDefaults();

    final a = await db.insertClient(firstName: 'Ada', lastName: 'Lovelace');
    final b = await db.insertClient(firstName: 'Grace', lastName: 'Hopper');
    await db.insertAppointment(
      clientId: a,
      startsAt: DateTime(2026, 10, 28, 9),
    );

    await expectLater(
      db.insertAppointment(
        clientId: b,
        startsAt: DateTime(2026, 10, 28, 9, 30),
      ),
      throwsA(isA<AppointmentConflictException>()),
    );

    // Same start after move still blocked; update of self ok.
    final id = await db.insertAppointment(
      clientId: b,
      startsAt: DateTime(2026, 10, 28, 11),
    );
    await expectLater(
      db.updateAppointment(
        id: id,
        startsAt: DateTime(2026, 10, 28, 9, 15),
      ),
      throwsA(isA<AppointmentConflictException>()),
    );
    expect(
      await db.updateAppointment(
        id: id,
        startsAt: DateTime(2026, 10, 28, 11),
      ),
      isTrue,
    );
  });

  test('deleteAppointment soft-deletes row and unlinks note', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final clientId = await db.insertClient(firstName: 'Ada', lastName: 'L');
    final apptId = await db.insertAppointment(
      clientId: clientId,
      startsAt: DateTime(2026, 10, 28, 9),
    );
    final note = await db.getOrCreateNoteForAppointment(
      appointmentId: apptId,
      clientId: clientId,
      noteDate: DateTime(2026, 10, 28, 9),
    );

    await db.deleteAppointment(apptId);
    final tombstone = await db.getAppointment(apptId);
    expect(tombstone, isNotNull);
    expect(tombstone!.deletedAt, isNotNull);
    expect(tombstone.syncStatus, RowSyncStatus.pending);
    final kept = await db.getNote(note.id);
    expect(kept, isNotNull);
    expect(kept!.appointmentId, isNull);
  });

  testWidgets('profile appointment tap opens edit, not SOAP', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final clientId = await db.insertClient(
      firstName: 'Ada',
      lastName: 'Lovelace',
    );
    await db.insertAppointment(
      clientId: clientId,
      startsAt: DateTime(2026, 10, 28, 9, 30),
    );

    await tester.pumpWidget(
      AppDatabaseProvider(
        database: db,
        syncEngine: const StubSyncEngine(),
        child: MaterialApp(
          home: ClientProfileScreen(clientId: clientId),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Open note'), findsNothing);
    expect(find.text('Client profile'), findsOneWidget);
    expect(find.text('CLIENT SUMMARY'), findsOneWidget);
    await tester.tap(find.text(formatApptWhen(DateTime(2026, 10, 28, 9, 30))));
    await tester.pumpAndSettle();

    expect(find.text('Edit appointment'), findsOneWidget);
    expect(find.text('Create SOAP note'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('agenda row tap opens edit, not SOAP', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final clientId = await db.insertClient(
      firstName: 'Ada',
      lastName: 'Lovelace',
    );
    final apptId = await db.insertAppointment(
      clientId: clientId,
      startsAt: DateTime(2026, 10, 29, 10, 0),
    );
    final appt = await db.getAppointment(apptId);
    final client = await db.getClient(clientId);

    await tester.pumpWidget(
      AppDatabaseProvider(
        database: db,
        syncEngine: const StubSyncEngine(),
        child: MaterialApp(
          home: Scaffold(
            body: AppointmentAgendaRow(
              appointment: appt!,
              client: client!,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Ada Lovelace'));
    await tester.pumpAndSettle();

    expect(find.text('Edit appointment'), findsOneWidget);
    expect(find.text('Create SOAP note'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    expect(find.text('Subjective'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('first-run shows when practitioner name missing', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(
      PelviApp(
        database: db,
        signedInOverride: Stream.value(true),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('NotesOnly'), findsOneWidget);
    expect(find.text('What should we call your practice?'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('shell opens when practitioner name is set', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.setPractitionerName('Test Clinic');

    await tester.pumpWidget(
      PelviApp(
        database: db,
        signedInOverride: Stream.value(true),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Today'), findsWidgets);
    expect(find.text('Calendar'), findsWidgets);
    expect(find.text('Clients'), findsWidgets);
    expect(find.text('More'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('signed-out shows Google sign-in gate', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.setPractitionerName('Test Clinic');
    await tester.binding.setSurfaceSize(const Size(412, 892));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      PelviApp(
        database: db,
        signedInOverride: Stream.value(false),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('NotesOnly'), findsOneWidget);
    expect(find.textContaining('A little less admin'), findsOneWidget);
    expect(find.text('Today'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  test('client and appointment round-trip in memory db', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final clientId = await db.insertClient(
      firstName: 'Ada',
      lastName: 'Lovelace',
      phone: '123',
      email: 'ada@example.com',
      emergencyContact: 'Lord Byron',
      emergencyContactPhone: '555',
      notes: 'prefers mornings',
    );
    final client = await db.getClient(clientId);
    expect(client?.firstName, 'Ada');
    expect(client?.phone, '123');
    expect(client?.emergencyContact, 'Lord Byron');
    expect(client?.emergencyContactPhone, '555');
    expect(client?.notes, 'prefers mornings');

    await db.updateClient(
      id: clientId,
      firstName: 'Ada',
      lastName: 'Lovelace',
      phone: '123',
      email: 'ada@example.com',
      emergencyContact: 'Lord Byron',
      emergencyContactPhone: '556',
      notes: 'updated note',
    );
    final updated = await db.getClient(clientId);
    expect(updated?.notes, 'updated note');
    expect(updated?.emergencyContactPhone, '556');

    final starts = DateTime(2026, 10, 28, 9, 30);
    await db.insertAppointment(clientId: clientId, startsAt: starts);

    final forClient = await db.watchAppointmentsForClient(clientId).first;
    expect(forClient, hasLength(1));
    expect(forClient.first.status, AppointmentStatus.scheduled);

    final today = await db.watchAppointmentsWithClientOnDay(starts).first;
    expect(today, hasLength(1));
    expect(today.first.client.lastName, 'Lovelace');
  });

  test('month appointment counts group by local day', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final clientId = await db.insertClient(
      firstName: 'Ada',
      lastName: 'Lovelace',
    );
    await db.insertAppointment(
      clientId: clientId,
      startsAt: DateTime(2026, 10, 28, 9),
    );
    await db.insertAppointment(
      clientId: clientId,
      startsAt: DateTime(2026, 10, 28, 14),
    );
    await db.insertAppointment(
      clientId: clientId,
      startsAt: DateTime(2026, 10, 29, 10),
    );
    await db.insertAppointment(
      clientId: clientId,
      startsAt: DateTime(2026, 11, 1, 10),
    );

    final counts =
        await db.watchAppointmentCountsForMonth(DateTime(2026, 10)).first;
    expect(counts[DateTime(2026, 10, 28)], 2);
    expect(counts[DateTime(2026, 10, 29)], 1);
    expect(counts.containsKey(DateTime(2026, 11, 1)), isFalse);
  });

  testWidgets('Calendar tab shows month grid and day list', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final clientId = await db.insertClient(
      firstName: 'Ada',
      lastName: 'Lovelace',
    );
    final now = DateTime.now();
    await db.insertAppointment(
      clientId: clientId,
      startsAt: DateTime(now.year, now.month, now.day, 10),
    );

    await tester.pumpWidget(
      AppDatabaseProvider(
        database: db,
        syncEngine: const StubSyncEngine(),
        child: const MaterialApp(home: CalendarScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Tap a day to see appointments'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('Calendar empty-day well opens create for selected day',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      AppDatabaseProvider(
        database: db,
        syncEngine: const StubSyncEngine(),
        child: const MaterialApp(home: CalendarScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('No appointments this day.'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);

    // Tap the message (not the CTA) — whole well is the hit target.
    await tester.tap(find.text('No appointments this day.'));
    await tester.pumpAndSettle();

    expect(find.text('New appointment'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  test('SOAP stays editable; copy last is same-client only', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final clientId = await db.insertClient(
      firstName: 'Ada',
      lastName: 'Lovelace',
    );
    final otherId = await db.insertClient(
      firstName: 'Other',
      lastName: 'Client',
    );
    final appt1 = await db.insertAppointment(
      clientId: clientId,
      startsAt: DateTime(2026, 10, 1, 10),
    );
    final appt2 = await db.insertAppointment(
      clientId: clientId,
      startsAt: DateTime(2026, 10, 28, 10),
    );
    final otherAppt = await db.insertAppointment(
      clientId: otherId,
      startsAt: DateTime(2026, 10, 27, 10),
    );

    final first = await db.getOrCreateNoteForAppointment(
      appointmentId: appt1,
      clientId: clientId,
      noteDate: DateTime(2026, 10, 1, 10),
    );
    await db.updateNoteSoap(
      id: first.id,
      subjective: 'pain',
      objective: 'ROM limited',
      assessment: 'strain',
      plan: 'ice',
    );

    // Always editable after the fact.
    await db.updateNoteSoap(
      id: first.id,
      subjective: 'rewritten',
      objective: 'ROM limited',
      assessment: 'strain',
      plan: 'ice',
    );
    expect((await db.getNote(first.id))?.subjective, 'rewritten');

    final otherNote = await db.getOrCreateNoteForAppointment(
      appointmentId: otherAppt,
      clientId: otherId,
      noteDate: DateTime(2026, 10, 27, 10),
    );
    await db.updateNoteSoap(
      id: otherNote.id,
      subjective: 'other client',
      objective: 'x',
      assessment: 'x',
      plan: 'x',
    );

    final second = await db.getOrCreateNoteForAppointment(
      appointmentId: appt2,
      clientId: clientId,
      noteDate: DateTime(2026, 10, 28, 10),
    );
    final last = await db.getLastNoteForClient(
      clientId,
      exceptNoteId: second.id,
    );
    expect(last?.id, first.id);
    expect(last?.subjective, 'rewritten');

    expect(
      await db.copySoapIntoNote(targetId: second.id, source: last!),
      isTrue,
    );
    final copied = await db.getNote(second.id);
    expect(copied?.subjective, 'rewritten');
    expect(copied?.plan, 'ice');

    final again = await db.getOrCreateNoteForAppointment(
      appointmentId: appt2,
      clientId: clientId,
    );
    expect(again.id, second.id);

    final history = await db.watchNotesForClient(clientId).first;
    expect(history, hasLength(2));
  });

  test('recall due uses window; cancelled ignored; notes count as visit', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureDefaults();
    expect(await db.getRecallDays(), 30);

    final now = DateTime(2026, 10, 28, 12);
    final stale = await db.insertClient(firstName: 'Stale', lastName: 'Client');
    final fresh = await db.insertClient(firstName: 'Fresh', lastName: 'Client');
    final never = await db.insertClient(firstName: 'Never', lastName: 'Seen');
    final cancelledOnly =
        await db.insertClient(firstName: 'Cancel', lastName: 'Only');

    await db.insertAppointment(
      clientId: stale,
      startsAt: now.subtract(const Duration(days: 40)),
      status: AppointmentStatus.completed,
    );
    await db.insertAppointment(
      clientId: fresh,
      startsAt: now.subtract(const Duration(days: 5)),
    );
    await db.insertAppointment(
      clientId: cancelledOnly,
      startsAt: now.subtract(const Duration(days: 2)),
      status: AppointmentStatus.cancelled,
    );

    var due = await db.getRecallDueClients(now: now);
    // Never-seen + cancelled-only stay out; only stale (seen, past window).
    expect(due.map((e) => e.client.id), [stale]);
    expect(due.map((e) => e.client.id), isNot(contains(fresh)));
    expect(due.map((e) => e.client.id), isNot(contains(never)));
    expect(due.map((e) => e.client.id), isNot(contains(cancelledOnly)));

    // First non-cancelled appt + recent note → no longer due.
    final appt = await db.insertAppointment(
      clientId: never,
      startsAt: now.subtract(const Duration(days: 60)),
      status: AppointmentStatus.completed,
    );
    await db.getOrCreateNoteForAppointment(
      appointmentId: appt,
      clientId: never,
      noteDate: now.subtract(const Duration(days: 3)),
    );
    due = await db.getRecallDueClients(now: now);
    expect(due.map((e) => e.client.id), isNot(contains(never)));

    await db.setRecallDays(0);
    expect(await db.getRecallDays(), 0);
    due = await db.getRecallDueClients(now: now);
    expect(due, isEmpty);
    expect(
      computeRecallDue(
        clients: await db.watchClients().first,
        appointments: await db.select(db.appointments).get(),
        notes: await db.select(db.notes).get(),
        recallDays: 0,
        now: now,
      ),
      isEmpty,
    );

    await db.setRecallDays(7);
    expect(await db.getRecallDays(), 7);
    due = await db.getRecallDueClients(now: now);
    // Fresh at 5 days is still inside a 7-day window.
    expect(due.map((e) => e.client.id), isNot(contains(fresh)));
    final weekPlus =
        await db.insertClient(firstName: 'Week', lastName: 'Plus');
    await db.insertAppointment(
      clientId: weekPlus,
      startsAt: now.subtract(const Duration(days: 10)),
      status: AppointmentStatus.completed,
    );
    due = await db.getRecallDueClients(now: now);
    expect(due.map((e) => e.client.id), contains(weekPlus));

    expect(
      computeRecallDue(
        clients: await db.watchClients().first,
        appointments: [],
        notes: [],
        recallDays: 30,
        now: now,
      ),
      isEmpty,
    );
    expect(formatLastSeenCaption(null, now), 'Never seen');
    expect(
      formatLastSeenCaption(now.subtract(const Duration(days: 12)), now),
      'Last seen 12 days ago',
    );

    // Mute hides from Due; Clear only from inbox.
    await db.setRecallMuted(stale, true);
    expect(await db.isRecallMuted(stale), isTrue);
    due = await db.getRecallDueClients(now: now);
    expect(due.map((e) => e.client.id), isNot(contains(stale)));
    expect(
      computeRecallDue(
        clients: await db.watchClients().first,
        appointments: await db.select(db.appointments).get(),
        notes: await db.select(db.notes).get(),
        recallDays: 7,
        now: now,
        mutedClientIds: {stale},
      ).map((e) => e.client.id),
      isNot(contains(stale)),
    );

    await db.setRecallMuted(stale, false);
    await db.clearRecallInboxItem(stale);
    due = await db.getRecallDueClients(now: now);
    expect(due.map((e) => e.client.id), contains(stale));
    final inbox = await db.getRecallInboxClients(now: now);
    expect(inbox.map((e) => e.client.id), isNot(contains(stale)));
  });

  test('client search matches name phone email; recent order + cap', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final ada = await db.insertClient(
      firstName: 'Ada',
      lastName: 'Lovelace',
      phone: '9123 4567',
      email: 'ada@example.com',
    );
    final grace = await db.insertClient(
      firstName: 'Grace',
      lastName: 'Hopper',
      phone: '555',
      email: 'grace@navy.mil',
    );
    final all = await db.watchClients().first;

    expect(filterClients(all, 'lovelace').single.id, ada);
    expect(filterClients(all, '9123').single.id, ada);
    expect(filterClients(all, 'navy.mil').single.id, grace);
    expect(filterClients(all, 'zzz'), isEmpty);

    await db.touchRecentClient(ada);
    await db.touchRecentClient(grace);
    await db.touchRecentClient(ada);
    expect(await db.watchRecentClientIds().first, [ada, grace]);

    for (var i = 0; i < AppDatabase.recentClientLimit + 2; i++) {
      final id = await db.insertClient(
        firstName: 'C$i',
        lastName: 'Client',
      );
      await db.touchRecentClient(id);
    }
    final recent = await db.watchRecentClientIds().first;
    expect(recent, hasLength(AppDatabase.recentClientLimit));
    expect(clientsInIdOrder(await db.watchClients().first, recent), hasLength(AppDatabase.recentClientLimit));
  });

  test('stickyLetterAtOffset returns one letter, never a stack', () {
    const sections = [
      (letter: 'B', count: 1),
      (letter: 'C', count: 1),
      (letter: 'J', count: 2),
    ];
    final bEnd = kAlphaLetterHeaderHeight + kAlphaClientRowHeight;
    final cEnd = bEnd + kAlphaLetterHeaderHeight + kAlphaClientRowHeight;
    expect(stickyLetterAtOffset(sections, 0), 'B');
    expect(stickyLetterAtOffset(sections, bEnd - 0.1), 'B');
    expect(stickyLetterAtOffset(sections, bEnd), 'C');
    expect(stickyLetterAtOffset(sections, cEnd), 'J');
    expect(stickyLetterAtOffset(sections, cEnd + 50), 'J');
  });

  test('stickyLetterAtOffset treats Pinned as one leading section', () {
    const sections = [
      (letter: kPinnedSectionLabel, count: 2),
      (letter: 'H', count: 1),
      (letter: 'L', count: 1),
    ];
    final pinnedEnd = kAlphaLetterHeaderHeight +
        2 * kAlphaClientRowHeight +
        kAlphaClientDividerHeight;
    expect(stickyLetterAtOffset(sections, 0), kPinnedSectionLabel);
    expect(stickyLetterAtOffset(sections, pinnedEnd - 0.1), kPinnedSectionLabel);
    expect(stickyLetterAtOffset(sections, pinnedEnd), 'H');
  });

  test('pin clients + letter groups + deleteClient scrub', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final ada = await db.insertClient(
      firstName: 'Ada',
      lastName: 'Lovelace',
    );
    final grace = await db.insertClient(
      firstName: 'Grace',
      lastName: 'Hopper',
    );
    final zed = await db.insertClient(
      firstName: 'Zed',
      lastName: '9nine',
    );

    final sorted = await db.watchClients().first;
    final groups = groupClientsByLetter(sorted);
    expect(groups.map((g) => g.letter), ['#', 'H', 'L']);
    expect(clientSectionLetter(sorted.firstWhere((c) => c.id == zed)), '#');

    final sections = [
      for (final g in groups) (letter: g.letter, count: g.clients.length),
    ];
    // One letter at a time — past `#` (1 client) lands on H, not a B/C/J stack.
    final afterHash = kAlphaLetterHeaderHeight + kAlphaClientRowHeight;
    expect(stickyLetterAtOffset(sections, 0), '#');
    expect(stickyLetterAtOffset(sections, afterHash), 'H');
    expect(
      stickyLetterAtOffset(
        sections,
        afterHash +
            kAlphaLetterHeaderHeight +
            kAlphaClientRowHeight,
      ),
      'L',
    );

    await db.setClientsPinned([ada, grace], true);
    expect(await db.getPinnedClientIds(), [grace, ada]);
    await db.setClientsPinned([ada], false);
    expect(await db.getPinnedClientIds(), [grace]);

    await db.touchRecentClient(grace);
    await db.setRecallMuted(grace, true);
    await db.insertAppointment(
      clientId: grace,
      startsAt: DateTime(2026, 1, 1, 10),
    );
    await db.deleteClient(grace);
    final gone = await db.getClient(grace);
    expect(gone?.deletedAt, isNotNull);
    expect(await db.watchClients().first, isNot(contains(gone)));
    expect(await db.getPinnedClientIds(), isEmpty);
    expect(await db.watchRecentClientIds().first, isEmpty);
    expect(await db.getRecallMutedIds(), isEmpty);
    final appts = await db.select(db.appointments).get();
    expect(appts, hasLength(1));
    expect(appts.single.deletedAt, isNotNull);
  });

  testWidgets('Clients tab search, recent, pinned section, letter headers', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final ada = await db.insertClient(
      firstName: 'Ada',
      lastName: 'Lovelace',
      phone: '111',
    );
    await db.insertClient(firstName: 'Grace', lastName: 'Hopper');
    await db.touchRecentClient(ada);
    await db.setClientsPinned([ada], true);

    await tester.pumpWidget(
      AppDatabaseProvider(
        database: db,
        syncEngine: const StubSyncEngine(),
        child: const MaterialApp(home: ClientsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Search name, phone, or email'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.textContaining('Due'), findsOneWidget);
    expect(find.text('RECENT'), findsOneWidget);
    expect(find.text(kPinnedSectionLabel), findsOneWidget);
    expect(find.text('PINNED'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    expect(find.text('AL'), findsWidgets); // Ada Lovelace initials avatar
    // In-list A–Z letters only (one scroll sticky overlay, not N pinned headers).
    expect(find.text('H'), findsOneWidget);
    expect(find.text('L'), findsOneWidget);
    // Recent chip + pinned row + A–Z row (not three full A–Z copies).
    expect(find.text('Ada Lovelace'), findsNWidgets(3));

    await tester.enterText(find.byType(TextField), 'hopper');
    await tester.pump();
    expect(find.text('RECENT'), findsNothing);
    expect(find.text(kPinnedSectionLabel), findsNothing);
    expect(find.text('Grace Hopper'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  test('dark mode setting persists via Drift prefs', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureDefaults();

    expect(await db.getDarkModeEnabled(), isFalse);
    await db.setDarkModeEnabled(true);
    expect(await db.getDarkModeEnabled(), isTrue);
    expect(await db.watchDarkModeEnabled().first, isTrue);
    await db.setDarkModeEnabled(false);
    expect(await db.getDarkModeEnabled(), isFalse);
  });

  test('settings defaults + backup JSON round-trip', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureDefaults();

    expect(await db.getDefaultAppointmentMinutes(), 60);
    expect(await db.getClinicHoursStart(), '09:00');
    expect(await db.getClinicHoursEnd(), '18:00');
    expect(await db.getTimezone(), 'Asia/Hong_Kong');
    expect(await db.getRecallNotificationsEnabled(), isTrue);
    expect(await db.getDarkModeEnabled(), isFalse);

    await db.setPractitionerName('Pelvi Clinic');
    await db.setDefaultAppointmentMinutes(45);
    await db.setClinicHoursStart('08:30');
    await db.setClinicHoursEnd('17:00');
    await db.setTimezone('America/Toronto');
    await db.setRecallNotificationsEnabled(false);

    final clientId = await db.insertClient(
      firstName: 'Ada',
      lastName: 'Lovelace',
      phone: '123',
    );
    final apptId = await db.insertAppointment(
      clientId: clientId,
      startsAt: DateTime(2026, 10, 28, 9),
    );
    final note = await db.getOrCreateNoteForAppointment(
      appointmentId: apptId,
      clientId: clientId,
      noteDate: DateTime(2026, 10, 28, 9),
    );
    await db.updateNoteSoap(
      id: note.id,
      subjective: 'pain',
      objective: 'rom',
      assessment: 'strain',
      plan: 'ice',
    );

    final json = encodeBackupJson(await buildBackupMap(db));
    final csv = await buildBackupCsv(db);
    expect(csv.clients, contains('Ada'));
    expect(csv.appointments, contains('$clientId'));
    expect(csv.notes, contains('pain'));

    // Wipe and restore into a fresh db.
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    await other.ensureDefaults();
    await other.setPractitionerName('Temp');
    await other.insertClient(firstName: 'Temp', lastName: 'Client');

    await restoreBackupMap(other, decodeBackupJson(json));
    expect(await other.getPractitionerName(), 'Pelvi Clinic');
    expect(await other.getDefaultAppointmentMinutes(), 45);
    expect(await other.getClinicHoursStart(), '08:30');
    expect(await other.getTimezone(), 'America/Toronto');
    expect(await other.getRecallNotificationsEnabled(), isFalse);

    final clients = await other.watchClients().first;
    expect(clients, hasLength(1));
    expect(clients.first.firstName, 'Ada');
    expect(clients.first.id, clientId);

    final appts = await other.watchAppointmentsForClient(clientId).first;
    expect(appts, hasLength(1));
    expect(appts.first.id, apptId);

    final notes = await other.watchNotesForClient(clientId).first;
    expect(notes, hasLength(1));
    expect(notes.first.subjective, 'pain');

    expect(
      () => decodeBackupJson('{"format":"nope","version":1}'),
      throwsFormatException,
    );
  });

  testWidgets('note editor leaves loading after open', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final clientId = await db.insertClient(
      firstName: 'Peter',
      lastName: 'Kwan',
    );
    final apptId = await db.insertAppointment(
      clientId: clientId,
      startsAt: DateTime(2026, 10, 28, 13, 50),
    );
    final note = await db.getOrCreateNoteForAppointment(
      appointmentId: apptId,
      clientId: clientId,
      noteDate: DateTime(2026, 10, 28, 13, 50),
    );

    await tester.pumpWidget(
      AppDatabaseProvider(
        database: db,
        syncEngine: const StubSyncEngine(),
        child: MaterialApp(
          home: NoteEditorScreen(noteId: note.id),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Peter Kwan'), findsOneWidget);
    expect(find.text('Wed, 28 Oct 2026'), findsOneWidget);
    expect(find.text('Copy last note'), findsOneWidget);
    expect(find.byIcon(Icons.content_copy_outlined), findsOneWidget);
    expect(find.text('Blank'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    expect(find.byTooltip('Choose template'), findsOneWidget);
    expect(find.text('Template'), findsNothing);
    expect(find.textContaining('Template:'), findsNothing);
    expect(find.text('Go to client profile'), findsNothing);
    expect(find.byTooltip('Client profile'), findsOneWidget);
    expect(find.byTooltip('Dictate'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
  });

  testWidgets('profile appointments multi-delete mode', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final clientId = await db.insertClient(
      firstName: 'Ada',
      lastName: 'Lovelace',
    );
    final a1 = await db.insertAppointment(
      clientId: clientId,
      startsAt: DateTime(2026, 10, 28, 9, 30),
    );
    final a2 = await db.insertAppointment(
      clientId: clientId,
      startsAt: DateTime(2026, 10, 29, 10),
    );

    await tester.pumpWidget(
      AppDatabaseProvider(
        database: db,
        syncEngine: const StubSyncEngine(),
        child: MaterialApp(
          home: ClientProfileScreen(clientId: clientId),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.longPress(
      find.text(formatApptWhen(DateTime(2026, 10, 28, 9, 30))),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text(formatApptWhen(DateTime(2026, 10, 29, 10))));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 2 appointments?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete').last);
    await tester.pumpAndSettle();

    expect((await db.getAppointment(a1))?.deletedAt, isNotNull);
    expect((await db.getAppointment(a2))?.deletedAt, isNotNull);
    expect(find.textContaining('selected'), findsNothing);
    expect(find.text('Edit'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  test('recall due stream seeds late listeners', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureDefaults();

    // First listener warms the cached broadcast (AppShell / Today).
    final first = await db.watchRecallDueClients().first;
    expect(first, isEmpty);

    // Second listener (notifications sheet) must not hang waiting for a
    // non-replaying broadcast emission.
    final second = await db
        .watchRecallDueClients()
        .timeout(const Duration(seconds: 2))
        .first;
    expect(second, isEmpty);
  });

  testWidgets('notifications sheet leaves loading after open', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureDefaults();

    // Warm cached broadcast (AppShell), then open sheet as a late listener.
    db.watchRecallDueClients().listen((_) {}).cancel();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.pumpWidget(
      AppDatabaseProvider(
        database: db,
        syncEngine: const StubSyncEngine(),
        child: MaterialApp(
          theme: pelviLightTheme(),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () => showNotificationsSheet(context),
                  child: const Text('Bell'),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Bell'));
    await tester.pump(); // sheet route
    await tester.pump(); // microtask seed
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('No recalls due.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('notifications sheet shows bordered recall card + initials', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureDefaults();

    final now = DateTime(2026, 11, 7, 12);
    final clientId = await db.insertClient(
      firstName: 'Susie',
      lastName: 'Rose',
    );
    await db.insertAppointment(
      clientId: clientId,
      startsAt: now.subtract(const Duration(days: 92)),
      status: AppointmentStatus.completed,
    );

    db.watchRecallDueClients().listen((_) {}).cancel();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.pumpWidget(
      AppDatabaseProvider(
        database: db,
        syncEngine: const StubSyncEngine(),
        child: MaterialApp(
          theme: pelviLightTheme(),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () => showNotificationsSheet(context),
                  child: const Text('Bell'),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Bell'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Recall · Susie Rose'), findsOneWidget);
    expect(find.text('SR'), findsOneWidget);
    expect(find.textContaining('Last seen'), findsOneWidget);
    final client = await db.getClient(clientId);
    expect(client, isNotNull);
    expect(clientInitials(client!), 'SR');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
