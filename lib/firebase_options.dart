// Generated from Firebase project notesonly-e4829.
// Android: android/app/google-services.json.
// Web: same project browser key + web app id (register Web app in Console if missing).
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        throw UnsupportedError(
          'FirebaseOptions are only set for Android and web. '
          'Use FlutterFire CLI when adding another platform.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // shortcut: appId is a stub until Peter adds a Web app in Console and pastes
  // the real appId (or runs `flutterfire configure`); Auth primarily needs apiKey.
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBxVs-nxEczlWAKrTdk1z_b-bqTvNt9KjE',
    appId: '1:832931514693:web:00000000000000000000000000000001',
    messagingSenderId: '832931514693',
    projectId: 'notesonly-e4829',
    authDomain: 'notesonly-e4829.firebaseapp.com',
    storageBucket: 'notesonly-e4829.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBxVs-nxEczlWAKrTdk1z_b-bqTvNt9KjE',
    appId: '1:832931514693:android:6483b1094aad6ebf95162c',
    messagingSenderId: '832931514693',
    projectId: 'notesonly-e4829',
    storageBucket: 'notesonly-e4829.firebasestorage.app',
  );
}
