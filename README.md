# Pelvi CRM

SOAP-first Flutter CRM for solo physiotherapists. Android-first, local-first SQLite, Hong Kong launch.

This repo currently contains the **first scaffolding slice**: design tokens, app shell (Today · Calendar · Clients · More + FAB), Drift DB skeleton, and a tiny first-run name screen. Full SOAP / calendar / CRUD come next.

## Requirements

- [Flutter](https://docs.flutter.dev/get-started/install) stable (3.35+ recommended)
- Android SDK (for APK / device runs)

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

## Project layout

```
lib/
  main.dart                 # opens DB, boots app
  app.dart                  # MaterialApp + first-run gate
  theme/                    # PelviColors, spacing, ThemeData
  data/                     # Drift schema + sync stub
  features/
    shell/                  # bottom nav + center FAB + quick-add
    first_run/              # practitioner name
    today|calendar|clients|more/
    placeholders/           # stub destinations
  widgets/                  # empty states
```

## Design

Cream canvas `#FFFCFA`, dusty pink `#B63C70` primary, purple `#7B609F` secondary, Inter. Figma is visual SoT — see project design-system docs in the Pelvi CRM Cursor store.
