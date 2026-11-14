# Magic-link clinic invites

Opaque hashed tokens + Resend email. **No 6-character invite codes.**

Web join URL: `https://notesonly-e4829.web.app/join?token=<opaque>`

## Callables (`us-central1`)

| Function | Role |
| --- | --- |
| `createClinicInvite` | Owner/Admin (or platform admin) → mint token, store SHA-256 doc id, email link |
| `resendClinicInvite` | Rotate token (revoke old) + email again |
| `acceptInvite` | Hash token → email match → membership (Admin SDK) |

Firestore never stores the raw token. Inviter may receive `joinUrl` once for clipboard.

## Secrets / env (Peter)

1. **Resend:** create account, verify a sending domain (or use `onboarding@resend.dev` for smoke tests only).
2. Set the Functions secret:

```bash
firebase functions:secrets:set RESEND_API_KEY
# paste the Resend API key when prompted
```

3. Optional runtime env (set in Console or `.env` for emulators):

| Name | Default | Purpose |
| --- | --- | --- |
| `INVITE_FROM_EMAIL` | `NotesOnly <onboarding@resend.dev>` | Resend `from` (must be allowed on your Resend domain) |
| `PUBLIC_WEB_URL` | `https://notesonly-e4829.web.app` | Base for `/join?token=` links |

## Deploy order

```bash
# 1) Functions (needs RESEND_API_KEY secret first)
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
2. Practice settings → Members → Send invite → confirm Resend delivery.
3. Open the link signed out → Google Sign-In with the **invited** account → auto-join.

## Android

Phase-2: App Links to the same HTTPS URL (or open in browser). Web is the primary path.
