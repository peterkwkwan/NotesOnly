import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../appointments/appointment_form_screen.dart';
import '../clients/client_form_screen.dart';
import '../notes/open_note.dart';

/// FAB quick-add sheet: Client / Appointment / Note.
Future<void> showQuickAddSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: PelviColors.surface,
    barrierColor: PelviColors.overlay,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(PelviRadius.lg)),
    ),
    builder: (context) => const QuickAddSheet(),
  );
}

class QuickAddSheet extends StatelessWidget {
  const QuickAddSheet({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  void _openNote(BuildContext context) {
    final nav = Navigator.of(context);
    nav.pop();
    // After sheet closes, pick client/appointment then open editor.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = nav.context;
      if (ctx.mounted) openNoteViaPickers(ctx);
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
                    PelviSpace.page,
                    PelviSpace.sm,
                    PelviSpace.page,
                    PelviSpace.md,
                  ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: PelviColors.border,
                  borderRadius: BorderRadius.circular(PelviRadius.full),
                ),
              ),
            ),
            const SizedBox(height: PelviSpace.md),
            Text(
              'Quick add',
              style: text.titleLarge,
            ),
            const SizedBox(height: PelviSpace.xs),
            Text(
              'Start a client, appointment, or SOAP note.',
              style: text.bodyMedium?.copyWith(color: PelviColors.inkMuted),
            ),
            const SizedBox(height: PelviSpace.md),
            const Divider(height: 1),
            _QuickAddRow(
              icon: Icons.person_add_outlined,
              title: 'Client',
              subtitle: 'Add a new patient profile',
              onTap: () => _open(context, const ClientFormScreen()),
            ),
            const Divider(height: 1),
            _QuickAddRow(
              icon: Icons.event_outlined,
              title: 'Appointment',
              subtitle: 'Book a visit on the calendar',
              onTap: () => _open(context, const AppointmentFormScreen()),
            ),
            const Divider(height: 1),
            _QuickAddRow(
              icon: Icons.notes_outlined,
              title: 'Note',
              subtitle: 'Start a SOAP draft',
              onTap: () => _openNote(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAddRow extends StatelessWidget {
  const _QuickAddRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      splashColor: PelviColors.surfaceMuted,
      highlightColor: PelviColors.surfaceMuted,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: PelviSpace.sm + 4,
          horizontal: PelviSpace.xs,
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: PelviColors.pink700),
            const SizedBox(width: PelviSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: PelviColors.inkMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
