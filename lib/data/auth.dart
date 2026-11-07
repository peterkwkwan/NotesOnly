import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Google → Firebase Auth. No Firestore sync here (M2).
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
    if (_googleReady) return;
    await _google.initialize();
    _googleReady = true;
  }

  /// Returns false if the user cancelled the Google sheet.
  static Future<bool> signInWithGoogle() async {
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
    await ensureGoogleInitialized();
    await _google.signOut();
    await _auth.signOut();
  }
}
