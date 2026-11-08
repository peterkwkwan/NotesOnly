import 'dart:async';
import 'dart:io';

/// Light reachability probe — no connectivity_plus.
///
/// False negatives possible on captive portals; Sync now still times out safely.
Future<bool> deviceLooksOnline({
  Duration timeout = const Duration(seconds: 2),
}) async {
  try {
    final result = await InternetAddress.lookup('dns.google.com').timeout(timeout);
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } on SocketException {
    return false;
  } on TimeoutException {
    return false;
  } catch (_) {
    return false;
  }
}
