'use strict';

const PLATFORM_ADMIN_EMAIL = 'peterkwkwan@gmail.com';

function normalizeEmail(email) {
  return String(email || '')
    .trim()
    .toLowerCase();
}

function isPlatformAdmin(auth) {
  return normalizeEmail(auth?.token?.email) === PLATFORM_ADMIN_EMAIL;
}

function membershipId(orgId, uid) {
  return `${orgId}_${uid}`;
}

async function loadMembership(db, orgId, uid) {
  const snap = await db.collection('memberships').doc(membershipId(orgId, uid)).get();
  if (!snap.exists) return null;
  const data = snap.data();
  if (data.active !== true) return null;
  return data;
}

function hasRole(member, role) {
  const roles = member?.roles;
  return Array.isArray(roles) && roles.includes(role);
}

/**
 * Who may create which invite. Mirrors firestore.rules invite authz.
 */
async function assertCanCreateInvite(db, auth, { kind, orgId, role }) {
  if (!auth?.uid) {
    throw Object.assign(new Error('Sign in required'), { code: 'unauthenticated' });
  }
  const email = normalizeEmail(auth.token?.email);
  if (!email) {
    throw Object.assign(new Error('Google account has no email'), {
      code: 'failed-precondition',
    });
  }

  if (kind === 'create-org') {
    if (!isPlatformAdmin(auth)) {
      throw Object.assign(new Error('Only the platform admin can invite create-org'), {
        code: 'permission-denied',
      });
    }
    return { issuedByPlatformAdmin: true };
  }

  if (kind !== 'join') {
    throw Object.assign(new Error('Unknown invite kind'), { code: 'invalid-argument' });
  }
  if (!orgId || typeof orgId !== 'string') {
    throw Object.assign(new Error('orgId required for join invites'), {
      code: 'invalid-argument',
    });
  }
  if (!['owner', 'admin', 'practitioner'].includes(role)) {
    throw Object.assign(new Error('Invalid role'), { code: 'invalid-argument' });
  }

  if (isPlatformAdmin(auth)) {
    return { issuedByPlatformAdmin: true };
  }

  const member = await loadMembership(db, orgId, auth.uid);
  if (!member) {
    throw Object.assign(new Error('Not a member of this clinic'), {
      code: 'permission-denied',
    });
  }
  const owner = hasRole(member, 'owner');
  const admin = hasRole(member, 'admin');
  if (owner) {
    return { issuedByPlatformAdmin: false };
  }
  if (admin && (role === 'admin' || role === 'practitioner')) {
    return { issuedByPlatformAdmin: false };
  }
  throw Object.assign(new Error('You cannot invite with that role'), {
    code: 'permission-denied',
  });
}

async function assertCanResend(db, auth, invite) {
  if (!auth?.uid) {
    throw Object.assign(new Error('Sign in required'), { code: 'unauthenticated' });
  }
  if (invite.issuedByUid === auth.uid) return;
  if (isPlatformAdmin(auth)) return;
  if (invite.kind === 'join' && invite.orgId) {
    const member = await loadMembership(db, invite.orgId, auth.uid);
    if (member && (hasRole(member, 'owner') || hasRole(member, 'admin'))) {
      return;
    }
  }
  throw Object.assign(new Error('Cannot resend this invite'), {
    code: 'permission-denied',
  });
}

/** Soft rate limit: max creates+resends per uid in a rolling window. */
async function assertRateLimit(db, uid, { max = 20, windowMs = 60 * 60 * 1000 } = {}) {
  const { Timestamp } = require('firebase-admin/firestore');
  const since = Timestamp.fromDate(new Date(Date.now() - windowMs));
  const snap = await db
    .collection('invites')
    .where('issuedByUid', '==', uid)
    .where('createdAt', '>', since)
    .limit(max + 1)
    .get();
  if (snap.size > max) {
    throw Object.assign(new Error('Too many invites; try again later'), {
      code: 'resource-exhausted',
    });
  }
}

function inviteExpiresAtMs(data) {
  const raw = data?.expiresAt;
  if (!raw) return null;
  if (typeof raw.toDate === 'function') return raw.toDate().getTime();
  if (raw instanceof Date) return raw.getTime();
  if (typeof raw === 'number') return raw;
  return null;
}

/** True when invite can still be accepted (not accepted/revoked, not past expiry). */
function isOpenInviteDoc(data, { now = Date.now() } = {}) {
  if (!data || data.acceptedAt || data.revokedAt) return false;
  const expiresMs = inviteExpiresAtMs(data);
  return expiresMs != null && expiresMs > now;
}

/**
 * After rotate / revoke+re-invite, the old hash is revoked but a newer open
 * invite may exist for the same email (+ org for join). Pure scan over docs.
 */
function hasOpenReplacementAmong(
  docs,
  { email, kind, orgId = null, excludeId, now = Date.now() },
) {
  const wantEmail = normalizeEmail(email);
  for (const doc of docs) {
    if (!doc || doc.id === excludeId) continue;
    const data = typeof doc.data === 'function' ? doc.data() : doc.data;
    if (!data) continue;
    if (normalizeEmail(data.email) !== wantEmail) continue;
    if (data.kind !== kind) continue;
    if (kind === 'join' && (data.orgId || null) !== (orgId || null)) continue;
    if (isOpenInviteDoc(data, { now })) return true;
  }
  return false;
}

/**
 * Look up whether a newer open invite exists for this email (and org when join).
 * Single-field email query — no composite index required.
 */
async function hasOpenReplacementInvite(
  db,
  { email, kind, orgId = null, excludeId, now = Date.now() },
) {
  const snap = await db
    .collection('invites')
    .where('email', '==', normalizeEmail(email))
    .get();
  return hasOpenReplacementAmong(snap.docs, {
    email,
    kind,
    orgId,
    excludeId,
    now,
  });
}

module.exports = {
  PLATFORM_ADMIN_EMAIL,
  normalizeEmail,
  isPlatformAdmin,
  membershipId,
  loadMembership,
  assertCanCreateInvite,
  assertCanResend,
  assertRateLimit,
  isOpenInviteDoc,
  hasOpenReplacementAmong,
  hasOpenReplacementInvite,
};
