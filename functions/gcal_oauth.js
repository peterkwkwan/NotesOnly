'use strict';

const crypto = require('crypto');
const { HttpsError } = require('firebase-functions/v2/https');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');

const CALENDAR_SCOPE = 'https://www.googleapis.com/auth/calendar.events';
const STATE_TTL_MS = 10 * 60 * 1000;
const DEFAULT_REDIRECT_URI =
  'https://us-central1-notesonly-e4829.cloudfunctions.net/googleCalendarOAuthCallback';
const DEFAULT_SUCCESS_URL = 'https://notesonly-e4829.web.app/?gcal=connected';
/** Android App Link / custom scheme — intent-filter in AndroidManifest. */
const APP_RETURN_URL = 'notesonly://gcal/connected';
const APP_CANCEL_URL = 'notesonly://gcal/cancelled';

function redirectUri() {
  return process.env.GCAL_REDIRECT_URI || DEFAULT_REDIRECT_URI;
}

function successUrl() {
  return process.env.GCAL_SUCCESS_URL || DEFAULT_SUCCESS_URL;
}

/**
 * Post-consent bridge: open the Android app via custom scheme, then fall back
 * to Hosting for desktop/web. Google redirect URI stays the Function URL.
 */
function oauthReturnHtml({ title, heading, detail, appUrl, webUrl }) {
  const app = String(appUrl);
  const web = String(webUrl);
  const detailHtml = detail
    ? `<p>${String(detail).replace(/</g, '&lt;')}</p>`
    : '';
  return htmlPage(
    title,
    `<h1>${heading}</h1>
     ${detailHtml}
     <p>Returning to NotesOnly…</p>
     <p><a href="${app}">Open NotesOnly app</a></p>
     <p><a href="${web}">Continue in browser</a></p>
     <script>
       (function () {
         var app = ${JSON.stringify(app)};
         var web = ${JSON.stringify(web)};
         try { window.location.replace(app); } catch (e) {}
         setTimeout(function () {
           try { window.location.replace(web); } catch (e) {}
         }, 700);
       })();
     </script>`,
  );
}

function clientId() {
  const v = process.env.GCAL_OAUTH_CLIENT_ID;
  if (!v) throw new HttpsError('failed-precondition', 'GCAL_OAUTH_CLIENT_ID not set');
  return v;
}

function clientSecret() {
  const v = process.env.GCAL_OAUTH_CLIENT_SECRET;
  if (!v) throw new HttpsError('failed-precondition', 'GCAL_OAUTH_CLIENT_SECRET not set');
  return v;
}

function tokenKey() {
  const v = process.env.GCAL_TOKEN_KEY;
  if (!v) throw new HttpsError('failed-precondition', 'GCAL_TOKEN_KEY not set');
  const key = Buffer.from(v, 'base64');
  if (key.length !== 32) {
    throw new HttpsError(
      'failed-precondition',
      'GCAL_TOKEN_KEY must be 32 bytes, base64-encoded',
    );
  }
  return key;
}

/** AES-256-GCM: base64(iv || tag || ciphertext). */
function encryptRefreshToken(plain) {
  const key = tokenKey();
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const enc = Buffer.concat([cipher.update(String(plain), 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, tag, enc]).toString('base64');
}

function decryptRefreshToken(cipherB64) {
  const key = tokenKey();
  const buf = Buffer.from(String(cipherB64), 'base64');
  if (buf.length < 12 + 16 + 1) {
    throw new HttpsError('internal', 'Stored Calendar token is corrupt');
  }
  const iv = buf.subarray(0, 12);
  const tag = buf.subarray(12, 28);
  const data = buf.subarray(28);
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(data), decipher.final()]).toString('utf8');
}

function privateDoc(db, uid) {
  return db.collection('users').doc(uid).collection('private').doc('googleCalendar');
}

function stateDoc(db, state) {
  return db.collection('gcalOAuthStates').doc(state);
}

function normalizeEmail(email) {
  return String(email || '')
    .trim()
    .toLowerCase();
}

function buildAuthUrl({ state, loginHint, forceConsent }) {
  const params = new URLSearchParams({
    client_id: clientId(),
    redirect_uri: redirectUri(),
    response_type: 'code',
    scope: CALENDAR_SCOPE,
    access_type: 'offline',
    include_granted_scopes: 'true',
    state,
  });
  if (forceConsent) params.set('prompt', 'consent');
  if (loginHint) params.set('login_hint', loginHint);
  return `https://accounts.google.com/o/oauth2/v2/auth?${params.toString()}`;
}

async function exchangeCode(code) {
  const body = new URLSearchParams({
    code,
    client_id: clientId(),
    client_secret: clientSecret(),
    redirect_uri: redirectUri(),
    grant_type: 'authorization_code',
  });
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  const data = await res.json();
  if (!res.ok) {
    const err = new Error(data.error_description || data.error || 'token exchange failed');
    err.code = 'failed-precondition';
    throw err;
  }
  return data;
}

async function refreshAccessToken(refreshToken) {
  const body = new URLSearchParams({
    client_id: clientId(),
    client_secret: clientSecret(),
    refresh_token: refreshToken,
    grant_type: 'refresh_token',
  });
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  const data = await res.json();
  if (!res.ok) {
    const err = new Error(data.error_description || data.error || 'refresh failed');
    err.code = data.error === 'invalid_grant' ? 'failed-precondition' : 'internal';
    err.invalidGrant = data.error === 'invalid_grant';
    throw err;
  }
  return data;
}

async function fetchGoogleEmail(accessToken) {
  const res = await fetch('https://www.googleapis.com/oauth2/v2/userinfo', {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) return null;
  const data = await res.json();
  return normalizeEmail(data.email);
}

async function revokeToken(token) {
  if (!token) return;
  try {
    await fetch(`https://oauth2.googleapis.com/revoke?token=${encodeURIComponent(token)}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    });
  } catch (_) {
    // Best-effort.
  }
}

function htmlPage(title, body) {
  return `<!doctype html><html><head><meta charset="utf-8"><title>${title}</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>body{font-family:system-ui,sans-serif;max-width:28rem;margin:3rem auto;padding:0 1rem;line-height:1.4}
a{color:#b63c70}</style></head><body>${body}</body></html>`;
}

/**
 * Callable: mint OAuth state + return Google consent URL.
 * @returns {{ authUrl: string }}
 */
async function beginGoogleCalendarOAuth(db, auth) {
  const email = normalizeEmail(auth.token?.email);
  if (!email) {
    throw new HttpsError('failed-precondition', 'This Google account has no email');
  }
  const state = crypto.randomBytes(24).toString('base64url');
  const expiresAt = new Date(Date.now() + STATE_TTL_MS);
  await stateDoc(db, state).set({
    uid: auth.uid,
    email,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt: Timestamp.fromDate(expiresAt),
  });
  // Always consent on connect so Google issues a refresh_token.
  const authUrl = buildAuthUrl({
    state,
    loginHint: email,
    forceConsent: true,
  });
  return { authUrl };
}

/**
 * HTTPS GET callback from Google.
 */
async function handleOAuthCallback(db, req, res) {
  const q = req.query || {};
  if (q.error) {
    const webCancel = successUrl().replace('gcal=connected', 'gcal=cancelled');
    res
      .status(400)
      .send(
        oauthReturnHtml({
          title: 'Calendar connect failed',
          heading: 'Calendar connect cancelled',
          detail: String(q.error),
          appUrl: APP_CANCEL_URL,
          webUrl: webCancel,
        }),
      );
    return;
  }
  const code = String(q.code || '').trim();
  const state = String(q.state || '').trim();
  if (!code || !state) {
    res.status(400).send(htmlPage('Bad request', '<h1>Missing code or state</h1>'));
    return;
  }

  const ref = stateDoc(db, state);
  const snap = await ref.get();
  if (!snap.exists) {
    res
      .status(400)
      .send(htmlPage('Expired', '<h1>This connect link expired</h1><p>Try again from Account settings.</p>'));
    return;
  }
  const st = snap.data();
  const expires = st.expiresAt?.toDate?.() || null;
  if (!expires || expires.getTime() <= Date.now()) {
    await ref.delete().catch(() => {});
    res
      .status(400)
      .send(htmlPage('Expired', '<h1>This connect link expired</h1><p>Try again from Account settings.</p>'));
    return;
  }

  try {
    const tokens = await exchangeCode(code);
    if (!tokens.refresh_token) {
      res
        .status(400)
        .send(
          htmlPage(
            'No refresh token',
            `<h1>Google did not return a refresh token</h1>
             <p>Disconnect NotesOnly from your Google Account permissions, then try Connect again.</p>`,
          ),
        );
      await ref.delete().catch(() => {});
      return;
    }
    const googleEmail =
      (await fetchGoogleEmail(tokens.access_token)) || normalizeEmail(st.email);
    if (googleEmail && normalizeEmail(st.email) && googleEmail !== normalizeEmail(st.email)) {
      res
        .status(403)
        .send(
          htmlPage(
            'Wrong Google account',
            `<h1>Wrong Google account</h1>
             <p>Signed in to NotesOnly as <b>${st.email}</b> but granted Calendar as <b>${googleEmail}</b>.</p>`,
          ),
        );
      await ref.delete().catch(() => {});
      return;
    }

    await privateDoc(db, st.uid).set(
      {
        refreshTokenCipher: encryptRefreshToken(tokens.refresh_token),
        scope: CALENDAR_SCOPE,
        googleEmail: googleEmail || normalizeEmail(st.email),
        updatedAt: FieldValue.serverTimestamp(),
        connectedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await ref.delete().catch(() => {});
    // Bridge page (not a bare Hosting redirect) so Android returns to the app.
    res
      .status(200)
      .send(
        oauthReturnHtml({
          title: 'Calendar connected',
          heading: 'Google Calendar connected',
          appUrl: APP_RETURN_URL,
          webUrl: successUrl(),
        }),
      );
  } catch (err) {
    await ref.delete().catch(() => {});
    res
      .status(500)
      .send(
        htmlPage(
          'Connect failed',
          `<h1>Could not finish Calendar connect</h1><p>${String(err.message || err)}</p>`,
        ),
      );
  }
}

/**
 * Callable: short-lived access token from stored refresh token.
 */
async function getCalendarAccessToken(db, auth) {
  const ref = privateDoc(db, auth.uid);
  const snap = await ref.get();
  if (!snap.exists || !snap.data()?.refreshTokenCipher) {
    throw new HttpsError('failed-precondition', 'Google Calendar is not connected');
  }
  const data = snap.data();
  let refreshToken;
  try {
    refreshToken = decryptRefreshToken(data.refreshTokenCipher);
  } catch (err) {
    throw new HttpsError('internal', err.message || 'Decrypt failed');
  }

  let tokens;
  try {
    tokens = await refreshAccessToken(refreshToken);
  } catch (err) {
    if (err.invalidGrant) {
      await ref.delete().catch(() => {});
      throw new HttpsError(
        'failed-precondition',
        'Google Calendar permission was revoked — reconnect',
      );
    }
    throw new HttpsError(err.code || 'internal', err.message || 'Refresh failed');
  }

  if (tokens.refresh_token) {
    await ref.set(
      {
        refreshTokenCipher: encryptRefreshToken(tokens.refresh_token),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }

  return {
    accessToken: tokens.access_token,
    expiresIn: tokens.expires_in || 3600,
    googleEmail: data.googleEmail || null,
  };
}

/**
 * Callable: connection flag without minting.
 */
async function getGoogleCalendarStatus(db, auth) {
  const snap = await privateDoc(db, auth.uid).get();
  if (!snap.exists || !snap.data()?.refreshTokenCipher) {
    return { connected: false };
  }
  return {
    connected: true,
    googleEmail: snap.data().googleEmail || null,
  };
}

/**
 * Callable: revoke + delete stored refresh token.
 */
async function disconnectGoogleCalendar(db, auth) {
  const ref = privateDoc(db, auth.uid);
  const snap = await ref.get();
  if (snap.exists && snap.data()?.refreshTokenCipher) {
    try {
      const refreshToken = decryptRefreshToken(snap.data().refreshTokenCipher);
      await revokeToken(refreshToken);
    } catch (_) {
      // Still delete local copy.
    }
  }
  await ref.delete().catch(() => {});
  return { ok: true };
}

module.exports = {
  CALENDAR_SCOPE,
  APP_RETURN_URL,
  encryptRefreshToken,
  decryptRefreshToken,
  buildAuthUrl,
  beginGoogleCalendarOAuth,
  handleOAuthCallback,
  getCalendarAccessToken,
  getGoogleCalendarStatus,
  disconnectGoogleCalendar,
  // test hooks
  _internals: {
    redirectUri,
    successUrl,
    normalizeEmail,
    oauthReturnHtml,
    APP_RETURN_URL,
    APP_CANCEL_URL,
  },
};
