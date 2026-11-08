// Generated from Firebase project notesonly-e4829.
// Android: android/app/google-services.json.
// Web: Firebase Console web app config.
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

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCszG1jvvDjQZEs-sskkhVf0LbTeh3tfMk',
    appId: '1:832931514693:web:a2902ee456eacd5f95162c',
    messagingSenderId: '832931514693',
    projectId: 'notesonly-e4829',
    authDomain: 'notesonly-e4829.firebaseapp.com',
    storageBucket: 'notesonly-e4829.firebasestorage.app',
    measurementId: 'G-DBKMQDKGBK',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBxVs-nxEczlWAKrTdk1z_b-bqTvNt9KjE',
    appId: '1:832931514693:android:6483b1094aad6ebf95162c',
    messagingSenderId: '832931514693',
    projectId: 'notesonly-e4829',
    storageBucket: 'notesonly-e4829.firebasestorage.app',
  );
}
