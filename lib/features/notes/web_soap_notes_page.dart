import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/theme.dart';
import '../clients/client_format.dart';
import '../shell/desktop_chrome.dart';
import 'note_format.dart';
import 'open_note.dart';
import 'web_soap_note_workspace.dart';

/// Desktop SOAP notes destination: hub or three-column editor.
class WebSoapNotesPage extends StatelessWidget {
  const WebSoapNotesPage({
    super.key,
    required this.noteId,
    required this.onBreadcrumb,
    required this.onOpenNote,
  });

  /// Fallback when [ShellNavigation] is absent (e.g. capture tools).
  final int? noteId;
  final ValueChanged<String?> onBreadcrumb;
  final ValueChanged<int> onOpenNote;

  @override
  Widget build(BuildContext context) {
    // Nested tab [Navigator] freezes constructor props; shell id stays live.
    final id = ShellNavigation.maybeOf(context)?.soapNoteId ?? noteId;
    if (id == null) {
      return _SoapNotesHub(
        onOpenNote: onOpenNote,
        onBreadcrumb: onBreadcrumb,
      );
    }
    return WebSoapNoteWorkspace(
      noteId: id,
      onBreadcrumb: onBreadcrumb,
    );
  }
}

/// Empty / drafts hub when no note is open (appointment-linked only).
class _SoapNotesHub extends StatelessWidget {
  const _SoapNotesHub({
    required this.onOpenNote,
    required this.onBreadcrumb,
  });

  final ValueChanged<int> onOpenNote;
  final ValueChanged<String?> onBreadcrumb;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onBreadcrumb(null);
    });
    final c = PelviColors.of(context);
    final db = AppDatabaseProvider.of(context);

    return ColoredBox(
      color: c.canvas,
      child: StreamBuilder<List<({Note note, Client client})>>(
        stream: db.watchOpenSoapDrafts(),
        builder: (context, snap) {
          final drafts = snap.data ?? const [];
          return SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'SOAP notes',
                  style: TextStyle(
                    fontSize: 29,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Open a note from an appointment. Notes stay tied to visits.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: c.inkMuted,
                  ),
                ),
                const SizedBox(height: 26),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: () async {
                      await openNoteViaPickers(context);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: c.pink700,
                      foregroundColor: c.inkInverse,
                      elevation: 0,
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(PelviRadius.sm),
                      ),
                    ),
                    child: const Text(
                      'Open from appointment',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (drafts.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  Text(
                    'Open drafts',
                    style: TextStyle(
                      fontSize: 17,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (final row in drafts) ...[
                    _DraftTile(
                      note: row.note,
                      client: row.client,
                      onOpen: () => onOpenNote(row.note.id),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DraftTile extends StatelessWidget {
  const _DraftTile({
    required this.note,
    required this.client,
    required this.onOpen,
  });

  final Note note;
  final Client client;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final avatar = clientAvatarColors(client, c);
    final linked = note.appointmentId != null;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(PelviRadius.button),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(PelviRadius.button),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PelviRadius.button),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: avatar.wash,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  clientInitials(client),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: avatar.ink,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clientDisplayName(client),
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      linked
                          ? formatNoteDate(note.noteDate)
                          : '${formatNoteDate(note.noteDate)} · unlinked',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: c.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'Continue →',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                  color: c.pink700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
