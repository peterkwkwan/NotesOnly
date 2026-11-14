/// Non-web: token only lives in memory for this isolate.
String? _memory;

String? readPendingJoinToken() => _memory;

void savePendingJoinToken(String token) {
  _memory = token.trim().isEmpty ? null : token.trim();
}

void clearPendingJoinToken() {
  _memory = null;
}

void replaceJoinUrlWithHome() {}
