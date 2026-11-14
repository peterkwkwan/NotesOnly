'use strict';

const crypto = require('crypto');

/** Opaque invite token (URL-safe) + SHA-256 hex doc id. Never store the raw token. */
function mintInviteToken() {
  const token = crypto.randomBytes(32).toString('base64url');
  return { token, hash: hashInviteToken(token) };
}

function hashInviteToken(token) {
  return crypto.createHash('sha256').update(String(token), 'utf8').digest('hex');
}

module.exports = { mintInviteToken, hashInviteToken };
