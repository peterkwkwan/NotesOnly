import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'org.dart';
import 'remote_id.dart';

/// Firestore orgs, memberships, and invites. Clinical rows stay on the org.
class OrgDirectory {
  OrgDirectory({FirebaseFirestore? firestore}) : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get _fs => _firestore ?? FirebaseFirestore.instance;

  static String membershipId(String orgId, String uid) => '${orgId}_$uid';

  Future<String> createInvite({
    required User user,
    required String email,
    required String kind,
    String? orgId,
    String? role,
    required bool issuedByPlatformAdmin,
  }) async {
    final id = newRemoteId();
    final normalized = email.trim().toLowerCase();
    await _fs.collection('invites').doc(id).set({
      'kind': kind,
      'email': normalized,
      'role': kind == 'join' ? role : null,
      'orgId': kind == 'join' ? orgId : null,
      'issuedByUid': user.uid,
      'issuedByPlatformAdmin': issuedByPlatformAdmin,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(DateTime.now().toUtc().add(inviteTtl)),
      'revokedAt': null,
      'acceptedAt': null,
      'acceptedByUid': null,
    });
    return id;
  }

  Future<void> revokeInvite({
    required String inviteId,
  }) async {
    await _fs.collection('invites').doc(inviteId.trim()).update({
      'revokedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, dynamic>> peekInvite(String inviteId) async {
    final snap = await _fs.collection('invites').doc(inviteId.trim()).get();
    if (!snap.exists) {
      throw StateError('Invite not found');
    }
    return snap.data()!;
  }

  /// Returns the org id the account now belongs to.
  Future<String> acceptInvite({
    required User user,
    required String inviteId,
    String? clinicName,
  }) async {
    final email = user.email?.trim().toLowerCase() ?? '';
    if (email.isEmpty) {
      throw StateError('This Google account has no email');
    }
    final ref = _fs.collection('invites').doc(inviteId.trim());
    final peeked = await ref.get();
    if (!peeked.exists) throw StateError('Invite not found');
    final preview = peeked.data()!;
    if (preview['email'] != email) {
      throw StateError('This invite is for a different Google account');
    }
    final expires = _time(preview['expiresAt']);
    if (expires == null ||
        !inviteStillOpen(
          now: DateTime.now().toUtc(),
          expiresAt: expires,
          accepted: preview['acceptedAt'] != null,
          revoked: preview['revokedAt'] != null,
        )) {
      throw StateError('This invite is no longer valid');
    }

    final kind = preview['kind'] as String?;
    if (kind == 'create-org') {
      final name = clinicName?.trim() ?? '';
      if (name.isEmpty) throw StateError('Name the clinic');
      final orgRef = _fs.collection('orgs').doc();
      final memberRef = _fs
          .collection('memberships')
          .doc(membershipId(orgRef.id, user.uid));
      await _fs.runTransaction((tx) async {
        tx.set(orgRef, {
          'name': name,
          'createdByUid': user.uid,
          'ownerUids': [user.uid],
          'migratedFromUser': false,
          'inviteId': ref.id,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(memberRef, _member(
          orgId: orgRef.id,
          user: user,
          email: email,
          roles: const ['owner', 'practitioner'],
          inviteId: ref.id,
        ));
        tx.update(ref, {
          'acceptedAt': FieldValue.serverTimestamp(),
          'acceptedByUid': user.uid,
        });
      });
      return orgRef.id;
    }

    if (kind == 'join') {
      final orgId = preview['orgId'] as String?;
      final role = preview['role'] as String?;
      if (orgId == null || role == null) {
        throw StateError('This invite is missing a clinic or role');
      }
      final memberRef =
          _fs.collection('memberships').doc(membershipId(orgId, user.uid));
      await _fs.runTransaction((tx) async {
        tx.set(memberRef, _member(
          orgId: orgId,
          user: user,
          email: email,
          roles: [role],
          inviteId: ref.id,
        ));
        tx.update(ref, {
          'acceptedAt': FieldValue.serverTimestamp(),
          'acceptedByUid': user.uid,
        });
      });
      return orgId;
    }

    throw StateError('Unknown invite');
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
      tx.set(memberRef, _member(
        orgId: orgRef.id,
        user: user,
        email: email,
        roles: const ['owner', 'practitioner'],
        inviteId: null,
      ));
    });
    return orgRef.id;
  }

  Map<String, Object?> _member({
    required String orgId,
    required User user,
    required String email,
    required List<String> roles,
    required String? inviteId,
  }) {
    return {
      'orgId': orgId,
      'uid': user.uid,
      'email': email,
      'roles': roles,
      'active': true,
      'inviteId': inviteId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static DateTime? _time(Object? raw) {
    if (raw is Timestamp) return raw.toDate().toUtc();
    if (raw is DateTime) return raw.toUtc();
    return null;
  }
}
