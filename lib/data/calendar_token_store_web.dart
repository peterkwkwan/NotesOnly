import 'dart:html' as html;

/// Survives tab close/reopen in this browser profile; cleared on sign-out.
///
/// shortcut: Google access tokens still expire ~1h; web GIS popup does not
/// yield a Calendar refresh token — upgrade if we add a server-side OAuth
/// refresh path.
const _key = 'notesonly_gcal_access_token';

String? readCalendarAccessToken() {
  try {
    final v = html.window.localStorage[_key];
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  } catch (_) {
    return null;
  }
}

void saveCalendarAccessToken(String token) {
  final t = token.trim();
  if (t.isEmpty) {
    clearCalendarAccessTokenStore();
    return;
  }
  try {
    html.window.localStorage[_key] = t;
    // Drop legacy sessionStorage copy from pre-localStorage builds.
    html.window.sessionStorage.remove(_key);
  } catch (_) {}
}

void clearCalendarAccessTokenStore() {
  try {
    html.window.localStorage.remove(_key);
    html.window.sessionStorage.remove(_key);
  } catch (_) {}
}
