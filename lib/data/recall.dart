import 'database.dart';

/// Client past the recall window (had ≥1 non-cancelled appointment).
class RecallDueEntry {
  const RecallDueEntry({
    required this.client,
    required this.lastSeen,
  });

  final Client client;

  /// Latest non-cancelled appointment or note date.
  final DateTime lastSeen;
}

/// Last activity = max(non-cancelled appointment.startsAt, note.noteDate).
DateTime? lastSeenForClient({
  required int clientId,
  required List<Appointment> appointments,
  required List<Note> notes,
}) {
  DateTime? last;
  for (final a in appointments) {
    if (a.clientId != clientId) continue;
    if (a.status == AppointmentStatus.cancelled) continue;
    if (last == null || a.startsAt.isAfter(last)) last = a.startsAt;
  }
  for (final n in notes) {
    if (n.clientId != clientId) continue;
    if (last == null || n.noteDate.isAfter(last)) last = n.noteDate;
  }
  return last;
}

/// Pure filter — easy to unit-test without Drift streams.
///
/// Excludes never-seen / cancelled-only (no non-cancelled appointment).
/// Due tab + notifications bell both use this.
List<RecallDueEntry> computeRecallDue({
  required List<Client> clients,
  required List<Appointment> appointments,
  required List<Note> notes,
  required int recallDays,
  required DateTime now,
  Set<int> mutedClientIds = const {},
}) {
  // 0 = Never (settings sentinel): no Due / bell / local notifs.
  if (recallDays <= 0) return const [];
  final cutoff = now.subtract(Duration(days: recallDays));
  final due = <RecallDueEntry>[];
  for (final c in clients) {
    if (mutedClientIds.contains(c.id)) continue;
    var seenAppt = false;
    for (final a in appointments) {
      if (a.clientId != c.id) continue;
      if (a.status == AppointmentStatus.cancelled) continue;
      seenAppt = true;
      break;
    }
    if (!seenAppt) continue;
    final last = lastSeenForClient(
      clientId: c.id,
      appointments: appointments,
      notes: notes,
    );
    // seenAppt ⇒ last non-null (notes can only push it later).
    if (last != null && last.isBefore(cutoff)) {
      due.add(RecallDueEntry(client: c, lastSeen: last));
    }
  }
  due.sort((a, b) => a.lastSeen.compareTo(b.lastSeen));
  return due;
}

String formatLastSeenCaption(DateTime? lastSeen, DateTime now) {
  if (lastSeen == null) return 'Never seen';
  final days = now.difference(lastSeen).inDays;
  if (days <= 0) return 'Seen today';
  if (days == 1) return 'Last seen 1 day ago';
  return 'Last seen $days days ago';
}
