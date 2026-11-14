# Magic-link clinic invites

Opaque hashed tokens + Gmail SMTP email. **No 6-character invite codes.**

Web join URL: `https://notesonly-e4829.web.app/join?token=<opaque>`

## Callables (`us-central1`)

| Function | Role |
| --- | --- |
| `createClinicInvite` | Owner/Admin (or platform admin) → mint token, store SHA-256 doc id, email link |
| `resendClinicInvite` | Rotate token (revoke old) + email again |
| `acceptInvite` | Hash token → email match → membership (Admin SDK) |

Firestore never stores the raw token. Inviter may receive `joinUrl` once for clipboard.

## Secrets / env (Peter)

1. Use a Google account with [App Passwords](https://myaccount.google.com/apppasswords) enabled (2FA required).
2. Set the Functions secrets:

```bash
firebase functions:secrets:set GMAIL_USER
# paste: peterkwkwan@gmail.com

firebase functions:secrets:set GMAIL_APP_PASSWORD
# paste the 16-character Google App Password
```

3. Optional runtime env:

| Name | Default | Purpose |
| --- | --- | --- |
| `PUBLIC_WEB_URL` | `https://notesonly-e4829.web.app` | Base for `/join?token=` links |

From address is always `NotesOnly <GMAIL_USER>` (no separate From secret).

`RESEND_API_KEY` is no longer used — remove it from Secret Manager when convenient.

## Deploy order

```bash
# 1) Functions (needs GMAIL_USER + GMAIL_APP_PASSWORD first)
cd functions && npm ci && cd ..
firebase deploy --only functions

# 2) Rules + invite rate-limit index
firebase deploy --only firestore:rules,firestore:indexes

# 3) Hosting (Flutter web)
flutter pub get
flutter build web --release
firebase deploy --only hosting
```

## After deploy

1. Revoke any leftover open **6-character** Amber Health invites (Pending → Revoke), or let them expire — they cannot be accepted anymore.
2. Practice settings → Members → Send invite → confirm Gmail delivery.
3. Open the link signed out → Google Sign-In with the **invited** account → auto-join.

## Android

Phase-2: App Links to the same HTTPS URL (or open in browser). Web is the primary path.
