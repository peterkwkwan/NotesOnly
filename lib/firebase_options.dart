// Generated manually from android/app/google-services.json (project notesonly-e4829).
// Web/iOS: add apps in Firebase Console, then replace stubs via FlutterFire CLI
// (`flutterfire configure`) or paste options here.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'FirebaseOptions for web are not configured. '
        'Add a Web app in Firebase Console (notesonly-e4829) and run '
        '`flutterfire configure`, or paste web options into firebase_options.dart.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        throw UnsupportedError(
          'FirebaseOptions are only set for Android. '
          'Use FlutterFire CLI when adding another platform.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBxVs-nxEczlWAKrTdk1z_b-bqTvNt9KjE',
    appId: '1:832931514693:android:6483b1094aad6ebf95162c',
    messagingSenderId: '832931514693',
    projectId: 'notesonly-e4829',
    storageBucket: 'notesonly-e4829.firebasestorage.app',
  );
}
