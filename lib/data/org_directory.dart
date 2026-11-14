import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'org.dart';

/// Firestore orgs / memberships / invite list+revoke.
/// Create, accept, and resend go through HTTPS callables (hashed magic links).
class OrgDirectory {
  OrgDirectory({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore,
        _functions = functions;

  final FirebaseFirestore? _firestore;
  final FirebaseFunctions? _functions;

  FirebaseFirestore get _fs => _firestore ?? FirebaseFirestore.instance;
  FirebaseFunctions get _fn =>
      _functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  static String membershipId(String orgId, String uid) => '${orgId}_$uid';

  /// Creates invite + emails magic link. Returns hash id and join URL.
  Future<ClinicInviteResult> createClinicInvite({
    required String email,
    required String kind,
    String? orgId,
    String? role,
  }) async {
    final callable = _fn.httpsCallable('createClinicInvite');
    final result = await callable.call(<String, dynamic>{
      'email': email.trim().toLowerCase(),
      'kind': kind,
      if (orgId != null) 'orgId': orgId,
      if (role != null) 'role': role,
    });
    return ClinicInviteResult.fromMap(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  Future<ClinicInviteResult> resendClinicInvite({
    required String inviteId,
  }) async {
    final callable = _fn.httpsCallable('resendClinicInvite');
    final result = await callable.call(<String, dynamic>{
      'inviteId': inviteId,
    });
    return ClinicInviteResult.fromMap(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  /// Accept via opaque token from `/join?token=`. Returns org id + roles.
  Future<AcceptedInvite> acceptInviteToken({
    required String token,
    String? clinicName,
  }) async {
    final callable = _fn.httpsCallable('acceptInvite');
    final result = await callable.call(<String, dynamic>{
      'token': token.trim(),
      if (clinicName != null && clinicName.trim().isNotEmpty)
        'clinicName': clinicName.trim(),
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final orgId = data['orgId'] as String? ?? '';
    final rolesRaw = data['roles'];
    final roles = <String>[
      if (rolesRaw is List)
        for (final r in rolesRaw) '$r',
    ];
    if (orgId.isEmpty) throw StateError('Accept returned no clinic');
    return AcceptedInvite(orgId: orgId, roles: roles);
  }

  Future<void> revokeInvite({
    required String inviteId,
  }) async {
    await _fs.collection('invites').doc(inviteId.trim()).update({
      'revokedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Open join invites for this clinic. Callers must be owner or admin.
  Future<List<OrgInvite>> listPendingInvites(String orgId) async {
    final snap =
        await _fs.collection('invites').where('orgId', isEqualTo: orgId).get();
    final now = DateTime.now().toUtc();
    final pending = <OrgInvite>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['kind'] != 'join') continue;
      final expires = _time(data['expiresAt']);
      if (expires == null) continue;
      if (!inviteStillOpen(
        now: now,
        expiresAt: expires,
        accepted: data['acceptedAt'] != null,
        revoked: data['revokedAt'] != null,
      )) {
        continue;
      }
      pending.add(OrgInvite(
        id: doc.id,
        email: data['email'] as String? ?? '',
        role: orgRoleFromName('${data['role'] ?? ''}'),
        expiresAt: expires,
        emailDeliveryStatus: data['emailDeliveryStatus'] as String?,
      ));
    }
    pending.sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
    return pending;
  }

  Future<List<OrgMember>> listMembers(String orgId) async {
    final snap = await _fs
        .collection('memberships')
        .where('orgId', isEqualTo: orgId)
        .get();
    final members = [
      for (final doc in snap.docs)
        OrgMember(
          uid: doc.data()['uid'] as String? ?? '',
          email: doc.data()['email'] as String? ?? '',
          roles: rolesFromRaw(doc.data()['roles']),
          active: doc.data()['active'] == true,
        ),
    ];
    members.sort((a, b) {
      int rank(OrgMember member) {
        if (!member.active) return 2;
        if (member.roles.contains(OrgRole.owner)) return 0;
        return 1;
      }

      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      return memberLabel(a).toLowerCase().compareTo(memberLabel(b).toLowerCase());
    });
    return members;
  }

  /// Owner path. Keeps `ownerUids` aligned with who still has the owner role.
  Future<void> setMemberRoles({
    required String orgId,
    required String uid,
    required List<OrgRole> roles,
  }) async {
    final next = normalizeOrgRoles(roles);
    if (next.isEmpty) throw StateError('Choose a role');
    final memberRef =
        _fs.collection('memberships').doc(membershipId(orgId, uid));
    final orgRef = _fs.collection('orgs').doc(orgId);
    await _fs.runTransaction((tx) async {
      final orgSnap = await tx.get(orgRef);
      final memberSnap = await tx.get(memberRef);
      if (!orgSnap.exists || !memberSnap.exists) {
        throw StateError('Member not found');
      }
      final data = memberSnap.data()!;
      if (data['active'] != true) {
        throw StateError('Removed members stay removed');
      }
      final current = rolesFromRaw(data['roles']);
      final owners = _ownerUids(orgSnap.data());
      final aligned = ownerUidsAfter(
        ownerUids: owners,
        uid: uid,
        isOwner: next.contains(OrgRole.owner),
      );
      if (aligned.isEmpty) {
        throw StateError('The last owner stays an owner');
      }
      final rolesSame = joinOrgRoles(current) == joinOrgRoles(next);
      final ownersSame = _idsEqual(owners, aligned);
      if (rolesSame && ownersSame) return;
      if (!ownersSame) {
        tx.update(orgRef, {
          'ownerUids': aligned,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (!rolesSame) {
        tx.update(memberRef, {
          'roles': [for (final role in next) role.name],
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  /// Sets active false. An owner who is not the last is dropped from ownerUids.
  Future<void> deactivateMember({
    required String orgId,
    required String uid,
  }) async {
    final memberRef =
        _fs.collection('memberships').doc(membershipId(orgId, uid));
    final orgRef = _fs.collection('orgs').doc(orgId);
    await _fs.runTransaction((tx) async {
      final orgSnap = await tx.get(orgRef);
      final memberSnap = await tx.get(memberRef);
      if (!memberSnap.exists) throw StateError('Member not found');
      final data = memberSnap.data()!;
      if (data['active'] != true) return;
      final current = rolesFromRaw(data['roles']);
      final owners = _ownerUids(orgSnap.data());
      final holdsOwner =
          current.contains(OrgRole.owner) || owners.contains(uid);
      final nextOwners = ownerUidsAfter(
        ownerUids: owners,
        uid: uid,
        isOwner: false,
      );
      if (holdsOwner && nextOwners.isEmpty) {
        throw StateError('The last owner stays on the clinic');
      }
      if (holdsOwner) {
        final nextRoles = [
          for (final role in current)
            if (role != OrgRole.owner) role.name,
        ];
        tx.update(orgRef, {
          'ownerUids': nextOwners,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.update(memberRef, {
          'roles': nextRoles,
          'active': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }
      tx.update(memberRef, {
        'active': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// One org for Peter's existing book. Not used for an empty sign-in.
  Future<String> createMigratedOrg({
    required User user,
    required String name,
  }) async {
    final email = user.email?.trim().toLowerCase() ?? '';
    final orgRef = _fs.collection('orgs').doc();
    final memberRef =
        _fs.collection('memberships').doc(membershipId(orgRef.id, user.uid));
    await _fs.runTransaction((tx) async {
      tx.set(orgRef, {
        'name': name,
        'createdByUid': user.uid,
        'ownerUids': [user.uid],
        'migratedFromUser': true,
        'inviteId': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(memberRef, {
        'orgId': orgRef.id,
        'uid': user.uid,
        'email': email,
        'roles': const ['owner', 'practitioner'],
        'active': true,
        'inviteId': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    return orgRef.id;
  }

  List<String> _ownerUids(Map<String, dynamic>? data) {
    final raw = data?['ownerUids'];
    if (raw is! List) return const [];
    return [for (final id in raw) id.toString()];
  }

  bool _idsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static DateTime? _time(Object? raw) {
    if (raw is Timestamp) return raw.toDate().toUtc();
    if (raw is DateTime) return raw.toUtc();
    return null;
  }
}

class ClinicInviteResult {
  const ClinicInviteResult({
    required this.inviteId,
    required this.joinUrl,
    required this.emailed,
    this.emailDeliveryStatus,
  });

  final String inviteId;
  final String joinUrl;
  final bool emailed;
  final String? emailDeliveryStatus;

  factory ClinicInviteResult.fromMap(Map<String, dynamic> data) {
    return ClinicInviteResult(
      inviteId: '${data['inviteId'] ?? ''}',
      joinUrl: '${data['joinUrl'] ?? ''}',
      emailed: data['emailed'] == true,
      emailDeliveryStatus: data['emailDeliveryStatus'] as String?,
    );
  }
}

class AcceptedInvite {
  const AcceptedInvite({required this.orgId, required this.roles});

  final String orgId;
  final List<String> roles;
}
