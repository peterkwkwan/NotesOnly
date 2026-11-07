import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../theme/theme.dart';
import '../clients/client_format.dart';
import '../notes/open_note.dart';
import 'appointment_form_screen.dart';

/// Today / Calendar day-list row: tap → edit appointment; note icon → SOAP.
class AppointmentAgendaRow extends StatelessWidget {
  const AppointmentAgendaRow({
    super.key,
    required this.appointment,
    required this.client,
    this.past = false,
  });

  final Appointment appointment;
  final Client client;
  final bool past;

  void _openEdit(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppointmentFormScreen(existing: appointment),
      ),
    );
  }

  void _openSoap(BuildContext context) {
    openNoteForAppointment(
      context,
      appointmentId: appointment.id,
      clientId: client.id,
      noteDate: appointment.startsAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ink = past ? PelviColors.of(context).inkMuted : PelviColors.of(context).ink;
    final decoration = past ? TextDecoration.lineThrough : TextDecoration.none;
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: () => _openEdit(context),
      splashColor: PelviColors.of(context).surfaceMuted,
      highlightColor: PelviColors.of(context).surfaceMuted,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PelviSpace.md,
          vertical: PelviSpace.sm + 4,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(
                  formatApptTime(appointment.startsAt),
                  style: text.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ink,
                    decoration: decoration,
                    decorationColor: ink,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      clientDisplayName(client),
                      style: text.labelLarge?.copyWith(
                        color: ink,
                        decoration: decoration,
                        decorationColor: ink,
                      ),
                    ),
                    Text.rich(
                      TextSpan(
                        style: text.labelMedium?.copyWith(
                          color: PelviColors.of(context).inkMuted,
                          decoration: decoration,
                          decorationColor: PelviColors.of(context).inkMuted,
                        ),
                        children: [
                          TextSpan(
                            text: appointmentStatusLabel(appointment.status),
                            style: TextStyle(
                              color: past
                                  ? PelviColors.of(context).inkMuted
                                  : appointmentStatusColor(appointment.status),
                              decoration: decoration,
                              decorationColor: PelviColors.of(context).inkMuted,
                            ),
                          ),
                          const TextSpan(text: ' · Note'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'SOAP note',
                onPressed: () => _openSoap(context),
                icon: Icon(
                  Icons.notes_outlined,
                  color: past ? PelviColors.of(context).inkMuted : PelviColors.of(context).purple700,
                  size: 20,
                ),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
