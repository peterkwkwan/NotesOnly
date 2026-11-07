import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../appointments/appointment_form_screen.dart';
import '../clients/client_form_screen.dart';

/// FAB quick-add sheet: Client / Appointment.
Future<void> showQuickAddSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: PelviColors.of(context).surface,
    barrierColor: PelviColors.of(context).overlay,
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
                  color: PelviColors.of(context).border,
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
              'Start a client or appointment.',
              style: text.bodyMedium?.copyWith(color: PelviColors.of(context).inkMuted),
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
      splashColor: PelviColors.of(context).surfaceMuted,
      highlightColor: PelviColors.of(context).surfaceMuted,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: PelviSpace.sm + 4,
          horizontal: PelviSpace.xs,
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: PelviColors.of(context).pink700),
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
            Icon(
              Icons.chevron_right,
              color: PelviColors.of(context).inkMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
