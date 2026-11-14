import 'join_token_store_stub.dart'
    if (dart.library.html) 'join_token_store_web.dart' as store;

/// Capture `/join?token=` from the browser URL and keep it across Google redirect.
String? captureJoinTokenFromUri([Uri? uri]) {
  final u = uri ?? Uri.base;
  final fromQuery = u.queryParameters['token']?.trim();
  if (fromQuery != null && fromQuery.isNotEmpty) {
    store.savePendingJoinToken(fromQuery);
    return fromQuery;
  }
  return store.readPendingJoinToken();
}

String? peekPendingJoinToken() => store.readPendingJoinToken();

void clearPendingJoinToken() => store.clearPendingJoinToken();

/// Drop `/join?token=…` from the address bar after accept/fail (web).
void replaceJoinUrlWithHome() => store.replaceJoinUrlWithHome();
