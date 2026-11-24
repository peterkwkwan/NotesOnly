/// Effective end when [endsAt] is missing or not after start: start + default.
DateTime appointmentEffectiveEnd(
  DateTime startsAt,
  DateTime? endsAt,
  int defaultMinutes,
) {
  if (endsAt != null && endsAt.isAfter(startsAt)) return endsAt;
  final mins = defaultMinutes > 0 ? defaultMinutes : 60;
  return startsAt.add(Duration(minutes: mins));
}

/// Half-open intervals [aStart, aEnd) and [bStart, bEnd).
bool appointmentsOverlap(
  DateTime aStart,
  DateTime aEnd,
  DateTime bStart,
  DateTime bEnd,
) {
  return aStart.isBefore(bEnd) && bStart.isBefore(aEnd);
}

/// Snackbar / dialog copy when save is blocked.
String appointmentConflictCopy({
  required String clientName,
  required DateTime startsAt,
}) {
  final hh = startsAt.hour.toString().padLeft(2, '0');
  final mm = startsAt.minute.toString().padLeft(2, '0');
  return 'Overlapping appointment: $clientName at $hh:$mm';
}

/// Google Calendar–style columns for one day: overlapping events sit
/// side-by-side; each collision cluster uses its own column count.
///
/// [intervals] are half-open `[start, end)`. Returns one `(lane, laneCount)`
/// per input index. Solo clusters get `laneCount == 1` (full width).
List<({int lane, int laneCount})> calendarOverlapLanes(
  List<({DateTime start, DateTime end})> intervals,
) {
  final n = intervals.length;
  if (n == 0) return const [];

  final order = [for (var i = 0; i < n; i++) i]..sort((a, b) {
      final byStart = intervals[a].start.compareTo(intervals[b].start);
      if (byStart != 0) return byStart;
      // Longer first (GCal packing).
      return intervals[b].end.compareTo(intervals[a].end);
    });

  final laneOf = List<int>.filled(n, 0);
  final laneEnds = <DateTime>[];
  for (final i in order) {
    final start = intervals[i].start;
    var end = intervals[i].end;
    if (!end.isAfter(start)) {
      end = start.add(const Duration(minutes: 1));
    }
    var lane = 0;
    while (lane < laneEnds.length && laneEnds[lane].isAfter(start)) {
      lane++;
    }
    if (lane == laneEnds.length) {
      laneEnds.add(end);
    } else {
      laneEnds[lane] = end;
    }
    laneOf[i] = lane;
  }

  // Cluster = maximal run where each next start is still before cluster end.
  final laneCountOf = List<int>.filled(n, 1);
  var cluster = <int>[];
  DateTime? clusterEnd;

  void flush() {
    if (cluster.isEmpty) return;
    var maxLane = 0;
    for (final i in cluster) {
      if (laneOf[i] > maxLane) maxLane = laneOf[i];
    }
    final count = maxLane + 1;
    for (final i in cluster) {
      laneCountOf[i] = count;
    }
    cluster = [];
    clusterEnd = null;
  }

  for (final i in order) {
    final start = intervals[i].start;
    var end = intervals[i].end;
    if (!end.isAfter(start)) {
      end = start.add(const Duration(minutes: 1));
    }
    if (clusterEnd != null && !start.isBefore(clusterEnd!)) {
      flush();
    }
    cluster.add(i);
    if (clusterEnd == null || end.isAfter(clusterEnd!)) {
      clusterEnd = end;
    }
  }
  flush();

  return [
    for (var i = 0; i < n; i++) (lane: laneOf[i], laneCount: laneCountOf[i]),
  ];
}
