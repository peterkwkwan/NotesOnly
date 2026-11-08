# NotesOnly (pelvi_crm package)

SOAP-first Flutter CRM for solo physiotherapists. Android-first, local-first SQLite + Firebase Auth (Google). Hong Kong launch. Web uses the same Drift schema + Firestore sync (sqlite3 wasm, not IndexedDB-primary).

## Requirements

- [Flutter](https://docs.flutter.dev/get-started/install) stable (3.35+ recommended)
- Android SDK (for APK / device runs)
- Chrome (for web)
- Firebase project `notesonly-e4829` (Android app `com.notes.notes_only`)

## Run

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generates Drift code
flutter run
```

Android device / emulator:

```bash
flutter run -d android
```

Web (Chrome):

```bash
flutter run -d chrome --web-hostname localhost --web-port 7357
```

Release APK:

```bash
flutter build apk
```

## Firebase Auth (Google) — Peter checklist

1. Get your **debug** SHA-1 (and SHA-256):

```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

2. Firebase Console → project **notesonly-e4829** → Project settings → Your apps → Android `com.notes.notes_only` → **Add fingerprint** → paste SHA-1 (and SHA-256).
3. Confirm **Authentication → Sign-in method → Google** is enabled.
4. Re-download `google-services.json` if `oauth_client` is empty, replace `android/app/google-services.json`, rebuild.
5. **Web app:** Project settings → Add app → **Web**. Copy the `appId` into `lib/firebase_options.dart` (`DefaultFirebaseOptions.web.appId`), or run `flutterfire configure`.
6. **Authorized domains** (Authentication → Settings): keep `localhost`, `notesonly-e4829.web.app`, `notesonly-e4829.firebaseapp.com` (already typical defaults). Add any custom domain after you attach one.
7. Later (Play): also add upload-key and Play App Signing SHA-1s the same way.

## Firestore sync

Offline-first: writes go to Drift first; when signed in, pending rows push to
`users/{uid}/clients|appointments|notes|settings/{id}` and pull by `updatedAt`.
Same engine on Android and web.

**Peter (Firebase Console):**

1. Firestore → **Create database** (production mode) if not created yet.
2. Deploy rules from the repo: `firebase deploy --only firestore:rules`
   (or paste `firestore.rules` in Console → Rules → Publish).
3. Confirm Google Sign-In still works (SHA-1 on Android app).

## Web Hosting deploy

```bash
flutter build web --release
firebase deploy --only hosting
# or both: firebase deploy --only firestore:rules,hosting
```

Requires Firebase CLI logged in as a project owner (`firebase login`). Public dir is `build/web` (see `firebase.json`). After first deploy, open `https://notesonly-e4829.web.app` and confirm it is listed under Auth authorized domains.

## Project layout

```
lib/
  main.dart                 # Firebase init, DB, runApp
  firebase_options.dart     # Android + web options (notesonly-e4829)
  app.dart                  # Auth gate → first-run → shell
  theme/                    # PelviColors, spacing, ThemeData
  data/                     # Drift schema + auth + Firestore sync
  features/
    auth/                   # Sign in with Google
    shell/                  # bottom nav + center FAB + quick-add
    first_run/              # practitioner name
    today|calendar|clients|more/
    placeholders/           # stub destinations
  widgets/                  # empty states
web/
  sqlite3.wasm              # Drift web (sqlite3 2.9.4)
  drift_worker.js           # Drift web worker (drift 2.31.0)
```

## Design

Cream canvas `#FFFCFA`, dusty pink `#B63C70` primary, purple `#7B609F` secondary. Figma is visual SoT — see project design-system docs in the NotesOnly Cursor store.
