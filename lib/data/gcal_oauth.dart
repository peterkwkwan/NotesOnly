import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Cloud Functions wrappers for long-lived Google Calendar OAuth.
class GcalOAuth {
  GcalOAuth({FirebaseFunctions? functions}) : _functions = functions;

  final FirebaseFunctions? _functions;

  FirebaseFunctions get _fn =>
      _functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Returns Google consent URL (offline + consent). Opens in browser/custom tab.
  Future<String> beginConnect() async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw StateError('Sign in required');
    }
    final callable = _fn.httpsCallable('beginGoogleCalendarOAuth');
    final result = await callable.call(<String, dynamic>{});
    final map = Map<String, dynamic>.from(result.data as Map);
    final url = map['authUrl'] as String?;
    if (url == null || url.isEmpty) {
      throw StateError('No Calendar auth URL returned');
    }
    return url;
  }

  Future<bool> isConnected() async {
    try {
      final callable = _fn.httpsCallable('getGoogleCalendarStatus');
      final result = await callable.call(<String, dynamic>{});
      final map = Map<String, dynamic>.from(result.data as Map);
      return map['connected'] == true;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'failed-precondition' || e.code == 'unauthenticated') {
        return false;
      }
      rethrow;
    }
  }

  /// Short-lived access token minted from the server refresh token.
  Future<({String accessToken, int expiresIn})?> mintAccessToken() async {
    try {
      final callable = _fn.httpsCallable('getCalendarAccessToken');
      final result = await callable.call(<String, dynamic>{});
      final map = Map<String, dynamic>.from(result.data as Map);
      final token = map['accessToken'] as String?;
      if (token == null || token.isEmpty) return null;
      final expiresIn = (map['expiresIn'] as num?)?.toInt() ?? 3600;
      return (accessToken: token, expiresIn: expiresIn);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'failed-precondition' || e.code == 'unauthenticated') {
        return null;
      }
      rethrow;
    }
  }

  /// Revoke + delete server refresh token. Leaves Google events in place.
  Future<void> disconnect() async {
    final callable = _fn.httpsCallable('disconnectGoogleCalendar');
    await callable.call(<String, dynamic>{});
  }
}
