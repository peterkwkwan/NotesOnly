import 'package:flutter/material.dart';

import '../../data/appointment_overlap.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/show_snack.dart';
import '../appointments/appointment_form_screen.dart';
import '../clients/client_format.dart';
import '../notes/note_format.dart';
import '../shell/desktop_chrome.dart';

enum _CalView { day, week, month }

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

const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _mondayOf(DateTime d) {
  final day = _dateOnly(d);
  return day.subtract(Duration(days: day.weekday - 1));
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int _parseHour(String hhmm) {
  final parts = hhmm.split(':');
  return int.tryParse(parts.first) ?? 9;
}

String _hhmm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _weekRangeLabel(DateTime monday) {
  final sunday = monday.add(const Duration(days: 6));
  if (monday.month == sunday.month) {
    return '${monday.day}–${sunday.day} ${_monthNames[monday.month - 1]} ${monday.year}';
  }
  if (monday.year == sunday.year) {
    return '${monday.day} ${_monthNames[monday.month - 1]} – '
        '${sunday.day} ${_monthNames[sunday.month - 1]} ${monday.year}';
  }
  return '${monday.day} ${_monthNames[monday.month - 1]} ${monday.year} – '
      '${sunday.day} ${_monthNames[sunday.month - 1]} ${sunday.year}';
}

/// Figma `NotesOnly · Calendar` page body (desktop shell supplies chrome).
class WebCalendarPage extends StatefulWidget {
  const WebCalendarPage({super.key});

  @override
  State<WebCalendarPage> createState() => _WebCalendarPageState();
}

class _WebCalendarPageState extends State<WebCalendarPage> {
  late DateTime _anchor; // week Monday for week view; day for day; month for month
  late DateTime _selected;
  _CalView _view = _CalView.week;
  bool _panelOpen = true;
  late TimeOfDay _starts;
  late TimeOfDay _ends;
  int? _clientId;
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selected = _dateOnly(now);
    _anchor = _mondayOf(now);
    _starts = nextWholeHour(now);
    _ends = TimeOfDay(hour: (_starts.hour + 1) % 24, minute: _starts.minute);
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  DateTime get _rangeStart {
    return switch (_view) {
      _CalView.day => _selected,
      _CalView.week => _mondayOf(_anchor),
      _CalView.month => DateTime(_anchor.year, _anchor.month),
    };
  }

  DateTime get _rangeEnd {
    return switch (_view) {
      _CalView.day => _selected.add(const Duration(days: 1)),
      _CalView.week => _mondayOf(_anchor).add(const Duration(days: 7)),
      _CalView.month => DateTime(_anchor.year, _anchor.month + 1),
    };
  }

  List<DateTime> get _visibleDays {
    return switch (_view) {
      _CalView.day => [_selected],
      _CalView.week => [
          for (var i = 0; i < 7; i++)
            _mondayOf(_anchor).add(Duration(days: i)),
        ],
      _CalView.month => const [],
    };
  }

  void _goToday() {
    final now = DateTime.now();
    setState(() {
      _selected = _dateOnly(now);
      _anchor = _view == _CalView.month
          ? DateTime(now.year, now.month)
          : _mondayOf(now);
      _starts = nextWholeHour(now);
      _ends = TimeOfDay(hour: (_starts.hour + 1) % 24, minute: _starts.minute);
    });
  }

  void _shift(int delta) {
    setState(() {
      switch (_view) {
        case _CalView.day:
          _selected = _selected.add(Duration(days: delta));
          _anchor = _mondayOf(_selected);
        case _CalView.week:
          _anchor = _mondayOf(_anchor).add(Duration(days: 7 * delta));
          _selected = _anchor;
        case _CalView.month:
          _anchor = DateTime(_anchor.year, _anchor.month + delta);
          _selected = DateTime(_anchor.year, _anchor.month, 1);
      }
    });
  }

  void _openPanel({DateTime? day, TimeOfDay? starts}) {
    final d = day ?? _selected;
    final s = starts ?? nextWholeHour();
    setState(() {
      _panelOpen = true;
      _selected = _dateOnly(d);
      _starts = s;
      _ends = TimeOfDay(hour: (s.hour + 1) % 24, minute: s.minute);
      _clientId = null;
      _notesCtrl.clear();
    });
  }

  void _closePanel() {
    setState(() => _panelOpen = false);
  }

  Future<void> _save(AppDatabase db, int defaultMins) async {
    final clientId = _clientId;
    if (clientId == null || _saving) return;
    final startsAt = DateTime(
      _selected.year,
      _selected.month,
      _selected.day,
      _starts.hour,
      _starts.minute,
    );
    var endsAt = DateTime(
      _selected.year,
      _selected.month,
      _selected.day,
      _ends.hour,
      _ends.minute,
    );
    if (!endsAt.isAfter(startsAt)) {
      endsAt = startsAt.add(Duration(minutes: defaultMins));
    }
    setState(() => _saving = true);
    try {
      await db.insertAppointment(
        clientId: clientId,
        startsAt: startsAt,
        endsAt: endsAt,
        notes: _notesCtrl.text,
      );
      if (!mounted) return;
      setState(() {
        _panelOpen = false;
        _clientId = null;
        _notesCtrl.clear();
      });
    } on AppointmentConflictException catch (e) {
      if (!mounted) return;
      showPelviSnackBar(
        context,
        appointmentConflictCopy(
          clientName: clientDisplayName(e.client),
          startsAt: e.appointment.startsAt,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = AppDatabaseProvider.of(context);
    final c = PelviColors.of(context);

    return ColoredBox(
      color: c.canvas,
      child: StreamBuilder<String?>(
        stream: db.watchPractitionerName(),
        builder: (context, nameSnap) {
          return StreamBuilder<int>(
            stream: db.watchDefaultAppointmentMinutes(),
            builder: (context, minsSnap) {
              return StreamBuilder<(String, String)>(
                stream: db.watchClinicHours(),
                builder: (context, hoursSnap) {
                  return StreamBuilder<String>(
                    stream: db.watchTimezone(),
                    builder: (context, tzSnap) {
                      return StreamBuilder(
                        stream: db.watchAppointmentsWithClientInRange(
                          _rangeStart,
                          _rangeEnd,
                        ),
                        builder: (context, apptSnap) {
                          final practitioner =
                              (nameSnap.data ?? '').trim();
                          final defaultMins = minsSnap.data ?? 60;
                          final hours = hoursSnap.data ??
                              (
                                AppDatabase.defaultClinicHoursStart,
                                AppDatabase.defaultClinicHoursEnd,
                              );
                          final startHour = _parseHour(hours.$1);
                          final endHour = _parseHour(hours.$2);
                          final tz = tzSnap.data ??
                              AppDatabase.defaultTimezone;
                          final rows = apptSnap.data ?? const [];

                          return LayoutBuilder(
                            builder: (context, constraints) {
                              return SingleChildScrollView(
                                padding: const EdgeInsets.all(32),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: constraints.maxHeight - 64,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _Header(
                                        subtitleMonth: _view == _CalView.month
                                            ? _anchor
                                            : _selected,
                                        onToday: _goToday,
                                        onAdd: () => _openPanel(day: _selected),
                                      ),
                                      const SizedBox(height: 26),
                                      _Controls(
                                        navLabel: switch (_view) {
                                          _CalView.day =>
                                            formatNoteDate(_selected),
                                          _CalView.week =>
                                            _weekRangeLabel(
                                                _mondayOf(_anchor)),
                                          _CalView.month =>
                                            '${_monthNames[_anchor.month - 1]} ${_anchor.year}',
                                        },
                                        practitioner: practitioner.isEmpty
                                            ? 'Practitioner'
                                            : practitioner,
                                        view: _view,
                                        onPrev: () => _shift(-1),
                                        onNext: () => _shift(1),
                                        onView: (v) => setState(() {
                                          _view = v;
                                          if (v == _CalView.week) {
                                            _anchor = _mondayOf(_selected);
                                          } else if (v == _CalView.month) {
                                            _anchor = DateTime(
                                              _selected.year,
                                              _selected.month,
                                            );
                                          }
                                        }),
                                      ),
                                      const SizedBox(height: 26),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: _view == _CalView.month
                                                ? _MonthPanel(
                                                    month: _anchor,
                                                    selected: _selected,
                                                    rows: rows,
                                                    onSelect: (day) {
                                                      setState(() {
                                                        _selected = day;
                                                        _view = _CalView.day;
                                                        _anchor =
                                                            _mondayOf(day);
                                                      });
                                                      _openPanel(day: day);
                                                    },
                                                  )
                                                : _WeekSchedule(
                                                    days: _visibleDays,
                                                    selected: _selected,
                                                    rows: rows,
                                                    startHour: startHour,
                                                    endHour: endHour,
                                                    defaultMins: defaultMins,
                                                    draft: _panelOpen
                                                        ? (
                                                            day: _selected,
                                                            starts: _starts,
                                                          )
                                                        : null,
                                                    onSelectDay: (day) =>
                                                        setState(() =>
                                                            _selected = day),
                                                    onTapSlot: (day, time) =>
                                                        _openPanel(
                                                      day: day,
                                                      starts: time,
                                                    ),
                                                  ),
                                          ),
                                          if (_panelOpen) ...[
                                            const SizedBox(width: 20),
                                            SizedBox(
                                              width: 330,
                                              child: _NewAppointmentPanel(
                                                selected: _selected,
                                                starts: _starts,
                                                ends: _ends,
                                                clientId: _clientId,
                                                notesCtrl: _notesCtrl,
                                                practitioner: practitioner,
                                                defaultMins: defaultMins,
                                                timezone: tz,
                                                saving: _saving,
                                                dayRows: [
                                                  for (final r in rows)
                                                    if (_sameDay(
                                                      r.appointment.startsAt,
                                                      _selected,
                                                    ))
                                                      r,
                                                ],
                                                onClose: _closePanel,
                                                onCancel: _closePanel,
                                                onPickClient: (id) =>
                                                    setState(
                                                        () => _clientId = id),
                                                onPickDate: () async {
                                                  final picked =
                                                      await showDatePicker(
                                                    context: context,
                                                    initialDate: _selected,
                                                    firstDate:
                                                        DateTime(2000),
                                                    lastDate:
                                                        DateTime(2100),
                                                  );
                                                  if (picked != null) {
                                                    setState(() {
                                                      _selected =
                                                          _dateOnly(picked);
                                                      if (_view ==
                                                          _CalView.week) {
                                                        _anchor = _mondayOf(
                                                            picked);
                                                      }
                                                    });
                                                  }
                                                },
                                                onPickStarts: () async {
                                                  final picked =
                                                      await showTimePicker(
                                                    context: context,
                                                    initialTime: _starts,
                                                  );
                                                  if (picked != null) {
                                                    setState(() {
                                                      _starts = picked;
                                                      _ends = TimeOfDay(
                                                        hour: (picked.hour +
                                                                1) %
                                                            24,
                                                        minute:
                                                            picked.minute,
                                                      );
                                                    });
                                                  }
                                                },
                                                onPickEnds: () async {
                                                  final picked =
                                                      await showTimePicker(
                                                    context: context,
                                                    initialTime: _ends,
                                                  );
                                                  if (picked != null) {
                                                    setState(
                                                        () => _ends = picked);
                                                  }
                                                },
                                                onSave: () =>
                                                    _save(db, defaultMins),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
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
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.subtitleMonth,
    required this.onToday,
    required this.onAdd,
  });

  final DateTime subtitleMonth;
  final VoidCallback onToday;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DesktopBreadcrumb(),
              Text(
                'Calendar',
                style: TextStyle(
                  fontSize: 29,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              Text(
                '${_monthNames[subtitleMonth.month - 1]} ${subtitleMonth.year}'
                ' · Plan the week without losing the detail',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: c.inkMuted,
                ),
              ),
            ],
          ),
        ),
        OutlinedButton(
          onPressed: onToday,
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
            'Today',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.ink,
            ),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: onAdd,
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

class _Controls extends StatelessWidget {
  const _Controls({
    required this.navLabel,
    required this.practitioner,
    required this.view,
    required this.onPrev,
    required this.onNext,
    required this.onView,
  });

  final String navLabel;
  final String practitioner;
  final _CalView view;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<_CalView> onView;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Row(
      children: [
        IconButton(
          onPressed: onPrev,
          icon: Icon(Icons.chevron_left, size: 18, color: c.ink),
          visualDensity: VisualDensity.compact,
          tooltip: 'Previous',
        ),
        Text(
          navLabel,
          style: TextStyle(
            fontSize: 18,
            height: 1.5,
            fontWeight: FontWeight.w600,
            color: c.ink,
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: Icon(Icons.chevron_right, size: 18, color: c.ink),
          visualDensity: VisualDensity.compact,
          tooltip: 'Next',
        ),
        const Spacer(),
        _PillButton(
          label: practitioner,
          icon: Icons.keyboard_arrow_down,
          onTap: null,
        ),
        const SizedBox(width: 10),
        _PillButton(
          label: 'Day',
          selected: view == _CalView.day,
          onTap: () => onView(_CalView.day),
        ),
        const SizedBox(width: 10),
        _PillButton(
          label: 'Week',
          selected: view == _CalView.week,
          onTap: () => onView(_CalView.week),
        ),
        const SizedBox(width: 10),
        _PillButton(
          label: 'Month',
          selected: view == _CalView.month,
          onTap: () => onView(_CalView.month),
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: c.ink),
          const SizedBox(width: 8),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? c.pink700 : c.ink,
          ),
        ),
      ],
    );
    return Material(
      color: selected ? c.pink50 : c.surface,
      borderRadius: BorderRadius.circular(PelviRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PelviRadius.sm),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PelviRadius.sm),
            border: selected
                ? null
                : Border.all(color: c.border),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _WeekSchedule extends StatefulWidget {
  const _WeekSchedule({
    required this.days,
    required this.selected,
    required this.rows,
    required this.startHour,
    required this.endHour,
    required this.defaultMins,
    required this.draft,
    required this.onSelectDay,
    required this.onTapSlot,
  });

  final List<DateTime> days;
  final DateTime selected;
  final List<({Appointment appointment, Client client})> rows;
  final int startHour;
  final int endHour;
  final int defaultMins;
  final ({DateTime day, TimeOfDay starts})? draft;
  final ValueChanged<DateTime> onSelectDay;
  final void Function(DateTime day, TimeOfDay time) onTapSlot;

  static const _hourH = 66.0;
  static const _gutter = 52.0;
  static const _dayStart = 0;
  static const _dayEnd = 24;

  @override
  State<_WeekSchedule> createState() => _WeekScheduleState();

  static bool _inDayHours(DateTime starts) {
    final mins = starts.hour * 60 + starts.minute;
    return mins >= _dayStart * 60 && mins < _dayEnd * 60;
  }

  static Widget _eventCard({
    required BuildContext context,
    required List<DateTime> days,
    required double gutter,
    required double colW,
    required int startHour,
    required double hourH,
    required int defaultMins,
    required ({Appointment appointment, Client client}) row,
  }) {
    final c = PelviColors.of(context);
    final dayIndex = days.indexWhere(
      (d) => _sameDay(d, row.appointment.startsAt),
    );
    if (dayIndex < 0) return const SizedBox.shrink();
    final start = row.appointment.startsAt;
    final end = appointmentEffectiveEnd(
      start,
      row.appointment.endsAt,
      defaultMins,
    );
    final top =
        ((start.hour - startHour) * 60 + start.minute) / 60.0 * hourH;
    final height =
        (end.difference(start).inMinutes / 60.0 * hourH).clamp(44.0, 400.0);
    return Positioned(
      left: gutter + dayIndex * colW + 4,
      top: top,
      width: colW - 8,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.pink50,
            border: Border.all(color: c.pink400.withValues(alpha: 0.45)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: c.pink400),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatApptTime(start),
                        style: TextStyle(fontSize: 10, color: c.pink700),
                      ),
                      Text(
                        clientDisplayName(row.client),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: c.pink700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _draftCard({
    required BuildContext context,
    required List<DateTime> days,
    required double gutter,
    required double colW,
    required int startHour,
    required int endHour,
    required double hourH,
    required ({DateTime day, TimeOfDay starts}) draft,
  }) {
    final c = PelviColors.of(context);
    final dayIndex = days.indexWhere((d) => _sameDay(d, draft.day));
    if (dayIndex < 0) return const SizedBox.shrink();
    final mins = draft.starts.hour * 60 + draft.starts.minute;
    if (mins < startHour * 60 || mins >= endHour * 60) {
      return const SizedBox.shrink();
    }
    final top =
        ((draft.starts.hour - startHour) * 60 + draft.starts.minute) /
            60.0 *
            hourH;
    // shortcut: solid border stands in for Figma dashed slot, upgrade if design QA cares
    return Positioned(
      left: gutter + dayIndex * colW + 4,
      top: top,
      width: colW - 8,
      height: hourH,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: c.pink50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c.pink400),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _hhmm(draft.starts),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: c.pink700,
              ),
            ),
            Text(
              'New booking',
              style: TextStyle(fontSize: 10, color: c.pink700),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekScheduleState extends State<_WeekSchedule> {
  late final ScrollController _timeScroll;

  @override
  void initState() {
    super.initState();
    // Land on clinic hours; full 0–24 grid stays reachable by scroll.
    _timeScroll = ScrollController(
      initialScrollOffset: widget.startHour.clamp(0, 23) * _WeekSchedule._hourH,
    );
  }

  @override
  void dispose() {
    _timeScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final days = widget.days;
    final selected = widget.selected;
    final rows = widget.rows;
    final clinicStart = widget.startHour.clamp(0, 24);
    final clinicEnd = widget.endHour.clamp(clinicStart + 1, 24);
    final hours = _WeekSchedule._dayEnd - _WeekSchedule._dayStart;
    final gridH = hours * _WeekSchedule._hourH;
    final viewportH =
        (clinicEnd - clinicStart).clamp(1, hours) * _WeekSchedule._hourH;
    final today = _dateOnly(DateTime.now());

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 72,
            child: Row(
              children: [
                SizedBox(
                  width: _WeekSchedule._gutter,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Device',
                        style: TextStyle(fontSize: 9, color: c.inkMuted),
                      ),
                      Text(
                        'clock',
                        style: TextStyle(fontSize: 9, color: c.inkMuted),
                      ),
                    ],
                  ),
                ),
                for (final day in days)
                  Expanded(
                    child: _DayHeading(
                      day: day,
                      selected: _sameDay(day, selected),
                      today: _sameDay(day, today),
                      bookingCount: rows
                          .where((r) =>
                              _sameDay(r.appointment.startsAt, day))
                          .length,
                      onTap: () => widget.onSelectDay(day),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: viewportH,
            child: SingleChildScrollView(
              controller: _timeScroll,
              child: SizedBox(
                height: gridH,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final colW = (constraints.maxWidth -
                            _WeekSchedule._gutter) /
                        days.length;
                    return Stack(
                      children: [
                        // Clinic-hours band stays emphasized; off-hours stay reachable.
                        Positioned(
                          left: _WeekSchedule._gutter,
                          right: 0,
                          top: 0,
                          height: clinicStart * _WeekSchedule._hourH,
                          child: ColoredBox(
                            color: c.surfaceMuted.withValues(alpha: 0.55),
                          ),
                        ),
                        Positioned(
                          left: _WeekSchedule._gutter,
                          right: 0,
                          top: clinicEnd * _WeekSchedule._hourH,
                          bottom: 0,
                          child: ColoredBox(
                            color: c.surfaceMuted.withValues(alpha: 0.55),
                          ),
                        ),
                        for (var i = 0; i <= hours * 2; i++)
                          Positioned(
                            left: _WeekSchedule._gutter,
                            right: 0,
                            top: i * (_WeekSchedule._hourH / 2),
                            child: Container(
                              height: 1,
                              color: i.isEven ? c.border : c.surfaceMuted,
                            ),
                          ),
                        for (var h = 0; h <= hours; h++)
                          Positioned(
                            left: 8,
                            top: h * _WeekSchedule._hourH + 4,
                            child: Text(
                              '${_WeekSchedule._dayStart + h}:00',
                              style: TextStyle(
                                fontSize: 10,
                                color: c.inkMuted,
                              ),
                            ),
                          ),
                        for (var i = 0; i < days.length; i++)
                          Positioned(
                            left: _WeekSchedule._gutter + i * colW,
                            top: 0,
                            width: colW,
                            height: gridH,
                            child: _DayColumn(
                              day: days[i],
                              startHour: _WeekSchedule._dayStart,
                              hourH: _WeekSchedule._hourH,
                              weekendTint:
                                  days[i].weekday == DateTime.saturday
                                      ? c.pink50.withValues(alpha: 0.35)
                                      : days[i].weekday == DateTime.sunday
                                          ? c.purple50
                                              .withValues(alpha: 0.55)
                                          : null,
                              onTapSlot: (time) =>
                                  widget.onTapSlot(days[i], time),
                            ),
                          ),
                        for (final row in rows)
                          if (_WeekSchedule._inDayHours(
                            row.appointment.startsAt,
                          ))
                            _WeekSchedule._eventCard(
                              context: context,
                              days: days,
                              gutter: _WeekSchedule._gutter,
                              colW: colW,
                              startHour: _WeekSchedule._dayStart,
                              hourH: _WeekSchedule._hourH,
                              defaultMins: widget.defaultMins,
                              row: row,
                            ),
                        if (widget.draft != null)
                          _WeekSchedule._draftCard(
                            context: context,
                            days: days,
                            gutter: _WeekSchedule._gutter,
                            colW: colW,
                            startHour: _WeekSchedule._dayStart,
                            endHour: _WeekSchedule._dayEnd,
                            hourH: _WeekSchedule._hourH,
                            draft: widget.draft!,
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
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
                      'Scheduled',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: c.pink700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Text(
                    rows.isEmpty
                        ? 'No appointments in this view.'
                        : '${rows.length} appointment${rows.length == 1 ? '' : 's'} shown.',
                    style: TextStyle(fontSize: 10, color: c.inkMuted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayHeading extends StatelessWidget {
  const _DayHeading({
    required this.day,
    required this.selected,
    required this.today,
    required this.bookingCount,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool today;
  final int bookingCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final weekend = day.weekday == DateTime.saturday;
    final sunday = day.weekday == DateTime.sunday;
    Color? bg;
    if (selected) {
      bg = c.pink50;
    } else if (weekend) {
      bg = c.pink50.withValues(alpha: 0.55);
    } else if (sunday) {
      bg = c.purple50;
    }
    final accent = selected ? c.pink700 : c.ink;
    return Material(
      color: bg ?? c.surface,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _weekdayShort[day.weekday - 1],
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: selected ? c.pink700 : c.inkMuted,
              ),
            ),
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: accent,
                decoration: today && !selected
                    ? TextDecoration.underline
                    : TextDecoration.none,
                decorationColor: c.inkMuted,
              ),
            ),
            if (bookingCount > 0 && !selected)
              Text(
                '$bookingCount booking${bookingCount == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 9, color: c.purple700),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.day,
    required this.startHour,
    required this.hourH,
    required this.weekendTint,
    required this.onTapSlot,
  });

  final DateTime day;
  final int startHour;
  final double hourH;
  final Color? weekendTint;
  final ValueChanged<TimeOfDay> onTapSlot;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: weekendTint,
        border: Border(left: BorderSide(color: c.border)),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          final slot = (details.localPosition.dy / (hourH / 2)).floor();
          final totalMins = startHour * 60 + slot * 30;
          onTapSlot(TimeOfDay(hour: totalMins ~/ 60, minute: totalMins % 60));
        },
      ),
    );
  }
}

class _MonthPanel extends StatelessWidget {
  const _MonthPanel({
    required this.month,
    required this.selected,
    required this.rows,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final List<({Appointment appointment, Client client})> rows;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final counts = <DateTime, int>{};
    for (final r in rows) {
      final d = _dateOnly(r.appointment.startsAt);
      counts[d] = (counts[d] ?? 0) + 1;
    }
    final first = DateTime(month.year, month.month);
    final leading = first.weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cellCount = ((leading + daysInMonth + 6) ~/ 7) * 7;
    final today = _dateOnly(DateTime.now());

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final w in _weekdayShort)
                Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: c.inkMuted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
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
                          return const SizedBox(height: 56);
                        }
                        final day =
                            DateTime(month.year, month.month, dayNum);
                        final isSelected = _sameDay(day, selected);
                        final isToday = _sameDay(day, today);
                        final count = counts[day] ?? 0;
                        return Padding(
                          padding: const EdgeInsets.all(2),
                          child: Material(
                            color: isSelected ? c.pink50 : Colors.transparent,
                            borderRadius:
                                BorderRadius.circular(PelviRadius.sm),
                            child: InkWell(
                              onTap: () => onSelect(day),
                              borderRadius:
                                  BorderRadius.circular(PelviRadius.sm),
                              child: SizedBox(
                                height: 56,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '$dayNum',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: isSelected
                                            ? c.pink700
                                            : c.ink,
                                        decoration: isToday && !isSelected
                                            ? TextDecoration.underline
                                            : null,
                                      ),
                                    ),
                                    Text(
                                      count > 0 ? '$count' : ' ',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: count > 0
                                            ? c.inkMuted
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

class _NewAppointmentPanel extends StatelessWidget {
  const _NewAppointmentPanel({
    required this.selected,
    required this.starts,
    required this.ends,
    required this.clientId,
    required this.notesCtrl,
    required this.practitioner,
    required this.defaultMins,
    required this.timezone,
    required this.saving,
    required this.dayRows,
    required this.onClose,
    required this.onCancel,
    required this.onPickClient,
    required this.onPickDate,
    required this.onPickStarts,
    required this.onPickEnds,
    required this.onSave,
  });

  final DateTime selected;
  final TimeOfDay starts;
  final TimeOfDay ends;
  final int? clientId;
  final TextEditingController notesCtrl;
  final String practitioner;
  final int defaultMins;
  final String timezone;
  final bool saving;
  final List<({Appointment appointment, Client client})> dayRows;
  final VoidCallback onClose;
  final VoidCallback onCancel;
  final ValueChanged<int> onPickClient;
  final VoidCallback onPickDate;
  final VoidCallback onPickStarts;
  final VoidCallback onPickEnds;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final db = AppDatabaseProvider.of(context);
    final canSave = clientId != null && !saving;
    final hint = dayRows.isEmpty
        ? '${formatNoteDate(selected).split(',').first}, '
            '${selected.day} ${_monthNames[selected.month - 1].substring(0, 3)} '
            'has no appointments. Choose a client to create a booking.'
        : '${dayRows.length} appointment${dayRows.length == 1 ? '' : 's'} '
            'on this day. Adjust time or pick a client.';

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: StreamBuilder<List<Client>>(
        stream: db.watchClients(),
        builder: (context, snap) {
          final clients = snap.data ?? const <Client>[];
          Client? selectedClient;
          for (final cl in clients) {
            if (cl.id == clientId) {
              selectedClient = cl;
              break;
            }
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'New appointment',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onClose,
                    icon: Icon(Icons.close, size: 18, color: c.inkMuted),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: c.pink50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Not yet booked',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: c.pink700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                hint,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: c.inkMuted,
                ),
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: c.border),
              const SizedBox(height: 16),
              _FieldLabel('Client'),
              const SizedBox(height: 7),
              _FieldBox(
                value: selectedClient == null
                    ? 'Select a client…'
                    : clientDisplayName(selectedClient),
                muted: selectedClient == null,
                onTap: clients.isEmpty
                    ? null
                    : () async {
                        final id = await showPelviPickerSheet<int>(
                          context: context,
                          title: 'Client',
                          selected: clientId,
                          searchable: true,
                          searchHint: 'Search name or phone',
                          options: [
                            for (final cl in clients)
                              PelviPickerOption(
                                value: cl.id,
                                label: clientDisplayName(cl),
                                subtitle: (cl.phone ?? '').trim().isEmpty
                                    ? null
                                    : cl.phone,
                                searchText:
                                    '${clientDisplayName(cl)} ${cl.phone ?? ''}',
                              ),
                          ],
                        );
                        if (id != null) onPickClient(id);
                      },
              ),
              if (clients.isEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Add a client first, then book a visit.',
                  style: TextStyle(fontSize: 11, color: c.inkMuted),
                ),
              ],
              const SizedBox(height: 16),
              _FieldLabel('Date'),
              const SizedBox(height: 7),
              _FieldBox(
                value: formatNoteDate(selected),
                onTap: onPickDate,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _FieldLabel('Starts'),
                        const SizedBox(height: 7),
                        _FieldBox(
                          value: _hhmm(starts),
                          onTap: onPickStarts,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _FieldLabel('Ends'),
                        const SizedBox(height: 7),
                        _FieldBox(
                          value: _hhmm(ends),
                          onTap: onPickEnds,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$defaultMins min · practice default',
                style: TextStyle(fontSize: 11, color: c.inkMuted),
              ),
              const SizedBox(height: 16),
              _FieldLabel('Practitioner'),
              const SizedBox(height: 7),
              _FieldBox(
                value: practitioner.isEmpty ? '—' : practitioner,
                onTap: null,
              ),
              const SizedBox(height: 16),
              _FieldLabel('Appointment notes'),
              const SizedBox(height: 7),
              TextField(
                controller: notesCtrl,
                maxLines: 3,
                style: TextStyle(fontSize: 13, color: c.ink),
                decoration: InputDecoration(
                  hintText: 'Enter optional booking details…',
                  hintStyle: TextStyle(fontSize: 13, color: c.inkMuted),
                  filled: true,
                  fillColor: c.surface,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(PelviRadius.sm),
                    borderSide: BorderSide(color: c.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(PelviRadius.sm),
                    borderSide: BorderSide(color: c.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(PelviRadius.sm),
                    borderSide: BorderSide(color: c.pink700),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: c.border),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: c.surface,
                      side: BorderSide(color: c.border),
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(PelviRadius.sm),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: canSave ? onSave : null,
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          canSave ? c.pink700 : c.surfaceMuted,
                      foregroundColor:
                          canSave ? c.inkInverse : c.inkMuted,
                      disabledBackgroundColor: c.surfaceMuted,
                      disabledForegroundColor: c.inkMuted,
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(PelviRadius.sm),
                      ),
                    ),
                    child: Text(
                      saving ? 'Saving…' : 'Save appointment',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                canSave
                    ? 'Timezone: ${timezone.replaceAll('_', ' ')} · label only (device clock).'
                    : 'Select a client before saving. Timezone: ${timezone.replaceAll('_', ' ')} · label only (device clock).',
                style: TextStyle(fontSize: 10, color: c.inkMuted),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: PelviColors.of(context).ink,
      ),
    );
  }
}

class _FieldBox extends StatelessWidget {
  const _FieldBox({
    required this.value,
    this.muted = false,
    this.onTap,
  });

  final String value;
  final bool muted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(PelviRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PelviRadius.sm),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PelviRadius.sm),
            border: Border.all(color: c.border),
          ),
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: muted ? c.inkMuted : c.ink,
            ),
          ),
        ),
      ),
    );
  }
}
