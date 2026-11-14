import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelvi_crm/data/database.dart';
import 'package:pelvi_crm/data/org.dart';

OrgMember _member(
  String uid,
  List<OrgRole> roles, {
  bool active = true,
  String? email,
}) {
  return OrgMember(
    uid: uid,
    email: email ?? '$uid@clinic.test',
    roles: roles,
    active: active,
  );
}

void main() {
  test('clearLocalClinicForAccountSwitch wipes clinic and keeps theme', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureDefaults();
    await db.setSetting(AppDatabase.themeModeKey, 'dark');
    await db.setSetting(AppDatabase.activeOrgIdKey, 'org-amber');
    await db.setSetting(AppDatabase.syncBoundUidKey, 'uid-peter');
    await db.setSetting(AppDatabase.practitionerNameKey, 'Peter');
    await db.into(db.clients).insert(
          ClientsCompanion.insert(firstName: 'Ada', lastName: 'Client'),
        );

    await db.clearLocalClinicForAccountSwitch();

    expect(await db.getSetting(AppDatabase.themeModeKey), 'dark');
    expect(await db.getSetting(AppDatabase.activeOrgIdKey), isNull);
    expect(await db.getSetting(AppDatabase.syncBoundUidKey), isNull);
    expect(await db.getSetting(AppDatabase.practitionerNameKey), isNull);
    expect(await db.getSetting(AppDatabase.clinicNameKey), isNull);
    expect(await db.hasClinicalRows(), isFalse);
    expect(await db.getSetting(AppDatabase.recallDaysKey), isNotNull);
  });

  test('display name survives clinic wipe for the same uid', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureDefaults();
    await db.setSetting(AppDatabase.syncBoundUidKey, 'uid-peter');
    await db.setPractitionerName('Peter Kwan');
    expect(await db.getPractitionerName(), 'Peter Kwan');
    expect(
      await db.getSetting(AppDatabase.practitionerNameKeyFor('uid-peter')),
      'Peter Kwan',
    );

    await db.clearLocalClinicForAccountSwitch();

    // Session key is wiped; per-uid copy remains for the next sign-in.
    expect(await db.getSetting(AppDatabase.practitionerNameKey), isNull);
    expect(await db.getPractitionerName(uid: 'uid-peter'), 'Peter Kwan');

    await db.setSetting(AppDatabase.syncBoundUidKey, 'uid-peter');
    await db.rehydratePractitionerNameForUid('uid-peter');
    expect(await db.getPractitionerName(), 'Peter Kwan');
    expect(await db.getSetting(AppDatabase.practitionerNameKey), 'Peter Kwan');

    // A different Google account does not inherit the name.
    expect(await db.getPractitionerName(uid: 'uid-other'), isNull);
  });

  test('clearLocalClinicForAccountSwitch skips missing templates table',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureDefaults();
    await db.setSetting(AppDatabase.themeModeKey, 'dark');
    await db.setSetting(AppDatabase.activeOrgIdKey, 'org-amber');
    await db.into(db.clients).insert(
          ClientsCompanion.insert(firstName: 'Ada', lastName: 'Client'),
        );
    await db.customStatement('DROP TABLE templates');
    expect(await db.hasSqliteTable('templates'), isFalse);

    await db.clearLocalClinicForAccountSwitch();

    expect(await db.getSetting(AppDatabase.themeModeKey), 'dark');
    expect(await db.getSetting(AppDatabase.activeOrgIdKey), isNull);
    expect(await db.hasClinicalRows(), isFalse);
    expect(await db.hasSqliteTable('templates'), isFalse);
  });

  test('ensureDefaults migrates legacy practitioner_name into clinic_name',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.setSetting(AppDatabase.practitionerNameKey, 'Amber Health');
    await db.ensureDefaults();
    expect(await db.getClinicName(), 'Amber Health');
    expect(await db.getPractitionerName(), 'Amber Health');
    expect(AppDatabase.isCloudSyncedSetting(AppDatabase.clinicNameKey), isTrue);
    expect(
      AppDatabase.isCloudSyncedSetting(AppDatabase.practitionerNameKey),
      isFalse,
    );
    expect(
      AppDatabase.isCloudSyncedSetting(
        AppDatabase.practitionerNameKeyFor('uid-peter'),
      ),
      isTrue,
    );
    expect(
      AppDatabase.isCloudSyncedSetting(AppDatabase.pinnedClientIdsKey),
      isTrue,
    );
    expect(
      AppDatabase.isCloudSyncedSetting(AppDatabase.recentClientIdsKey),
      isFalse,
    );
  });

  test('pinned pins store remoteIds and still resolve legacy local ints', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureDefaults();

    final ada = await db.insertClient(firstName: 'Ada', lastName: 'Lovelace');
    final grace = await db.insertClient(firstName: 'Grace', lastName: 'Hopper');
    final adaRow = (await db.getClient(ada))!;
    final graceRow = (await db.getClient(grace))!;

    await db.setClientsPinned([ada, grace], true);
    expect(
      await db.getSetting(AppDatabase.pinnedClientIdsKey),
      '${graceRow.remoteId},${adaRow.remoteId}',
    );
    expect(await db.getPinnedClientIds(), [grace, ada]);

    // Legacy device-local int list still resolves until rewritten.
    await db.into(db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: AppDatabase.pinnedClientIdsKey,
            value: '$ada,$grace',
            updatedAt: Value(DateTime.now()),
            syncStatus: const Value(RowSyncStatus.synced),
          ),
        );
    expect(await db.getPinnedClientIds(), [ada, grace]);

    await db.rewritePinnedClientIdsToRemoteIds();
    expect(
      await db.getSetting(AppDatabase.pinnedClientIdsKey),
      '${adaRow.remoteId},${graceRow.remoteId}',
    );
    final pinnedRow = await (db.select(db.settings)
          ..where((t) => t.key.equals(AppDatabase.pinnedClientIdsKey)))
        .getSingle();
    expect(pinnedRow.syncStatus, RowSyncStatus.pending);
  });

  test('mirrorPractitionerNameToCloudOnce queues prior local name once',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureDefaults();
    await db.setSetting(AppDatabase.syncBoundUidKey, 'uid-peter');
    // Simulate a pre-cloud local write (synced, not pending).
    await db.into(db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: AppDatabase.practitionerNameKeyFor('uid-peter'),
            value: 'Peter Kwan',
            syncStatus: const Value(RowSyncStatus.synced),
          ),
        );
    await db.mirrorPractitionerNameToCloudOnce('uid-peter');
    final row = await (db.select(db.settings)
          ..where(
            (t) => t.key.equals(
              AppDatabase.practitionerNameKeyFor('uid-peter'),
            ),
          ))
        .getSingle();
    expect(row.syncStatus, RowSyncStatus.pending.index);

    await (db.update(db.settings)
          ..where(
            (t) => t.key.equals(
              AppDatabase.practitionerNameKeyFor('uid-peter'),
            ),
          ))
        .write(
      const SettingsCompanion(syncStatus: Value(RowSyncStatus.synced)),
    );
    await db.mirrorPractitionerNameToCloudOnce('uid-peter');
    final again = await (db.select(db.settings)
          ..where(
            (t) => t.key.equals(
              AppDatabase.practitionerNameKeyFor('uid-peter'),
            ),
          ))
        .getSingle();
    expect(again.syncStatus, RowSyncStatus.synced.index);
  });

  test('Practice settings and clinic invites are owner/admin only', () {
    expect(canManagePracticeSettings(const [OrgRole.owner]), isTrue);
    expect(canManagePracticeSettings(const [OrgRole.admin]), isTrue);
    expect(canManagePracticeSettings(const [OrgRole.practitioner]), isFalse);
    expect(canSendClinicInvite(const [OrgRole.owner]), isTrue);
    expect(canSendClinicInvite(const [OrgRole.admin]), isTrue);
    expect(canSendClinicInvite(const [OrgRole.practitioner]), isFalse);
    expect(
      clinicInviteRolesFor(const [OrgRole.owner]),
      [OrgRole.practitioner, OrgRole.admin],
    );
    expect(
      clinicInviteRolesFor(const [OrgRole.admin]),
      [OrgRole.practitioner, OrgRole.admin],
    );
    expect(clinicInviteRolesFor(const [OrgRole.practitioner]), isEmpty);
    expect(
      canInviteWithRole(
        actor: const [OrgRole.admin],
        role: OrgRole.owner,
      ),
      isFalse,
    );
    expect(
      canInviteWithRole(
        actor: const [OrgRole.admin],
        role: OrgRole.admin,
      ),
      isTrue,
    );
    expect(
      canInviteWithRole(
        actor: const [OrgRole.owner],
        role: OrgRole.owner,
      ),
      isTrue,
    );
  });

  test('parseClinicInviteEmails trims skips empties and keeps order', () {
    expect(parseClinicInviteEmails(''), isEmpty);
    expect(parseClinicInviteEmails(' ; ; '), isEmpty);
    expect(
      parseClinicInviteEmails(' Ada@Gmail.com ; bob@x.test;; '),
      ['ada@gmail.com', 'bob@x.test'],
    );
    expect(isClinicInviteEmail('ada@gmail.com'), isTrue);
    expect(isClinicInviteEmail('user@clinic.hk'), isTrue);
    expect(isClinicInviteEmail('bob@x.test'), isTrue);
    expect(isClinicInviteEmail('not-an-email'), isFalse);
    expect(isClinicInviteEmail('shummh19@'), isFalse);
    expect(isClinicInviteEmail('a@b'), isFalse);
    expect(isClinicInviteEmail('a @b.com'), isFalse);
  });

  test('inviteStillOpen rejects accepted revoked and expired', () {
    final now = DateTime.utc(2026, 11, 14);
    expect(
      inviteStillOpen(
        now: now,
        expiresAt: now.add(const Duration(days: 1)),
        accepted: false,
        revoked: false,
      ),
      isTrue,
    );
    expect(
      inviteStillOpen(
        now: now,
        expiresAt: now.add(const Duration(days: 1)),
        accepted: true,
        revoked: false,
      ),
      isFalse,
    );
    expect(
      inviteStillOpen(
        now: now,
        expiresAt: now.subtract(const Duration(minutes: 1)),
        accepted: false,
        revoked: false,
      ),
      isFalse,
    );
  });

  test('owner role edits keep the last owner and block admins', () {
    final owner = _member('o1', const [OrgRole.owner, OrgRole.practitioner]);
    final second = _member('o2', const [OrgRole.owner]);
    final physio = _member('p1', const [OrgRole.practitioner]);
    final owners = [owner, second];

    expect(
      canSetMemberRoles(
        actor: const [OrgRole.admin],
        target: physio,
        nextRoles: const [OrgRole.owner],
        owners: 2,
      ),
      isFalse,
    );
    expect(
      canSetMemberRoles(
        actor: const [OrgRole.owner],
        target: physio,
        nextRoles: const [OrgRole.owner, OrgRole.practitioner],
        owners: 1,
      ),
      isTrue,
    );
    expect(
      canSetMemberRoles(
        actor: const [OrgRole.owner],
        target: owner,
        nextRoles: const [OrgRole.practitioner],
        owners: 1,
      ),
      isFalse,
    );
    expect(
      canSetMemberRoles(
        actor: const [OrgRole.owner],
        target: owner,
        nextRoles: const [OrgRole.practitioner],
        owners: activeOwnerCount(owners),
      ),
      isTrue,
    );
    expect(
      canRemoveMember(
        actor: const [OrgRole.admin],
        target: physio,
        owners: 1,
      ),
      isTrue,
    );
    expect(
      canRemoveMember(
        actor: const [OrgRole.admin],
        target: second,
        owners: 2,
      ),
      isFalse,
    );
    expect(
      canRemoveMember(
        actor: const [OrgRole.owner],
        target: owner,
        owners: 1,
      ),
      isFalse,
    );
    expect(
      canRemoveMember(
        actor: const [OrgRole.owner],
        target: second,
        owners: 2,
      ),
      isTrue,
    );
    expect(
      ownerUidsAfter(ownerUids: const ['o1'], uid: 'p1', isOwner: true),
      ['o1', 'p1'],
    );
    expect(
      ownerUidsAfter(ownerUids: const ['o1', 'o2'], uid: 'o2', isOwner: false),
      ['o1'],
    );
    expect(
      ownerUidsAfter(ownerUids: const ['o1'], uid: 'o1', isOwner: false),
      isEmpty,
    );
  });

  test('reassign follows the same overlap rule on the new practitioner', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureDefaults();

    final ada = await db.insertClient(firstName: 'Ada', lastName: 'Lovelace');
    final grace = await db.insertClient(firstName: 'Grace', lastName: 'Hopper');
    final moving = await db.insertAppointment(
      clientId: ada,
      practitionerUid: 'physio-a',
      startsAt: DateTime(2026, 10, 28, 9),
    );
    await db.insertAppointment(
      clientId: grace,
      practitionerUid: 'physio-b',
      startsAt: DateTime(2026, 10, 28, 9),
    );

    await expectLater(
      db.updateAppointment(
        id: moving,
        startsAt: DateTime(2026, 10, 28, 9),
        practitionerUid: 'physio-b',
      ),
      throwsA(isA<AppointmentConflictException>()),
    );
    expect((await db.getAppointment(moving))!.practitionerUid, 'physio-a');

    expect(
      await db.updateAppointment(
        id: moving,
        startsAt: DateTime(2026, 10, 28, 9),
        practitionerUid: 'physio-c',
      ),
      isTrue,
    );
    expect((await db.getAppointment(moving))!.practitionerUid, 'physio-c');

    // Same client still overlaps whoever is booked.
    final later = await db.insertAppointment(
      clientId: ada,
      practitionerUid: 'physio-a',
      startsAt: DateTime(2026, 10, 28, 15),
    );
    await expectLater(
      db.updateAppointment(
        id: later,
        startsAt: DateTime(2026, 10, 28, 9),
        practitionerUid: 'physio-d',
      ),
      throwsA(isA<AppointmentConflictException>()),
    );

    await db.insertAppointment(
      clientId: grace,
      practitionerUid: 'physio-e',
      startsAt: DateTime(2026, 10, 28, 16),
      status: AppointmentStatus.cancelled,
    );
    final ontoCancelled = await db.insertAppointment(
      clientId: grace,
      practitionerUid: 'physio-a',
      startsAt: DateTime(2026, 10, 28, 17),
    );
    expect(
      await db.updateAppointment(
        id: ontoCancelled,
        startsAt: DateTime(2026, 10, 28, 16),
        practitionerUid: 'physio-e',
      ),
      isTrue,
    );

    await db.insertAppointment(
      clientId: grace,
      practitionerUid: 'physio-f',
      startsAt: DateTime(2026, 10, 28, 12),
      endsAt: DateTime(2026, 10, 28, 13),
    );
    final backToBack = await db.insertAppointment(
      clientId: ada,
      practitionerUid: 'physio-a',
      startsAt: DateTime(2026, 10, 28, 18),
      endsAt: DateTime(2026, 10, 28, 19),
    );
    expect(
      await db.updateAppointment(
        id: backToBack,
        startsAt: DateTime(2026, 10, 28, 13),
        endsAt: DateTime(2026, 10, 28, 14),
        practitionerUid: 'physio-f',
      ),
      isTrue,
    );

    expect(mayReassignBooking(const [OrgRole.practitioner]), isFalse);
    expect(mayReassignBooking(const [OrgRole.admin]), isTrue);
    expect(
      isBookablePractitioner(
        _member('gone', const [OrgRole.practitioner], active: false),
      ),
      isFalse,
    );
  });
}
