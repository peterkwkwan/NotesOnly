import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

/// Google → Firebase Auth (Android: google_sign_in; web: Auth popup).
class NotesAuth {
  NotesAuth._();

  static FirebaseAuth get _auth => FirebaseAuth.instance;
  static GoogleSignIn get _google => GoogleSignIn.instance;
  static bool _googleReady = false;

  static Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// Null when signed out or Firebase is not initialized (widget tests).
  static User? get currentUser {
    try {
      return _auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  static Future<void> ensureGoogleInitialized() async {
    if (kIsWeb || _googleReady) return;
    await _google.initialize();
    _googleReady = true;
  }

  /// Returns false if the user cancelled the Google sheet / popup.
  static Future<bool> signInWithGoogle() async {
    if (kIsWeb) {
      try {
        await _auth.signInWithPopup(GoogleAuthProvider());
        return true;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'popup-closed-by-user' ||
            e.code == 'cancelled-popup-request') {
          return false;
        }
        rethrow;
      }
    }

    await ensureGoogleInitialized();
    try {
      final account = await _google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw StateError(
          'Google Sign-In returned no idToken. Add the debug SHA-1 in '
          'Firebase Console for com.notes.notes_only, re-download '
          'google-services.json if oauth_client is still empty, then rebuild.',
        );
      }
      await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
      return true;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      rethrow;
    }
  }

  static Future<void> signOut() async {
    if (!kIsWeb) {
      await ensureGoogleInitialized();
      await _google.signOut();
    }
    await _auth.signOut();
  }
}
