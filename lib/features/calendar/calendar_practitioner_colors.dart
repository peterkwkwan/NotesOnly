import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Stable fill / accent / text swatches for a calendar practitioner.
class PracColors {
  const PracColors({
    required this.fill,
    required this.accent,
    required this.text,
  });

  final Color fill;
  final Color accent;
  final Color text;
}

/// Pink = me; others get purple / teal / amber by roster order, else UID hash.
PracColors practitionerColors({
  required PelviPalette c,
  required String uid,
  required String selfUid,
  required List<String> rosterUids,
}) {
  final id = uid.isEmpty ? selfUid : uid;
  if (id.isEmpty || id == selfUid) {
    return PracColors(fill: c.pink50, accent: c.pink400, text: c.pink700);
  }
  // shortcut: teal/amber are fixed light swatches; upgrade if dark-calendar QA cares
  final extras = <PracColors>[
    PracColors(fill: c.purple50, accent: c.purple400, text: c.purple700),
    const PracColors(
      fill: Color(0xFFE6F5F0),
      accent: Color(0xFF5BA88A),
      text: Color(0xFF1F7A5C),
    ),
    const PracColors(
      fill: Color(0xFFFBF0E6),
      accent: Color(0xFFE0A066),
      text: Color(0xFFB56A1E),
    ),
  ];
  final others = [for (final u in rosterUids) if (u != selfUid) u];
  final idx = others.indexOf(id);
  final pick =
      idx < 0 ? id.hashCode.abs() % extras.length : idx % extras.length;
  return extras[pick];
}
