import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

/// Google → Firebase Auth (Android: google_sign_in; web: Auth popup).
class NotesAuth {
  NotesAuth._();

  static FirebaseAuth get _auth => FirebaseAuth.instance;
  static GoogleSignIn get _google => GoogleSignIn.instance;
  static bool _googleReady = false;

  /// Least privilege for primary-calendar event CRUD.
  static const calendarEventsScope =
      'https://www.googleapis.com/auth/calendar.events';

  /// In-memory Calendar access token (never Firestore).
  static String? _calendarAccessToken;

  static Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// Null when signed out or Firebase is not initialized (widget tests).
  static User? get currentUser {
    try {
      return _auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  static String? get calendarAccessToken => _calendarAccessToken;

  static Future<void> ensureGoogleInitialized() async {
    if (kIsWeb || _googleReady) return;
    await _google.initialize();
    _googleReady = true;
  }

  /// Returns false if the user cancelled the Google sheet / popup.
  static Future<bool> signInWithGoogle() async {
    if (kIsWeb) {
      try {
        final provider = GoogleAuthProvider()
          ..setCustomParameters({'prompt': 'select_account'});
        await _auth.signInWithPopup(provider);
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

  /// Request Calendar write scope. [interactive] shows the consent UI.
  ///
  /// Returns the access token, or null if the user cancelled / denied.
  /// Does not change the Firebase session identity on Android; on web may
  /// re-prompt via popup with the extra scope (plan option A).
  static Future<String?> requestCalendarAccess({
    bool interactive = true,
  }) async {
    if (kIsWeb) {
      try {
        final provider = GoogleAuthProvider()
          ..addScope(calendarEventsScope);
        if (interactive) {
          provider.setCustomParameters({'prompt': 'consent select_account'});
        }
        final result = await _auth.signInWithPopup(provider);
        final cred = result.credential;
        if (cred is OAuthCredential &&
            cred.accessToken != null &&
            cred.accessToken!.isNotEmpty) {
          _calendarAccessToken = cred.accessToken;
          return _calendarAccessToken;
        }
        return null;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'popup-closed-by-user' ||
            e.code == 'cancelled-popup-request') {
          return null;
        }
        rethrow;
      }
    }

    await ensureGoogleInitialized();
    final client = _google.authorizationClient;
    try {
      final GoogleSignInClientAuthorization? authz;
      if (interactive) {
        authz = await client.authorizeScopes(const [calendarEventsScope]);
      } else {
        authz = await client.authorizationForScopes(
          const [calendarEventsScope],
        );
      }
      final token = authz?.accessToken;
      if (token == null || token.isEmpty) return null;
      _calendarAccessToken = token;
      return token;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  /// Drop a bad token from the platform cache (401 recovery).
  static Future<void> clearCalendarAccessToken() async {
    final token = _calendarAccessToken;
    _calendarAccessToken = null;
    if (token == null || kIsWeb) return;
    try {
      await ensureGoogleInitialized();
      await _google.authorizationClient.clearAuthorizationToken(
        accessToken: token,
      );
    } catch (_) {
      // Best-effort; next request will re-authorize.
    }
  }

  static Future<void> signOut() async {
    _calendarAccessToken = null;
    if (!kIsWeb) {
      await ensureGoogleInitialized();
      await _google.signOut();
    }
    await _auth.signOut();
  }
}
