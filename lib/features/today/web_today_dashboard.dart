import 'package:flutter/material.dart';

import '../../data/appointment_overlap.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/theme.dart';
import '../appointments/appointment_form_screen.dart';
import '../clients/client_format.dart';
import '../clients/client_profile_screen.dart';
import '../notes/note_editor_screen.dart';
import '../notes/note_format.dart';
import '../notes/open_note.dart';
import '../shell/desktop_chrome.dart';

/// Figma `NotesOnly · Today` page body (desktop shell already supplies chrome).
class WebTodayDashboard extends StatelessWidget {
  const WebTodayDashboard({super.key});

  void _addAppointment(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppointmentFormScreen(initialDay: DateTime.now()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = AppDatabaseProvider.of(context);
    final today = DateTime.now();
    final tomorrow = DateTime(today.year, today.month, today.day)
        .add(const Duration(days: 1));
    final c = PelviColors.of(context);

    return ColoredBox(
      color: c.canvas,
      child: StreamBuilder(
        stream: db.watchAppointmentsWithClientOnDay(today),
        builder: (context, apptSnap) {
          return StreamBuilder(
            stream: db.watchOpenSoapDrafts(),
            builder: (context, draftSnap) {
              return StreamBuilder(
                stream: db.watchRecallInboxClients(),
                builder: (context, recallSnap) {
                  return StreamBuilder(
                    stream: db.watchRecallDays(),
                    builder: (context, recallDaysSnap) {
                      return StreamBuilder(
                        stream: db.watchNextAppointmentOnOrAfter(tomorrow),
                        builder: (context, nextSnap) {
                          return StreamBuilder(
                            stream: db.watchDefaultAppointmentMinutes(),
                            builder: (context, minsSnap) {
                              return StreamBuilder(
                                stream: db.watchPractitionerName(),
                                builder: (context, nameSnap) {
                                  final appts = apptSnap.data ?? const [];
                                  final drafts = draftSnap.data ?? const [];
                                  final recalls = recallSnap.data ?? const [];
                                  final recallDays = recallDaysSnap.data ?? 14;
                                  final next = nextSnap.data;
                                  final defaultMins = minsSnap.data ?? 60;
                                  final practitioner =
                                      (nameSnap.data ?? '').trim();

                                  return SingleChildScrollView(
                                    padding: const EdgeInsets.all(32),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _HeroRow(
                                          today: today,
                                          onNewNote: () =>
                                              openNoteViaPickers(context),
                                          onAddAppointment: () =>
                                              _addAppointment(context),
                                        ),
                                        const SizedBox(height: 26),
                                        _SummaryRow(
                                          appointments: appts,
                                          drafts: drafts,
                                          recallCount: recalls.length,
                                          recallDays: recallDays,
                                        ),
                                        const SizedBox(height: 26),
                                        LayoutBuilder(
                                          builder: (context, constraints) {
                                            final sideBySide =
                                                constraints.maxWidth >= 980;
                                            final agenda = _AgendaPanel(
                                              today: today,
                                              rows: appts,
                                              defaultMinutes: defaultMins,
                                              practitionerName: practitioner,
                                            );
                                            final draftsPanel = _DraftsPanel(
                                              drafts: drafts,
                                            );
                                            final side = SizedBox(
                                              width: sideBySide
                                                  ? 340
                                                  : double.infinity,
                                              child: Column(
                                                children: [
                                                  _RecallsPanel(
                                                    count: recalls.length,
                                                    recallDays: recallDays,
                                                  ),
                                                  const SizedBox(height: 24),
                                                  _UpNextPanel(next: next),
                                                ],
                                              ),
                                            );
                                            if (!sideBySide) {
                                              return Column(
                                                children: [
                                                  agenda,
                                                  const SizedBox(height: 24),
                                                  draftsPanel,
                                                  const SizedBox(height: 24),
                                                  side,
                                                ],
                                              );
                                            }
                                            return Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    children: [
                                                      agenda,
                                                      const SizedBox(
                                                          height: 24),
                                                      draftsPanel,
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 24),
                                                side,
                                              ],
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

String _pad2(int n) => n.toString().padLeft(2, '0');

String _heroDateLabel(DateTime d) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${weekdays[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
}

String _agendaDateLabel(DateTime d) {
  const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  const months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  return '${weekdays[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
}

String _upNextDayLabel(DateTime d) {
  const weekdays = [
    'MONDAY',
    'TUESDAY',
    'WEDNESDAY',
    'THURSDAY',
    'FRIDAY',
    'SATURDAY',
    'SUNDAY',
  ];
  const months = [
    'JANUARY',
    'FEBRUARY',
    'MARCH',
    'APRIL',
    'MAY',
    'JUNE',
    'JULY',
    'AUGUST',
    'SEPTEMBER',
    'OCTOBER',
    'NOVEMBER',
    'DECEMBER',
  ];
  return '${weekdays[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
}

class _HeroRow extends StatelessWidget {
  const _HeroRow({
    required this.today,
    required this.onNewNote,
    required this.onAddAppointment,
  });

  final DateTime today;
  final VoidCallback onNewNote;
  final VoidCallback onAddAppointment;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A little more room for care.',
                style: TextStyle(
                  fontSize: 29,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              Text(
                'Your practice at a glance · ${_heroDateLabel(today)}',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: c.inkMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        OutlinedButton.icon(
          onPressed: onNewNote,
          icon: Icon(Icons.edit_note_outlined, size: 16, color: c.ink),
          label: Text(
            'New note',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.ink,
            ),
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: c.surface,
            side: BorderSide(color: c.border),
            minimumSize: const Size(0, 38),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PelviRadius.sm),
            ),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: onAddAppointment,
          icon: const Icon(Icons.add, size: 16),
          label: const Text(
            'Add appointment',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: c.pink700,
            foregroundColor: c.inkInverse,
            minimumSize: const Size(0, 38),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PelviRadius.sm),
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.appointments,
    required this.drafts,
    required this.recallCount,
    required this.recallDays,
  });

  final List<({Appointment appointment, Client client})> appointments;
  final List<({Note note, Client client})> drafts;
  final int recallCount;
  final int recallDays;

  @override
  Widget build(BuildContext context) {
    final firstAppt = appointments.isEmpty ? null : appointments.first;
    final firstDraft = drafts.isEmpty ? null : drafts.first;
    final apptDetail = firstAppt == null
        ? 'Nothing booked'
        : '${clientDisplayName(firstAppt.client)} · ${formatApptTime(firstAppt.appointment.startsAt)}';
    final draftDetail = firstDraft == null
        ? 'No open drafts'
        : '${clientDisplayName(firstDraft.client)} · ${_shortNoteDay(firstDraft.note.noteDate)}';
    final recallDetail = recallDays <= 0
        ? 'Recall off'
        : '$recallDays-day recall window';

    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            count: appointments.length,
            title: appointments.length == 1
                ? 'Appointment today'
                : 'Appointments today',
            detail: apptDetail,
            icon: Icons.calendar_month_outlined,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _SummaryCard(
            count: drafts.length,
            title: drafts.length == 1 ? 'Open SOAP draft' : 'Open SOAP drafts',
            detail: draftDetail,
            icon: Icons.edit_note_outlined,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _SummaryCard(
            count: recallCount,
            title: recallCount == 1
                ? 'Client due for recall'
                : 'Clients due for recall',
            detail: recallDetail,
            icon: Icons.replay_outlined,
          ),
        ),
      ],
    );
  }
}

String _shortNoteDay(DateTime d) => '${d.day} ${_monthShort(d.month)}';

String _monthShort(int m) {
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
  return months[m - 1];
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.count,
    required this.title,
    required this.detail,
    required this.icon,
  });

  final int count;
  final String title;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Text(
            _pad2(count),
            style: TextStyle(
              fontSize: 36,
              height: 1,
              letterSpacing: -1,
              color: c.pink700,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    color: c.inkMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(icon, size: 18, color: c.inkMuted),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: child,
    );
  }
}

class _PanelLink extends StatelessWidget {
  const _PanelLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          height: 1.5,
          fontWeight: FontWeight.w600,
          color: c.pink700,
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.title, this.link});

  final String title;
  final Widget? link;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 17,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: c.ink,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (link != null) ...[const SizedBox(width: 8), link!],
      ],
    );
  }
}

class _AgendaPanel extends StatelessWidget {
  const _AgendaPanel({
    required this.today,
    required this.rows,
    required this.defaultMinutes,
    required this.practitionerName,
  });

  final DateTime today;
  final List<({Appointment appointment, Client client})> rows;
  final int defaultMinutes;
  final String practitionerName;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final countLabel =
        rows.length == 1 ? '1 appointment' : '${rows.length} appointments';
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(
            title: 'Your agenda',
            link: _PanelLink(
              label: 'Open calendar →',
              onTap: () =>
                  ShellNavigation.maybeOf(context)?.goTo(DesktopDest.calendar),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                _agendaDateLabel(today),
                style: TextStyle(fontSize: 12, height: 1.5, color: c.inkMuted),
              ),
              const Spacer(),
              Text(
                countLabel,
                style: TextStyle(fontSize: 12, height: 1.5, color: c.inkMuted),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Divider(height: 1, color: c.border),
          if (rows.isEmpty) ...[
            const SizedBox(height: 18),
            Text(
              'No appointments scheduled for today.',
              style: TextStyle(fontSize: 13, height: 1.5, color: c.inkMuted),
            ),
          ] else ...[
            for (final row in rows) ...[
              const SizedBox(height: 18),
              _AgendaVisit(
                appointment: row.appointment,
                client: row.client,
                defaultMinutes: defaultMinutes,
                practitionerName: practitionerName,
              ),
            ],
            const SizedBox(height: 18),
            Text(
              '* Default duration when an end time is not set.',
              style: TextStyle(fontSize: 11, height: 1.5, color: c.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _AgendaVisit extends StatelessWidget {
  const _AgendaVisit({
    required this.appointment,
    required this.client,
    required this.defaultMinutes,
    required this.practitionerName,
  });

  final Appointment appointment;
  final Client client;
  final int defaultMinutes;
  final String practitionerName;

  int get _durationMins {
    final end = appointmentEffectiveEnd(
      appointment.startsAt,
      appointment.endsAt,
      defaultMinutes,
    );
    return end.difference(appointment.startsAt).inMinutes;
  }

  bool get _usedDefault => appointment.endsAt == null;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final avatar = clientAvatarColors(client, c);
    final phone = (client.phone ?? '').trim();
    final metaParts = <String>[
      if (phone.isNotEmpty) phone,
      if (practitionerName.isNotEmpty) practitionerName,
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 62,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatApptTime(appointment.startsAt),
                style: TextStyle(
                  fontSize: 18,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                  color: c.ink,
                ),
              ),
              Text(
                '$_durationMins min${_usedDefault ? '*' : ''}',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: c.inkMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: c.canvas,
              borderRadius: BorderRadius.circular(PelviRadius.md),
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: avatar.wash,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        clientInitials(client),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: avatar.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            clientDisplayName(client),
                            style: TextStyle(
                              fontSize: 17,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                              color: c.ink,
                            ),
                          ),
                          if (metaParts.isNotEmpty)
                            Text(
                              metaParts.join(' · '),
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: c.inkMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: c.pink50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        appointmentStatusLabel(appointment.status),
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                          color: c.pink700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Divider(height: 1, color: c.border),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      'Prepare for this visit',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: c.inkMuted,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () => openNoteForAppointment(
                        context,
                        appointmentId: appointment.id,
                        clientId: client.id,
                        noteDate: appointment.startsAt,
                      ),
                      icon: Icon(
                        Icons.edit_note_outlined,
                        size: 16,
                        color: c.pink700,
                      ),
                      label: Text(
                        'Start SOAP note',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.pink700,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: c.pink50,
                        foregroundColor: c.pink700,
                        elevation: 0,
                        minimumSize: const Size(0, 38),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(PelviRadius.sm),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DraftsPanel extends StatelessWidget {
  const _DraftsPanel({required this.drafts});

  final List<({Note note, Client client})> drafts;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(
            title: 'Open SOAP drafts',
            link: _PanelLink(
              label: 'View notes →',
              onTap: () => ShellNavigation.maybeOf(context)
                  ?.goTo(DesktopDest.soapNotes),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'CLIENT / NOTE DATE',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    color: c.inkMuted,
                  ),
                ),
              ),
              Text(
                'TEMPLATE',
                style: TextStyle(fontSize: 11, height: 1.5, color: c.inkMuted),
              ),
              const SizedBox(width: 16),
              Text(
                'ACTION',
                style: TextStyle(fontSize: 11, height: 1.5, color: c.inkMuted),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Divider(height: 1, color: c.border),
          if (drafts.isEmpty) ...[
            const SizedBox(height: 18),
            Text(
              'No open drafts.',
              style: TextStyle(fontSize: 13, height: 1.5, color: c.inkMuted),
            ),
          ] else
            for (final row in drafts) ...[
              const SizedBox(height: 18),
              _DraftRow(note: row.note, client: row.client),
            ],
        ],
      ),
    );
  }
}

class _DraftRow extends StatelessWidget {
  const _DraftRow({required this.note, required this.client});

  final Note note;
  final Client client;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final avatar = clientAvatarColors(client, c);
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: avatar.wash,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            clientInitials(client),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: avatar.ink,
            ),
          ),
        ),
        const SizedBox(width: 20),
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
                '${formatNoteDate(note.noteDate)} · No clinical text entered',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: c.inkMuted,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: c.purple50,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Blank',
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: c.purple700,
            ),
          ),
        ),
        const SizedBox(width: 16),
        OutlinedButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => NoteEditorScreen(noteId: note.id),
              ),
            );
          },
          style: OutlinedButton.styleFrom(
            backgroundColor: c.surface,
            side: BorderSide(color: c.border),
            minimumSize: const Size(0, 38),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PelviRadius.sm),
            ),
          ),
          child: Text(
            'Continue',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.ink,
            ),
          ),
        ),
      ],
    );
  }
}

class _RecallsPanel extends StatelessWidget {
  const _RecallsPanel({required this.count, required this.recallDays});

  final int count;
  final int recallDays;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final windowCopy = recallDays <= 0
        ? 'Recall is turned off in Practice settings.'
        : 'Review clients with no visit in the last $recallDays days, then choose who to follow up with.';
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(
            title: 'Client recalls',
            link: _PanelLink(
              label: 'Manage →',
              onTap: () => ShellNavigation.maybeOf(context)
                  ?.goTo(DesktopDest.clients),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 42,
                  height: 1,
                  color: c.pink700,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                count == 1 ? 'client in Due' : 'clients in Due',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: c.inkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            windowCopy,
            style: TextStyle(fontSize: 13, height: 1.5, color: c.inkMuted),
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => ShellNavigation.maybeOf(context)
                  ?.goTo(DesktopDest.clients),
              icon: Icon(Icons.people_outline, size: 16, color: c.pink700),
              label: Text(
                'Review Due clients',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.pink700,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: c.pink50,
                foregroundColor: c.pink700,
                elevation: 0,
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(PelviRadius.sm),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Divider(height: 1, color: c.border),
          const SizedBox(height: 18),
          Text(
            'Muted clients stay out of the Due list. Manage individual preferences in the client profile.',
            style: TextStyle(fontSize: 11, height: 1.5, color: c.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _UpNextPanel extends StatelessWidget {
  const _UpNextPanel({required this.next});

  final ({Appointment appointment, Client client})? next;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final row = next;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Up next',
            style: TextStyle(
              fontSize: 17,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: c.ink,
            ),
          ),
          if (row == null) ...[
            const SizedBox(height: 18),
            Text(
              'Nothing booked after today.',
              style: TextStyle(fontSize: 13, height: 1.5, color: c.inkMuted),
            ),
          ] else ...[
            const SizedBox(height: 18),
            Text(
              _upNextDayLabel(row.appointment.startsAt),
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: c.purple700,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Builder(
                  builder: (context) {
                    final avatar = clientAvatarColors(row.client, c);
                    return Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: avatar.wash,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        clientInitials(row.client),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: avatar.ink,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clientDisplayName(row.client),
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      '${formatApptTime(row.appointment.startsAt)} · ${appointmentStatusLabel(row.appointment.status)}',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: c.inkMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            Divider(height: 1, color: c.border),
            const SizedBox(height: 18),
            Text(
              'Review the profile and appointment history before opening a new note.',
              style: TextStyle(fontSize: 12, height: 1.5, color: c.inkMuted),
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ClientProfileScreen(clientId: row.client.id),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  backgroundColor: c.surface,
                  side: BorderSide(color: c.border),
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(PelviRadius.sm),
                  ),
                ),
                child: Text(
                  'Open client profile',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
