'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

const {
  hasOpenReplacementAmong,
  isOpenInviteDoc,
} = require('../invite_authz');

function doc(id, data) {
  return { id, data };
}

describe('isOpenInviteDoc', () => {
  const now = Date.parse('2026-11-14T12:00:00Z');

  it('rejects accepted revoked missing expiry and past expiry', () => {
    assert.equal(isOpenInviteDoc(null, { now }), false);
    assert.equal(
      isOpenInviteDoc(
        { expiresAt: new Date('2026-11-20'), acceptedAt: new Date() },
        { now },
      ),
      false,
    );
    assert.equal(
      isOpenInviteDoc(
        { expiresAt: new Date('2026-11-20'), revokedAt: new Date() },
        { now },
      ),
      false,
    );
    assert.equal(isOpenInviteDoc({ expiresAt: null }, { now }), false);
    assert.equal(
      isOpenInviteDoc({ expiresAt: new Date('2026-11-01') }, { now }),
      false,
    );
  });

  it('accepts open future invite', () => {
    assert.equal(
      isOpenInviteDoc({ expiresAt: new Date('2026-11-20') }, { now }),
      true,
    );
  });
});

describe('hasOpenReplacementAmong', () => {
  const now = Date.parse('2026-11-14T12:00:00Z');
  const open = {
    email: 'pmkwanshum@gmail.com',
    kind: 'join',
    orgId: 'org1',
    expiresAt: new Date('2026-11-28'),
    revokedAt: null,
    acceptedAt: null,
  };

  it('returns true when a newer open join invite exists for same email+org', () => {
    const docs = [
      doc('old-hash', { ...open, revokedAt: new Date() }),
      doc('new-hash', open),
    ];
    assert.equal(
      hasOpenReplacementAmong(docs, {
        email: 'pmkwanshum@gmail.com',
        kind: 'join',
        orgId: 'org1',
        excludeId: 'old-hash',
        now,
      }),
      true,
    );
  });

  it('returns false when only the revoked doc exists (true revoke)', () => {
    const docs = [doc('old-hash', { ...open, revokedAt: new Date() })];
    assert.equal(
      hasOpenReplacementAmong(docs, {
        email: 'pmkwanshum@gmail.com',
        kind: 'join',
        orgId: 'org1',
        excludeId: 'old-hash',
        now,
      }),
      false,
    );
  });

  it('ignores open invites for a different org', () => {
    const docs = [doc('other', { ...open, orgId: 'org2' })];
    assert.equal(
      hasOpenReplacementAmong(docs, {
        email: 'pmkwanshum@gmail.com',
        kind: 'join',
        orgId: 'org1',
        excludeId: 'old-hash',
        now,
      }),
      false,
    );
  });
});
