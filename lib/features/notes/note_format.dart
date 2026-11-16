/// Abbreviated weekday + day + month + year, e.g. `Wed, 28 Oct 2026`.
String formatNoteDate(DateTime dt) {
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${weekdays[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]} ${dt.year}';
}

/// Snapshot time for revision rows / revert confirm, e.g. `15 Nov 2026, 14:05`.
String formatRevisionDateTime(DateTime dt) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = dt.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${months[local.month - 1]} ${local.year}, $hh:$mm';
}

/// One-line revision preview: prefer the latest changed SOAP chunk vs [previous*],
/// else the first non-empty section.
String soapRevisionPreview({
  required String subjective,
  required String objective,
  required String assessment,
  required String plan,
  String? previousSubjective,
  String? previousObjective,
  String? previousAssessment,
  String? previousPlan,
}) {
  if (previousSubjective != null &&
      previousObjective != null &&
      previousAssessment != null &&
      previousPlan != null) {
    final changed = _latestChangedSoapChunk(
      current: [subjective, objective, assessment, plan],
      previous: [
        previousSubjective,
        previousObjective,
        previousAssessment,
        previousPlan,
      ],
    );
    if (changed != null) return _oneLinePreview(changed);
  }
  for (final raw in [subjective, objective, assessment, plan]) {
    final t = raw.trim();
    if (t.isEmpty) continue;
    return _oneLinePreview(t);
  }
  return 'Empty snapshot';
}

/// Last SOAP field that differs from [previous], showing the changed sentence/block.
String? _latestChangedSoapChunk({
  required List<String> current,
  required List<String> previous,
}) {
  String? best;
  for (var i = 0; i < current.length; i++) {
    if (current[i] == previous[i]) continue;
    best = _changedFieldChunk(current[i], previous[i]);
  }
  return best;
}

/// Full sentence/field block that changed (not just the differing words).
String _changedFieldChunk(String current, String previous) {
  final curr = current.trim();
  final prev = previous.trim();
  if (curr.isEmpty) return 'Cleared';
  if (prev.isEmpty) return curr;

  final currChunks = _soapTextChunks(curr);
  final prevChunks = _soapTextChunks(prev);
  if (currChunks.isEmpty) return curr;

  // Prefer the last differing chunk (append-style edits).
  final n = currChunks.length > prevChunks.length
      ? currChunks.length
      : prevChunks.length;
  for (var i = n - 1; i >= 0; i--) {
    final c = i < currChunks.length ? currChunks[i] : '';
    final p = i < prevChunks.length ? prevChunks[i] : '';
    if (c != p && c.isNotEmpty) return c;
  }
  return curr;
}

/// Sentence / paragraph blocks inside one SOAP field.
List<String> _soapTextChunks(String text) {
  return text
      .split(RegExp(r'(?<=[.!?])\s+|\n+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

String _oneLinePreview(String raw) {
  final one = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (one.length <= 72) return one;
  return '${one.substring(0, 72)}…';
}
