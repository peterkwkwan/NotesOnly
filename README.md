# NotesOnly (pelvi_crm package)

SOAP-first Flutter CRM for solo physiotherapists. Android-first, local-first SQLite + Firebase Auth (Google). Hong Kong launch.

## Requirements

- [Flutter](https://docs.flutter.dev/get-started/install) stable (3.35+ recommended)
- Android SDK (for APK / device runs)
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

Release APK:

```bash
flutter build apk
```

## Firebase Auth (Google) — Peter checklist

`google-services.json` currently has an empty `oauth_client` list until a SHA fingerprint is registered. Sign-in will fail until you do this:

1. Get your **debug** SHA-1 (and SHA-256):

```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

2. Firebase Console → project **notesonly-e4829** → Project settings → Your apps → Android `com.notes.notes_only` → **Add fingerprint** → paste SHA-1 (and SHA-256).
3. Confirm **Authentication → Sign-in method → Google** is enabled.
4. Re-download `google-services.json` if `oauth_client` is still empty, replace `android/app/google-services.json`, rebuild.
5. **Web:** add a Web app in the same Firebase project, then run `flutterfire configure` (or paste web options into `lib/firebase_options.dart`). Web options are intentionally not set yet.
6. Later (Play): also add upload-key and Play App Signing SHA-1s the same way.

## Firestore sync

Offline-first: writes go to Drift first; when signed in, pending rows push to
`users/{uid}/clients|appointments|notes|settings/{id}` and pull by `updatedAt`.

**Peter (Firebase Console):**

1. Firestore → **Create database** (production mode) if not created yet.
2. Deploy rules from the repo: `firebase deploy --only firestore:rules`
   (or paste `firestore.rules` in Console → Rules → Publish).
3. Confirm Google Sign-In still works (SHA-1 on Android app).

## Project layout

```
lib/
  main.dart                 # Firebase init, DB, runApp
  firebase_options.dart     # Android options from google-services.json
  app.dart                  # Auth gate → first-run → shell
  theme/                    # PelviColors, spacing, ThemeData
  data/                     # Drift schema + auth + sync stub
  features/
    auth/                   # Sign in with Google
    shell/                  # bottom nav + center FAB + quick-add
    first_run/              # practitioner name
    today|calendar|clients|more/
    placeholders/           # stub destinations
  widgets/                  # empty states
```

## Design

Cream canvas `#FFFCFA`, dusty pink `#B63C70` primary, purple `#7B609F` secondary. Figma is visual SoT — see project design-system docs in the NotesOnly Cursor store.
