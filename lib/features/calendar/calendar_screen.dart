import 'package:flutter/material.dart';

import '../../data/database_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/empty_state.dart';
import '../appointments/appointment_agenda_row.dart';
import '../appointments/appointment_form_screen.dart';
import '../notes/note_format.dart';

const _monthNames = [
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

const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = _dateOnly(now);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      if (_selected.year != _month.year || _selected.month != _month.month) {
        _selected = DateTime(_month.year, _month.month, 1);
      }
    });
  }

  void _openNewAppointment() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppointmentFormScreen(initialDay: _selected),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = AppDatabaseProvider.of(context);
    final text = Theme.of(context).textTheme;
    final today = _dateOnly(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      body: StreamBuilder(
        stream: db.watchAppointmentsWithClientOnDay(_selected),
        builder: (context, daySnap) {
          final rows = daySnap.data;
          final now = DateTime.now();
          final isToday = _sameDay(_selected, today);

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    PelviSpace.sm,
                    PelviSpace.md,
                    PelviSpace.sm,
                    PelviSpace.sm,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous month',
                        onPressed: () => _shiftMonth(-1),
                        icon: Icon(
                          Icons.chevron_left,
                          color: PelviColors.of(context).ink,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${_monthNames[_month.month - 1]} ${_month.year}',
                          textAlign: TextAlign.center,
                          style: text.titleLarge?.copyWith(fontSize: 18),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next month',
                        onPressed: () => _shiftMonth(1),
                        icon: Icon(
                          Icons.chevron_right,
                          color: PelviColors.of(context).ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: PelviSpace.page),
                  child: Row(
                    children: [
                      for (final letter in _weekdayLetters)
                        Expanded(
                          child: Center(
                            child: Text(letter, style: text.labelMedium),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: PelviSpace.xs)),
              SliverToBoxAdapter(
                child: StreamBuilder<Map<DateTime, int>>(
                  stream: db.watchAppointmentCountsForMonth(_month),
                  builder: (context, snap) {
                    final counts = snap.data ?? const <DateTime, int>{};
                    return _MonthGrid(
                      month: _month,
                      selected: _selected,
                      today: today,
                      counts: counts,
                      onSelect: (day) => setState(() => _selected = day),
                    );
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    PelviSpace.page,
                    PelviSpace.sm,
                    PelviSpace.page,
                    PelviSpace.md,
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: PelviSpace.md,
                      vertical: PelviSpace.sm + 4,
                    ),
                    decoration: BoxDecoration(
                      color: PelviColors.of(context).surfaceMuted,
                      borderRadius: BorderRadius.circular(PelviRadius.md),
                      border: Border.all(color: PelviColors.of(context).border),
                    ),
                    child: Text(
                      'Tap a day to see appointments',
                      style: text.labelMedium,
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: Divider(height: 1)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    PelviSpace.page,
                    PelviSpace.md,
                    PelviSpace.page,
                    PelviSpace.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          formatNoteDate(_selected),
                          style: text.labelLarge,
                        ),
                      ),
                      TextButton(
                        onPressed: _openNewAppointment,
                        style: TextButton.styleFrom(
                          foregroundColor: PelviColors.of(context).pink700,
                        ),
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ),
              ),
              if (rows == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: PelviColors.of(context).pink700,
                    ),
                  ),
                )
              else if (rows.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                    PelviSpace.page,
                    PelviSpace.sm,
                    PelviSpace.page,
                    PelviSpace.lg,
                  ),
                    child: DashedEmptyWell(
                      message: 'No appointments this day.',
                      ctaLabel: 'Add appointment',
                      onCta: _openNewAppointment,
                    ),
                  ),
                )
              else
                SliverList.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final past =
                        isToday && row.appointment.startsAt.isBefore(now);
                    return AppointmentAgendaRow(
                      appointment: row.appointment,
                      client: row.client,
                      past: past,
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.today,
    required this.counts,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final DateTime today;
  final Map<DateTime, int> counts;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final first = DateTime(month.year, month.month);
    // Monday-first: weekday 1 → col 0.
    final leading = first.weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cellCount = ((leading + daysInMonth + 6) ~/ 7) * 7;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PelviSpace.page),
      child: Column(
        children: [
          for (var row = 0; row < cellCount ~/ 7; row++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final index = row * 7 + col;
                        final dayNum = index - leading + 1;
                        if (dayNum < 1 || dayNum > daysInMonth) {
                          return const SizedBox(height: 52);
                        }
                        final day = DateTime(month.year, month.month, dayNum);
                        final count = counts[day] ?? 0;
                        final isSelected = _sameDay(day, selected);
                        final isToday = _sameDay(day, today);

                        return Padding(
                          padding: const EdgeInsets.all(2),
                          child: Material(
                            color: isSelected
                                ? PelviColors.of(context).pink50
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(PelviRadius.md),
                            child: InkWell(
                              onTap: () => onSelect(day),
                              borderRadius:
                                  BorderRadius.circular(PelviRadius.md),
                              splashColor: PelviColors.of(context).surfaceMuted,
                              highlightColor: PelviColors.of(context).surfaceMuted,
                              child: SizedBox(
                                height: 52,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '$dayNum',
                                      style: text.labelLarge?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: isSelected
                                            ? PelviColors.of(context).pink700
                                            : PelviColors.of(context).ink,
                                        decoration: isToday && !isSelected
                                            ? TextDecoration.underline
                                            : TextDecoration.none,
                                        decorationColor: PelviColors.of(context).inkMuted,
                                      ),
                                    ),
                                    Text(
                                      count > 0 ? '$count' : ' ',
                                      style: text.labelSmall?.copyWith(
                                        fontSize: 11,
                                        height: 1.2,
                                        fontWeight: FontWeight.w500,
                                        color: count > 0
                                            ? PelviColors.of(context).inkMuted
                                            : Colors.transparent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
