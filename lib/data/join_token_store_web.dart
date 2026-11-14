import 'dart:html' as html;

const _key = 'notesonly_join_token';

String? readPendingJoinToken() {
  try {
    final v = html.window.sessionStorage[_key];
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  } catch (_) {
    return null;
  }
}

void savePendingJoinToken(String token) {
  final t = token.trim();
  if (t.isEmpty) {
    clearPendingJoinToken();
    return;
  }
  try {
    html.window.sessionStorage[_key] = t;
  } catch (_) {}
}

void clearPendingJoinToken() {
  try {
    html.window.sessionStorage.remove(_key);
  } catch (_) {}
}

void replaceJoinUrlWithHome() {
  try {
    final origin = html.window.location.origin;
    html.window.history.replaceState(null, '', '$origin/');
  } catch (_) {}
}
