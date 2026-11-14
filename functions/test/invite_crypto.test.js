'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { mintInviteToken, hashInviteToken } = require('../invite_crypto');

describe('invite_crypto', () => {
  it('mints opaque token and matching sha256 hex id', () => {
    const { token, hash } = mintInviteToken();
    assert.equal(typeof token, 'string');
    assert.ok(token.length >= 40);
    assert.equal(hash, hashInviteToken(token));
    assert.match(hash, /^[a-f0-9]{64}$/);
  });

  it('does not put the raw token in the hash', () => {
    const { token, hash } = mintInviteToken();
    assert.equal(hash.includes(token), false);
  });
});
