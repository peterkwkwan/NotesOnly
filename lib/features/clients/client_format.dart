import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../theme/colors.dart';

String clientDisplayName(Client c) => '${c.firstName} ${c.lastName}'.trim();

/// Case-insensitive match on name / phone / email (fields that exist).
bool clientMatchesQuery(Client c, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final hay = [
    c.firstName,
    c.lastName,
    '${c.firstName} ${c.lastName}',
    if (c.phone != null) c.phone!,
    if (c.email != null) c.email!,
  ].join(' ').toLowerCase();
  return hay.contains(q);
}

List<Client> filterClients(List<Client> clients, String query) {
  final q = query.trim();
  if (q.isEmpty) return clients;
  return [for (final c in clients) if (clientMatchesQuery(c, q)) c];
}

/// Preserve [recentIds] order; drop missing clients.
List<Client> clientsInIdOrder(List<Client> clients, List<int> recentIds) {
  if (recentIds.isEmpty) return const [];
  final byId = {for (final c in clients) c.id: c};
  return [
    for (final id in recentIds)
      if (byId[id] != null) byId[id]!,
  ];
}

/// Phone-book section letter from last name (A–Z or `#`).
String clientSectionLetter(Client c) {
  final name = c.lastName.trim();
  if (name.isEmpty) return '#';
  final u = name[0].toUpperCase();
  if (u.compareTo('A') >= 0 && u.compareTo('Z') <= 0) return u;
  return '#';
}

/// Group already A–Z-sorted clients into sticky letter sections.
List<({String letter, List<Client> clients})> groupClientsByLetter(
  List<Client> sorted,
) {
  final groups = <({String letter, List<Client> clients})>[];
  String? current;
  var bucket = <Client>[];
  for (final c in sorted) {
    final letter = clientSectionLetter(c);
    if (current == null) {
      current = letter;
      bucket = [c];
    } else if (letter == current) {
      bucket.add(c);
    } else {
      groups.add((letter: current, clients: bucket));
      current = letter;
      bucket = [c];
    }
  }
  if (current != null) {
    groups.add((letter: current, clients: bucket));
  }
  return groups;
}

/// Letter heights / row extents must match `_LetterBar` / `_ClientRow` layout.
const kAlphaLetterHeaderHeight = 28.0;
const kAlphaClientRowHeight = 80.0;
const kAlphaClientDividerHeight = 1.0;

/// Leading phone-book section above A–Z (sticky overlay uses this label).
const kPinnedSectionLabel = 'Pinned';

/// Current A–Z sticky letter for [offset] — one letter, never a stacked set.
String stickyLetterAtOffset(
  List<({String letter, int count})> sections,
  double offset, {
  double letterHeight = kAlphaLetterHeaderHeight,
  double rowHeight = kAlphaClientRowHeight,
  double dividerHeight = kAlphaClientDividerHeight,
}) {
  if (sections.isEmpty) return '';
  final yTop = offset < 0 ? 0.0 : offset;
  var y = 0.0;
  var letter = sections.first.letter;
  for (final s in sections) {
    letter = s.letter;
    final clientsExtent = s.count <= 0
        ? 0.0
        : s.count * rowHeight + (s.count - 1) * dividerHeight;
    final next = y + letterHeight + clientsExtent;
    if (yTop < next) return letter;
    y = next;
  }
  return letter;
}

String appointmentStatusLabel(AppointmentStatus status) {
  return switch (status) {
    AppointmentStatus.scheduled => 'Scheduled',
    AppointmentStatus.completed => 'Completed',
    AppointmentStatus.cancelled => 'Cancelled',
    AppointmentStatus.noShow => 'No-show',
  };
}

/// Status word color only — light/dark pink, purple, muted.
Color appointmentStatusColor(AppointmentStatus status) {
  return switch (status) {
    AppointmentStatus.scheduled => PelviColors.pink400,
    AppointmentStatus.completed => PelviColors.pink700,
    AppointmentStatus.cancelled => PelviColors.inkMuted,
    AppointmentStatus.noShow => PelviColors.purple700,
  };
}

String formatApptWhen(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$y-$m-$d · $hh:$mm';
}

String formatApptTime(DateTime dt) {
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}
