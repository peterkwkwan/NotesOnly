'use strict';

const { describe, it, before } = require('node:test');
const assert = require('node:assert/strict');

before(() => {
  process.env.GCAL_TOKEN_KEY = Buffer.alloc(32, 7).toString('base64');
  process.env.GCAL_OAUTH_CLIENT_ID = 'test-client-id.apps.googleusercontent.com';
  process.env.GCAL_OAUTH_CLIENT_SECRET = 'test-secret';
});

const {
  encryptRefreshToken,
  decryptRefreshToken,
  buildAuthUrl,
  CALENDAR_SCOPE,
} = require('../gcal_oauth');

describe('gcal_oauth encrypt/decrypt', () => {
  it('round-trips a refresh token', () => {
    const plain = '1//refresh-token-sample';
    const cipher = encryptRefreshToken(plain);
    assert.notEqual(cipher, plain);
    assert.equal(decryptRefreshToken(cipher), plain);
  });

  it('produces different ciphertext each call (random IV)', () => {
    const a = encryptRefreshToken('same');
    const b = encryptRefreshToken('same');
    assert.notEqual(a, b);
  });
});

describe('gcal_oauth buildAuthUrl', () => {
  it('requests offline access + calendar.events + consent', () => {
    const url = buildAuthUrl({
      state: 'abc',
      loginHint: 'peter@example.com',
      forceConsent: true,
    });
    const u = new URL(url);
    assert.equal(u.origin + u.pathname, 'https://accounts.google.com/o/oauth2/v2/auth');
    assert.equal(u.searchParams.get('access_type'), 'offline');
    assert.equal(u.searchParams.get('prompt'), 'consent');
    assert.equal(u.searchParams.get('scope'), CALENDAR_SCOPE);
    assert.equal(u.searchParams.get('state'), 'abc');
    assert.equal(u.searchParams.get('login_hint'), 'peter@example.com');
    assert.equal(u.searchParams.get('response_type'), 'code');
  });
});
