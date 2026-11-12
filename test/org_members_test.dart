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
  test('clinic invites allow owner and admin but never owner role for admin', () {
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
