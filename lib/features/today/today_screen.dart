import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/empty_state.dart';
import '../appointments/appointment_agenda_row.dart';
import '../appointments/appointment_form_screen.dart';
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
            return const Center(
              child: CircularProgressIndicator(color: PelviColors.pink700),
            );
          }
          if (rows.isEmpty) {
            return Column(
              children: [
                const Expanded(
                  child: QuietEmptyState(
                    title: 'Nothing on today',
                    body:
                        'Your agenda will show here — appointments and open SOAP drafts for the day.',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    PelviSpace.page,
                    0,
                    PelviSpace.page,
                    PelviSpace.lg,
                  ),
                  child: DashedEmptyWell(
                    message: 'No appointments scheduled for today.',
                    ctaLabel: 'Add appointment',
                    onCta: () => _openNewAppointment(context),
                  ),
                ),
              ],
            );
          }

          return _TodayAgendaList(rows: rows);
        },
      ),
    );
  }
}

class _TodayAgendaList extends StatefulWidget {
  const _TodayAgendaList({required this.rows});

  final List<({Appointment appointment, Client client})> rows;

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
      // All past → end of list.
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
        _didInitialScroll = true;
      }
      return;
    }

    if (upcomingIndex == 0) {
      // First item is upcoming (all future or next is first) → stay at top.
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

    return ListView.separated(
      controller: _scroll,
      itemCount: widget.rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final row = widget.rows[index];
        final appt = row.appointment;
        final past = appt.startsAt.isBefore(now);

        Widget child = AppointmentAgendaRow(
          appointment: appt,
          client: row.client,
          past: past,
        );

        if (index == upcomingIndex) {
          child = KeyedSubtree(key: _upcomingKey, child: child);
        }
        return child;
      },
    );
  }
}
