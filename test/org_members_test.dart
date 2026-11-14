import 'dart:math';

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

  test('invite codes are 6 chars from the unambiguous alphabet', () {
    final code = newInviteCode(Random(1));
    expect(code.length, inviteCodeLength);
    expect(code, matches(RegExp('^[$inviteCodeAlphabet]{$inviteCodeLength}\$')));
    expect(normalizeInviteCode('  ab3k7f  '), 'AB3K7F');
    expect(inviteCodeAlphabet.contains('0'), isFalse);
    expect(inviteCodeAlphabet.contains('O'), isFalse);
    expect(inviteCodeAlphabet.contains('1'), isFalse);
    expect(inviteCodeAlphabet.contains('I'), isFalse);
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
