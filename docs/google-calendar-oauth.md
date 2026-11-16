# Google Calendar — long-lived refresh tokens

Backend OAuth (Cloud Functions). Refresh tokens live encrypted under
`users/{uid}/private/googleCalendar` (Admin SDK only). The Flutter client
mints short-lived access tokens via `getCalendarAccessToken` and keeps the
existing outbox → Calendar REST drain.

Related plan: project docs `google-calendar-refresh-token-plan.md`.

## Functions (`us-central1`)

| Export | Type | Role |
| --- | --- | --- |
| `beginGoogleCalendarOAuth` | callable | Mint state + return Google consent URL |
| `googleCalendarOAuthCallback` | HTTPS GET | Code exchange → store encrypted refresh token |
| `getCalendarAccessToken` | callable | Refresh → short-lived access token |
| `getGoogleCalendarStatus` | callable | `{ connected }` for post-consent polling |
| `disconnectGoogleCalendar` | callable | Revoke + delete stored refresh token |

Redirect URI (add exactly in Google Cloud Console):

```
https://us-central1-notesonly-e4829.cloudfunctions.net/googleCalendarOAuthCallback
```

After first deploy, confirm the live URL in Firebase Console → Functions. If
Gen2 shows a `*.run.app` URL instead, set that as the Console redirect URI and
optionally set runtime env `GCAL_REDIRECT_URI` to match.

## Google Cloud Console (`notesonly-e4829`) — Peter

1. **APIs** → enable **Google Calendar API** (if not already).
2. **OAuth consent screen** → scope  
   `https://www.googleapis.com/auth/calendar.events`  
   While **Testing**, add clinic emails under **Test users**.
3. **Credentials** → create **OAuth client ID** → type **Web application**  
   Name e.g. `NotesOnly Calendar offline`.  
   **Authorized redirect URIs** → the Function URL above.  
   (Keep the existing Firebase Web / Android clients for sign-in; this client is
   for Calendar offline only.)
4. Copy the new **Client ID** and **Client secret** (do not put them in Flutter).

## Secrets / env (Peter)

Generate a 32-byte AES key (base64):

```bash
openssl rand -base64 32
```

Set Secret Manager values (paste when prompted — do not commit):

```bash
firebase functions:secrets:set GCAL_OAUTH_CLIENT_ID
# paste Web client ID

firebase functions:secrets:set GCAL_OAUTH_CLIENT_SECRET
# paste Web client secret

firebase functions:secrets:set GCAL_TOKEN_KEY
# paste openssl output (32 bytes base64)
```

Optional runtime env:

| Name | Default | Purpose |
| --- | --- | --- |
| `GCAL_REDIRECT_URI` | `https://us-central1-notesonly-e4829.cloudfunctions.net/googleCalendarOAuthCallback` | Must match Console redirect URI |
| `GCAL_SUCCESS_URL` | `https://notesonly-e4829.web.app/?gcal=connected` | Post-consent browser redirect |

## Deploy order

```bash
# 1) Secrets first (above)
cd functions && npm ci && npm test && cd ..
firebase deploy --only functions
firebase deploy --only firestore:rules
```

## App behaviour

- **Connect** (Account settings): opens Google consent (`access_type=offline`,
  `prompt=consent`) → Function stores refresh token → client polls status →
  backfill + drain.
- **Drain**: client outbox; each tick calls `getCalendarAccessToken` (cached
  ~1h in memory) then Calendar REST.
- **Toggle off / Disconnect**: `disconnectGoogleCalendar` (revoke + delete).
  Does **not** delete Google events (v1).
- **Sign-out**: clears Firebase session only; server refresh token stays so
  reconnect on another device still works.

## Smoke (after secrets + deploy)

1. Sign in on web or Android as a consent **test user**.
2. Account settings → enable **Sync my appointments to Google Calendar**.
3. Complete Google consent in the browser tab.
4. Create an appointment → confirm event on calendar.google.com primary.
5. Hard-refresh the web app → create/edit another appointment without re-consent.
6. Toggle off → confirm Functions doc gone; events remain on Google.
