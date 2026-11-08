import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/show_snack.dart';
import '../clients/client_format.dart';
import '../shell/desktop_chrome.dart';
import 'note_editor_screen.dart';

/// Open the note for an appointment (create draft if none).
Future<void> openNoteForAppointment(
  BuildContext context, {
  required int appointmentId,
  required int clientId,
  DateTime? noteDate,
}) async {
  final db = AppDatabaseProvider.of(context);
  final note = await db.getOrCreateNoteForAppointment(
    appointmentId: appointmentId,
    clientId: clientId,
    noteDate: noteDate,
  );
  if (!context.mounted) return;
  final shell = ShellNavigation.maybeOf(context);
  if (shell?.openSoapNote != null && isDesktopShell(context)) {
    shell!.openSoapNote!(note.id);
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => NoteEditorScreen(noteId: note.id),
    ),
  );
}

/// FAB / quick-add: pick client → pick appointment → open note.
Future<void> openNoteViaPickers(BuildContext context) async {
  final db = AppDatabaseProvider.of(context);
  final clients = await db.watchClients().first;
  if (!context.mounted) return;

  if (clients.isEmpty) {
    showPelviSnackBar(context, 'Add a client first, then book a visit.');
    return;
  }

  final int? clientId;
  if (clients.length == 1) {
    clientId = clients.first.id;
  } else {
    clientId = await showPelviPickerSheet<int>(
      context: context,
      title: 'Client',
      searchable: true,
      searchHint: 'Search name or phone',
      options: [
        for (final c in clients)
          PelviPickerOption(
            value: c.id,
            label: clientDisplayName(c),
            subtitle: (c.phone ?? '').trim().isEmpty ? null : c.phone,
            searchText: '${clientDisplayName(c)} ${c.phone ?? ''}',
          ),
      ],
    );
  }
  if (clientId == null || !context.mounted) return;

  final appts = await db.watchAppointmentsForClient(clientId).first;
  if (!context.mounted) return;

  if (appts.isEmpty) {
    showPelviSnackBar(context, 'Book an appointment for this client first.');
    return;
  }

  final Appointment? appointment;
  if (appts.length == 1) {
    appointment = appts.first;
  } else {
    appointment = await showPelviPickerSheet<Appointment>(
      context: context,
      title: 'Appointment',
      options: [
        for (final a in appts)
          PelviPickerOption(
            value: a,
            label: formatApptWhen(a.startsAt),
            subtitle: appointmentStatusLabel(a.status),
            subtitleColor: appointmentStatusColor(a.status),
          ),
      ],
    );
  }
  if (appointment == null || !context.mounted) return;

  await openNoteForAppointment(
    context,
    appointmentId: appointment.id,
    clientId: clientId,
    noteDate: appointment.startsAt,
  );
}
