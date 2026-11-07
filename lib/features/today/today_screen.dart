import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/theme.dart';
import '../appointments/appointment_form_screen.dart';
import '../clients/client_format.dart';
import '../notes/open_note.dart';
import '../notifications/notifications_sheet.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  void _openNewAppointment(BuildContext context) {
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          StreamBuilder<List<RecallDueEntry>>(
            stream: db.watchRecallInboxClients(),
            builder: (context, snap) {
              final count = snap.data?.length ?? 0;
              return NotificationBellButton(
                dueCount: count,
                onPressed: () => showNotificationsSheet(context),
              );
            },
          ),
          const SizedBox(width: PelviSpace.sm),
        ],
      ),
      body: StreamBuilder(
        stream: db.watchAppointmentsWithClientOnDay(today),
        builder: (context, snap) {
          final rows = snap.data;
          if (rows == null) {
            return Center(
              child: CircularProgressIndicator(color: PelviColors.of(context).pink700),
            );
          }
          return _TodayBody(
            rows: rows,
            onAdd: () => _openNewAppointment(context),
          );
        },
      ),
    );
  }
}

class _TodayBody extends StatelessWidget {
  const _TodayBody({required this.rows, required this.onAdd});

  final List<({Appointment appointment, Client client})> rows;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final count = rows.length;
    final countLabel =
        count == 1 ? '1 appointment' : '$count appointments';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PelviSpace.page,
            0,
            PelviSpace.page,
            0,
          ),
          child: Row(
            children: [
              Text(
                'YOUR AGENDA',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const Spacer(),
              Text(
                countLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 12,
                      height: 1.25,
                      letterSpacing: 0,
                    ),
              ),
            ],
          ),
        ),
        SizedBox(height: count == 0 ? 18 : 26),
        Expanded(
          child: count == 0
              ? _TodayEmpty(onAdd: onAdd)
              : _TodayAgendaList(rows: rows, onAdd: onAdd),
        ),
      ],
    );
  }
}

class _TodayEmpty extends StatelessWidget {
  const _TodayEmpty({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: PelviSpace.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 290),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 86,
                      height: 86,
                      decoration: BoxDecoration(
                        color: PelviColors.of(context).pink50,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.today_outlined,
                        size: 34,
                        color: PelviColors.of(context).pink700,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Nothing on today',
                      textAlign: TextAlign.center,
                      style: text.displayLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your agenda will show here — appointments and open SOAP drafts for the day.',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(
                        color: PelviColors.of(context).inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PelviSpace.page,
            0,
            PelviSpace.page,
            PelviSpace.lg,
          ),
          child: _EmptyAddPanel(onAdd: onAdd),
        ),
      ],
    );
  }
}

class _EmptyAddPanel extends StatelessWidget {
  const _EmptyAddPanel({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(PelviRadius.lg),
        splashColor: PelviColors.of(context).surfaceMuted,
        highlightColor: PelviColors.of(context).surfaceMuted,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: PelviColors.of(context).pink50,
            borderRadius: BorderRadius.circular(PelviRadius.lg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No appointments scheduled for today.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: PelviColors.of(context).inkMuted,
                      fontSize: 14,
                      height: 1.5,
                    ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 19),
                  label: const Text('Add appointment'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayAgendaList extends StatefulWidget {
  const _TodayAgendaList({required this.rows, required this.onAdd});

  final List<({Appointment appointment, Client client})> rows;
  final VoidCallback onAdd;

  @override
  State<_TodayAgendaList> createState() => _TodayAgendaListState();
}

class _TodayAgendaListState extends State<_TodayAgendaList> {
  final _scroll = ScrollController();
  final _upcomingKey = GlobalKey();
  bool _didInitialScroll = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleInitialScroll();
  }

  @override
  void didUpdateWidget(covariant _TodayAgendaList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_didInitialScroll) _scheduleInitialScroll();
  }

  void _scheduleInitialScroll() {
    if (_didInitialScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didInitialScroll) return;
      _scrollToUpcoming();
    });
  }

  void _scrollToUpcoming() {
    final now = DateTime.now();
    final upcomingIndex = widget.rows.indexWhere(
      (r) => !r.appointment.startsAt.isBefore(now),
    );

    if (upcomingIndex < 0) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
        _didInitialScroll = true;
      }
      return;
    }

    if (upcomingIndex == 0) {
      _didInitialScroll = true;
      return;
    }

    final ctx = _upcomingKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0,
      duration: Duration.zero,
    );
    _didInitialScroll = true;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final upcomingIndex = widget.rows.indexWhere(
      (r) => !r.appointment.startsAt.isBefore(now),
    );

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(horizontal: PelviSpace.page),
            itemCount: widget.rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final row = widget.rows[index];
              final past = row.appointment.startsAt.isBefore(now);
              Widget child = _TodayAppointmentCard(
                appointment: row.appointment,
                client: row.client,
                past: past,
              );
              if (index == upcomingIndex) {
                child = KeyedSubtree(key: _upcomingKey, child: child);
              }
              return child;
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PelviSpace.page,
            PelviSpace.md,
            PelviSpace.page,
            PelviSpace.lg,
          ),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: widget.onAdd,
              style: FilledButton.styleFrom(
                backgroundColor: PelviColors.of(context).pink50,
                foregroundColor: PelviColors.of(context).pink700,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(PelviRadius.md),
                ),
              ),
              icon: const Icon(Icons.add, size: 19),
              label: const Text('Add appointment'),
            ),
          ),
        ),
      ],
    );
  }
}

class _TodayAppointmentCard extends StatelessWidget {
  const _TodayAppointmentCard({
    required this.appointment,
    required this.client,
    required this.past,
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
    final text = Theme.of(context).textTheme;
    final c = PelviColors.of(context);
    final ink = past ? c.inkMuted : c.ink;
    final decoration = past ? TextDecoration.lineThrough : TextDecoration.none;
    final status = appointment.status;
    final pillFg = past ? c.inkMuted : _statusPillForeground(status, c);
    final pillBg = past ? c.surfaceMuted : _statusPillBackground(status, c);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 49,
            child: Column(
              children: [
                const SizedBox(height: 20),
                Text(
                  formatApptTime(appointment.startsAt),
                  style: text.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    height: 1.2,
                    color: ink,
                    decoration: decoration,
                    decorationColor: ink,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Center(
                    child: Container(
                      width: 1,
                      color: PelviColors.of(context).border,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Material(
              color: PelviColors.of(context).surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(PelviRadius.lg),
                side: BorderSide(color: PelviColors.of(context).border),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _openEdit(context),
                splashColor: PelviColors.of(context).surfaceMuted,
                highlightColor: PelviColors.of(context).surfaceMuted,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clientDisplayName(client),
                        style: text.titleMedium?.copyWith(
                          fontSize: 20,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.4,
                          color: ink,
                          decoration: decoration,
                          decorationColor: ink,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: pillBg,
                          borderRadius: BorderRadius.circular(PelviRadius.sm),
                        ),
                        child: Text(
                          appointmentStatusLabel(status),
                          style: text.labelMedium?.copyWith(
                            fontSize: 11,
                            height: 1.2,
                            letterSpacing: 0,
                            fontWeight: FontWeight.w500,
                            color: pillFg,
                          ),
                        ),
                      ),
                      const SizedBox(height: 17),
                      const Divider(height: 1),
                      const SizedBox(height: 14),
                      InkWell(
                        onTap: () => _openSoap(context),
                        child: Row(
                          children: [
                            Icon(
                              Icons.edit_note_outlined,
                              size: 17,
                              color: past
                                  ? PelviColors.of(context).inkMuted
                                  : PelviColors.of(context).purple700,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                'Note',
                                style: text.labelLarge?.copyWith(
                                  fontSize: 13,
                                  height: 1.2,
                                  fontWeight: FontWeight.w500,
                                  color: past
                                      ? PelviColors.of(context).inkMuted
                                      : PelviColors.of(context).purple700,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: past
                                  ? PelviColors.of(context).inkMuted
                                  : PelviColors.of(context).purple400,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _statusPillForeground(AppointmentStatus status, PelviPalette c) {
  return switch (status) {
    AppointmentStatus.scheduled => c.pink700,
    AppointmentStatus.completed => c.pink700,
    AppointmentStatus.cancelled => c.inkMuted,
    AppointmentStatus.noShow => c.purple700,
  };
}

Color _statusPillBackground(AppointmentStatus status, PelviPalette c) {
  return switch (status) {
    AppointmentStatus.scheduled => c.pink50,
    AppointmentStatus.completed => c.pink50,
    AppointmentStatus.cancelled => c.surfaceMuted,
    AppointmentStatus.noShow => c.purple50,
  };
}
