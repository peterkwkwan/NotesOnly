'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');

const { mintInviteToken, hashInviteToken } = require('./invite_crypto');
const {
  INVITE_TTL_DAYS,
  joinUrlForToken,
  sendInviteEmail,
} = require('./invite_mail');
const {
  normalizeEmail,
  membershipId,
  assertCanCreateInvite,
  assertCanResend,
  assertRateLimit,
} = require('./invite_authz');

initializeApp();
const db = getFirestore();

const gmailUser = defineSecret('GMAIL_USER');
const gmailAppPassword = defineSecret('GMAIL_APP_PASSWORD');

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

function httpsError(err) {
  if (err instanceof HttpsError) return err;
  const code = err.code || 'internal';
  const map = {
    unauthenticated: 'unauthenticated',
    'permission-denied': 'permission-denied',
    'invalid-argument': 'invalid-argument',
    'failed-precondition': 'failed-precondition',
    'resource-exhausted': 'resource-exhausted',
    'not-found': 'not-found',
  };
  return new HttpsError(map[code] || 'internal', err.message || 'Error');
}

function requireAuth(request) {
  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'Sign in required');
  }
  return request.auth;
}

async function clinicNameFor(orgId) {
  if (!orgId) return null;
  const snap = await db.collection('orgs').doc(orgId).get();
  return snap.exists ? snap.data().name || null : null;
}

async function writeInviteDoc({
  hash,
  kind,
  email,
  role,
  orgId,
  issuedByUid,
  issuedByPlatformAdmin,
  expiresAt,
}) {
  const ref = db.collection('invites').doc(hash);
  await ref.set({
    kind,
    email,
    role: kind === 'join' ? role : null,
    orgId: kind === 'join' ? orgId : null,
    issuedByUid,
    issuedByPlatformAdmin,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt: Timestamp.fromDate(expiresAt),
    revokedAt: null,
    acceptedAt: null,
    acceptedByUid: null,
    lastEmailedAt: null,
    emailDeliveryStatus: 'queued',
  });
  return ref;
}

async function markEmailStatus(ref, status) {
  await ref.update({
    emailDeliveryStatus: status,
    lastEmailedAt: FieldValue.serverTimestamp(),
  });
}

async function createAndEmailInvite({
  auth,
  email,
  kind,
  orgId,
  role,
}) {
  const normalized = normalizeEmail(email);
  if (!EMAIL_RE.test(normalized)) {
    throw new HttpsError('invalid-argument', `Invalid email: ${email}`);
  }

  const { issuedByPlatformAdmin } = await assertCanCreateInvite(db, auth, {
    kind,
    orgId,
    role,
  });
  await assertRateLimit(db, auth.uid);

  const { token, hash } = mintInviteToken();
  const expiresAt = new Date(Date.now() + INVITE_TTL_DAYS * 24 * 60 * 60 * 1000);
  const ref = await writeInviteDoc({
    hash,
    kind,
    email: normalized,
    role: kind === 'join' ? role : null,
    orgId: kind === 'join' ? orgId : null,
    issuedByUid: auth.uid,
    issuedByPlatformAdmin,
    expiresAt,
  });

  const joinUrl = joinUrlForToken(token);
  const clinicName =
    kind === 'join' ? await clinicNameFor(orgId) : 'NotesOnly (create clinic)';
  const mailed = await sendInviteEmail({
    to: normalized,
    clinicName,
    role: kind === 'join' ? role : null,
    joinUrl,
    expiresAt,
  });
  await markEmailStatus(ref, mailed.status);

  return {
    inviteId: hash,
    joinUrl,
    emailed: mailed.ok,
    emailDeliveryStatus: mailed.status,
    emailError: mailed.error || null,
  };
}

exports.createClinicInvite = onCall(
  { secrets: [gmailUser, gmailAppPassword], region: 'us-central1' },
  async (request) => {
    try {
      // Secrets are injected into process.env by Functions runtime.
      if (gmailUser.value()) process.env.GMAIL_USER = gmailUser.value();
      if (gmailAppPassword.value()) {
        process.env.GMAIL_APP_PASSWORD = gmailAppPassword.value();
      }
      const auth = requireAuth(request);
      const data = request.data || {};
      const kind = data.kind === 'create-org' ? 'create-org' : 'join';
      return await createAndEmailInvite({
        auth,
        email: data.email,
        kind,
        orgId: data.orgId || null,
        role: data.role || null,
      });
    } catch (err) {
      throw httpsError(err);
    }
  },
);

exports.resendClinicInvite = onCall(
  { secrets: [gmailUser, gmailAppPassword], region: 'us-central1' },
  async (request) => {
    try {
      if (gmailUser.value()) process.env.GMAIL_USER = gmailUser.value();
      if (gmailAppPassword.value()) {
        process.env.GMAIL_APP_PASSWORD = gmailAppPassword.value();
      }
      const auth = requireAuth(request);
      const inviteId = String(request.data?.inviteId || '').trim();
      if (!inviteId) {
        throw new HttpsError('invalid-argument', 'inviteId required');
      }
      const oldRef = db.collection('invites').doc(inviteId);
      const oldSnap = await oldRef.get();
      if (!oldSnap.exists) {
        throw new HttpsError('not-found', 'Invite not found');
      }
      const old = oldSnap.data();
      await assertCanResend(db, auth, old);
      if (old.acceptedAt || old.revokedAt) {
        throw new HttpsError('failed-precondition', 'Invite is no longer open');
      }
      const expires = old.expiresAt?.toDate?.() || null;
      if (!expires || expires.getTime() <= Date.now()) {
        throw new HttpsError('failed-precondition', 'Invite has expired');
      }

      // Rotate: revoke previous open invite, mint a fresh token.
      await oldRef.update({ revokedAt: FieldValue.serverTimestamp() });

      return await createAndEmailInvite({
        auth,
        email: old.email,
        kind: old.kind,
        orgId: old.orgId,
        role: old.role,
      });
    } catch (err) {
      throw httpsError(err);
    }
  },
);

exports.acceptInvite = onCall({ region: 'us-central1' }, async (request) => {
  try {
    const auth = requireAuth(request);
    const email = normalizeEmail(auth.token?.email);
    if (!email) {
      throw new HttpsError('failed-precondition', 'This Google account has no email');
    }
    const token = String(request.data?.token || '').trim();
    if (!token) {
      throw new HttpsError('invalid-argument', 'token required');
    }
    // No legacy 6-char path — hash only.
    const hash = hashInviteToken(token);
    const ref = db.collection('invites').doc(hash);
    const clinicName = String(request.data?.clinicName || '').trim();

    const result = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) {
        throw new HttpsError('not-found', 'Invite not found');
      }
      const invite = snap.data();
      if (normalizeEmail(invite.email) !== email) {
        throw new HttpsError(
          'permission-denied',
          'This invite is for a different Google account. Sign in with the invited email.',
        );
      }
      if (invite.acceptedAt) {
        throw new HttpsError('failed-precondition', 'This invite was already used');
      }
      if (invite.revokedAt) {
        throw new HttpsError('failed-precondition', 'This invite was revoked');
      }
      const expires = invite.expiresAt?.toDate?.() || null;
      if (!expires || expires.getTime() <= Date.now()) {
        throw new HttpsError('failed-precondition', 'This invite has expired');
      }

      if (invite.kind === 'create-org') {
        if (!clinicName) {
          throw new HttpsError('invalid-argument', 'Name the clinic');
        }
        const orgRef = db.collection('orgs').doc();
        const memberRef = db
          .collection('memberships')
          .doc(membershipId(orgRef.id, auth.uid));
        tx.set(orgRef, {
          name: clinicName,
          createdByUid: auth.uid,
          ownerUids: [auth.uid],
          migratedFromUser: false,
          inviteId: ref.id,
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        tx.set(memberRef, {
          orgId: orgRef.id,
          uid: auth.uid,
          email,
          roles: ['owner', 'practitioner'],
          active: true,
          inviteId: ref.id,
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        tx.update(ref, {
          acceptedAt: FieldValue.serverTimestamp(),
          acceptedByUid: auth.uid,
        });
        return { orgId: orgRef.id, roles: ['owner', 'practitioner'] };
      }

      if (invite.kind === 'join') {
        const orgId = invite.orgId;
        const role = invite.role;
        if (!orgId || !role) {
          throw new HttpsError('failed-precondition', 'Invite is missing clinic or role');
        }
        const memberRef = db.collection('memberships').doc(membershipId(orgId, auth.uid));
        const existing = await tx.get(memberRef);
        if (existing.exists && existing.data().active === true) {
          // Already a member — still consume invite.
          tx.update(ref, {
            acceptedAt: FieldValue.serverTimestamp(),
            acceptedByUid: auth.uid,
          });
          return {
            orgId,
            roles: existing.data().roles || [role],
          };
        }
        tx.set(memberRef, {
          orgId,
          uid: auth.uid,
          email,
          roles: [role],
          active: true,
          inviteId: ref.id,
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        tx.update(ref, {
          acceptedAt: FieldValue.serverTimestamp(),
          acceptedByUid: auth.uid,
        });
        return { orgId, roles: [role] };
      }

      throw new HttpsError('failed-precondition', 'Unknown invite');
    });

    return result;
  } catch (err) {
    throw httpsError(err);
  }
});
