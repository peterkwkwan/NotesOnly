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

/// One-line preview from the first non-empty SOAP section.
String soapRevisionPreview({
  required String subjective,
  required String objective,
  required String assessment,
  required String plan,
}) {
  for (final raw in [subjective, objective, assessment, plan]) {
    final t = raw.trim();
    if (t.isEmpty) continue;
    final one = t.replaceAll(RegExp(r'\s+'), ' ');
    if (one.length <= 72) return one;
    return '${one.substring(0, 72)}…';
  }
  return 'Empty snapshot';
}
