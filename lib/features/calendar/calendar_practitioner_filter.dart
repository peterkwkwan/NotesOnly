/// Shared calendar practitioner filter (mobile + desktop).
///
/// Selection is a set of practitioner UIDs persisted under
/// [calendarFilterUidsKey]. Empty appointment `practitionerUid` counts as self.

/// Desktop week-view color budget; mobile may select more (Select all).
const maxCalendarPractitioners = 3;

String calendarFilterUidsKey(String orgId, String uid) =>
    'calendar_filter_uids__${orgId}__$uid';

/// Whether [practitionerUid] is in [filterUids]. Empty uid → [selfUid].
bool matchesCalendarFilter({
  required Set<String> filterUids,
  required String practitionerUid,
  required String selfUid,
}) {
  if (filterUids.isEmpty) return true;
  final uid = practitionerUid.isEmpty ? selfUid : practitionerUid;
  if (uid.isEmpty) return filterUids.contains(selfUid);
  return filterUids.contains(uid);
}

Set<String> parseCalendarFilterUids(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  final out = <String>{};
  for (final part in raw.split(',')) {
    final uid = part.trim();
    if (uid.isNotEmpty) out.add(uid);
  }
  return out;
}

String encodeCalendarFilterUids(Set<String> uids) => uids.join(',');
