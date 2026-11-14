import 'dart:math';

/// Clinic roles. One person may hold more than one (Owner + Practitioner).
enum OrgRole { owner, admin, practitioner }

const platformAdminEmail = 'peterkwkwan@gmail.com';

const inviteTtl = Duration(days: 14);

/// Invite doc ids: 6 chars, A–Z / 2–9 (no 0/O/1/I). Stored uppercase.
const inviteCodeLength = 6;
const inviteCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

String newInviteCode([Random? random]) {
  final r = random ?? Random.secure();
  final chars = List<String>.generate(
    inviteCodeLength,
    (_) => inviteCodeAlphabet[r.nextInt(inviteCodeAlphabet.length)],
  );
  return chars.join();
}

/// Trim + uppercase so accept is case-insensitive. Legacy UUID invites still match.
String normalizeInviteCode(String raw) => raw.trim().toUpperCase();

bool isPlatformAdminEmail(String? email) {
  return email?.trim().toLowerCase() == platformAdminEmail;
}

OrgRole? orgRoleFromName(String raw) {
  for (final role in OrgRole.values) {
    if (role.name == raw) return role;
  }
  return null;
}

List<OrgRole> parseOrgRoles(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  return [
    for (final part in raw.split(','))
      if (orgRoleFromName(part.trim()) != null) orgRoleFromName(part.trim())!,
  ];
}

String joinOrgRoles(Iterable<OrgRole> roles) =>
    roles.map((role) => role.name).join(',');

/// Owner, then admin, then practitioner. Drops duplicates.
List<OrgRole> normalizeOrgRoles(Iterable<OrgRole> roles) {
  return [
    for (final role in OrgRole.values)
      if (roles.contains(role)) role,
  ];
}

List<OrgRole> rolesFromRaw(Object? raw) {
  if (raw is String) return normalizeOrgRoles(parseOrgRoles(raw));
  if (raw is! List) return const [];
  final roles = <OrgRole>[];
  for (final item in raw) {
    final role = orgRoleFromName('$item');
    if (role != null) roles.add(role);
  }
  return normalizeOrgRoles(roles);
}

class OrgMember {
  const OrgMember({
    required this.uid,
    required this.email,
    required this.roles,
    required this.active,
  });

  final String uid;
  final String email;
  final List<OrgRole> roles;
  final bool active;
}

String memberLabel(OrgMember member) {
  final email = member.email.trim();
  return email.isEmpty ? member.uid : email;
}

String orgRoleLabel(OrgRole role) {
  return switch (role) {
    OrgRole.owner => 'Owner',
    OrgRole.admin => 'Admin',
    OrgRole.practitioner => 'Practitioner',
  };
}

int activeOwnerCount(Iterable<OrgMember> members) {
  var count = 0;
  for (final member in members) {
    if (member.active && member.roles.contains(OrgRole.owner)) count++;
  }
  return count;
}

bool mayReassignBooking(Iterable<OrgRole> actor) {
  return actor.contains(OrgRole.owner) || actor.contains(OrgRole.admin);
}

bool isBookablePractitioner(OrgMember member) {
  return member.active && member.roles.contains(OrgRole.practitioner);
}

/// Only an owner changes roles. The last owner cannot drop owner.
bool canSetMemberRoles({
  required List<OrgRole> actor,
  required OrgMember target,
  required List<OrgRole> nextRoles,
  required int owners,
}) {
  if (!target.active || !actor.contains(OrgRole.owner)) return false;
  final next = normalizeOrgRoles(nextRoles);
  if (next.isEmpty) return false;
  final dropsOwner = target.roles.contains(OrgRole.owner) &&
      !next.contains(OrgRole.owner);
  if (dropsOwner && owners <= 1) return false;
  return true;
}

/// Owner or admin may open Practice settings and send clinic invites.
bool canManagePracticeSettings(Iterable<OrgRole> actor) {
  return actor.contains(OrgRole.owner) || actor.contains(OrgRole.admin);
}

/// Owner or admin may send a clinic join invite from Practice settings.
bool canSendClinicInvite(Iterable<OrgRole> actor) {
  return canManagePracticeSettings(actor);
}

/// Roles the Members Send invite UI offers. Owner grants stay off this panel.
List<OrgRole> clinicInviteRolesFor(Iterable<OrgRole> actor) {
  if (!canSendClinicInvite(actor)) return const [];
  return const [OrgRole.practitioner, OrgRole.admin];
}

bool canInviteWithRole({
  required Iterable<OrgRole> actor,
  required OrgRole role,
}) {
  if (role == OrgRole.owner) return actor.contains(OrgRole.owner);
  if (role == OrgRole.admin || role == OrgRole.practitioner) {
    return canSendClinicInvite(actor);
  }
  return false;
}

/// Semicolon-separated Google emails for the Members invite dialog.
List<String> parseClinicInviteEmails(String raw) {
  final out = <String>[];
  for (final part in raw.split(';')) {
    final email = part.trim().toLowerCase();
    if (email.isEmpty) continue;
    out.add(email);
  }
  return out;
}

/// Practical invite shape: local@domain.tld — no spaces, domain has a dot.
/// Does not require a specific TLD (.hk, custom domains OK).
final _clinicInviteEmailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool isClinicInviteEmail(String email) =>
    _clinicInviteEmailRe.hasMatch(email.trim().toLowerCase());

class OrgInvite {
  const OrgInvite({
    required this.id,
    required this.email,
    required this.role,
    required this.expiresAt,
  });

  final String id;
  final String email;
  final OrgRole? role;
  final DateTime expiresAt;
}

/// Owner or admin may deactivate. Admin cannot revoke owner. Last owner stays.
bool canRemoveMember({
  required List<OrgRole> actor,
  required OrgMember target,
  required int owners,
}) {
  if (!target.active) return false;
  final isOwner = actor.contains(OrgRole.owner);
  final isAdmin = actor.contains(OrgRole.admin);
  if (!isOwner && !isAdmin) return false;
  if (target.roles.contains(OrgRole.owner)) {
    if (!isOwner || owners <= 1) return false;
  }
  return true;
}

/// Next `orgs.ownerUids` after [uid] gains or loses owner. Same list if unchanged.
List<String> ownerUidsAfter({
  required List<String> ownerUids,
  required String uid,
  required bool isOwner,
}) {
  final has = ownerUids.contains(uid);
  if (isOwner && has) return List<String>.from(ownerUids);
  if (!isOwner && !has) return List<String>.from(ownerUids);
  if (isOwner) return [...ownerUids, uid];
  return [
    for (final id in ownerUids)
      if (id != uid) id,
  ];
}

bool inviteStillOpen({
  required DateTime now,
  required DateTime expiresAt,
  required bool accepted,
  required bool revoked,
}) {
  return !accepted && !revoked && expiresAt.isAfter(now);
}

/// Peter's existing book becomes one org. Sign-in alone does not.
bool shouldMigrateLegacyBook({
  required String? email,
  required bool hasMembership,
  required bool hasClinical,
}) {
  return isPlatformAdminEmail(email) && !hasMembership && hasClinical;
}
