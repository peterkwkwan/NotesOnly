/// Web reachability — fail *open*.
///
/// `dart:io` DNS lookup is unavailable in the browser. A closed false here
/// made Google Calendar [drain] skip forever while the UI still said Connected.
/// Calendar HTTP itself soft-fails when the network is actually down.
Future<bool> deviceLooksOnline({
  Duration timeout = const Duration(seconds: 2),
}) async {
  return true;
}
