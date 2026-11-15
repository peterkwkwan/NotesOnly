import 'dart:html' as html;

/// Survives hard refresh in the same tab; cleared on tab close / sign-out.
const _key = 'notesonly_gcal_access_token';

String? readCalendarAccessToken() {
  try {
    final v = html.window.sessionStorage[_key];
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
    html.window.sessionStorage[_key] = t;
  } catch (_) {}
}

void clearCalendarAccessTokenStore() {
  try {
    html.window.sessionStorage.remove(_key);
  } catch (_) {}
}
