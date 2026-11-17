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
| `GCAL_SUCCESS_URL` | `https://notesonly-e4829.web.app/?gcal=connected` | Desktop/web fallback after consent bridge |

**Google Console redirect URI does not change** for the mobile return fix.
The Function callback still exchanges the code, then serves an HTML bridge that
opens `notesonly://gcal/connected` (Android intent-filter) and falls back to
`GCAL_SUCCESS_URL` for desktop/web.

## Deploy order

```bash
# 1) Secrets first (above) — only on first setup
cd functions && npm ci && npm test && cd ..
# Mobile return-to-app fix: Functions only (Hosting optional; bridge no longer
# depends on Hosting for Android). No Google Console redirect URI change.
firebase deploy --only functions:googleCalendarOAuthCallback,functions:beginGoogleCalendarOAuth
# Or simply:
firebase deploy --only functions
```

Ship a new Android build (Custom Tabs launch mode + `notesonly://gcal` intent
filter). Until Functions are redeployed, consent still lands on Hosting only
and the app relies on the in-app poll / resume recovery alone.

## App behaviour

- **Connect** (Account settings): opens Google consent in a Chrome Custom Tab
  on Android (`LaunchMode.inAppBrowserView`; web still uses an external tab)
  with `access_type=offline` + `prompt=consent` → Function stores refresh
  token → bridge opens `notesonly://gcal/connected` → client polls status
  (and finishes on resume if status was `connecting`) → backfill + drain.
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

### Android return-to-app smoke

1. Install a build that includes the `notesonly://gcal` intent-filter.
2. Confirm Functions callback deploy is live (bridge page mentions
   “Open NotesOnly app”, not a bare Hosting redirect).
3. On the phone: More → enable Google Calendar sync.
4. Consent in the Custom Tab; after success you should land back in the app
   (or tap **Open NotesOnly app**).
5. Toggle subtitle shows **Connected** (not stuck on Connecting… / Needs
   permission). Local `sync_google_calendar_enabled` is on for that device.
6. Create an appointment on the phone → event appears on Google primary.
