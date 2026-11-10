/// Clinic roles. One person may hold more than one (Owner + Practitioner).
enum OrgRole { owner, admin, practitioner }

const platformAdminEmail = 'peterkwkwan@gmail.com';

const inviteTtl = Duration(days: 14);

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
