/// Light reachability probe — no connectivity_plus.
///
/// False negatives possible on captive portals; Sync now still times out safely.
/// Web uses a fail-open stub (`online_web.dart`); IO uses DNS (`online_io.dart`).
export 'online_io.dart' if (dart.library.html) 'online_web.dart';
