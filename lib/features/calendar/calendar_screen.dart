import 'package:flutter/material.dart';

import '../../data/auth.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/org.dart';
import '../../data/org_directory.dart';
import '../../theme/theme.dart';
import '../../widgets/empty_state.dart';
import '../appointments/appointment_agenda_row.dart';
import '../appointments/appointment_form_screen.dart';
import '../notes/note_format.dart';
import '../shell/desktop_chrome.dart';
import 'calendar_practitioner_colors.dart';
import 'calendar_practitioner_filter.dart';
import 'web_calendar_page.dart';

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

const _weekdayLetters = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

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

  bool _rosterStarted = false;
  String _selfUid = '';
  String _orgId = '';
  Set<String> _filterUids = {};
  List<OrgMember> _members = const [];
  Map<String, String> _memberNames = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = _dateOnly(now);
    // Default Me-only before async roster/settings restore.
    final self = NotesAuth.currentUser?.uid ?? '';
    _selfUid = self;
    if (self.isNotEmpty) _filterUids = {self};
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rosterStarted) return;
    _rosterStarted = true;
    _loadRoster();
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

  List<OrgMember> get _bookableMembers => [
        for (final m in _members)
          if (isBookablePractitioner(m)) m,
      ];

  Future<void> _loadRoster() async {
    try {
      final db = AppDatabaseProvider.of(context);
      final orgId = await db.getSetting(AppDatabase.activeOrgIdKey);
      final self = NotesAuth.currentUser?.uid ?? '';
      if (!mounted) return;
      setState(() {
        _selfUid = self;
        _orgId = orgId ?? '';
      });
      if (orgId == null || orgId.isEmpty) {
        if (self.isNotEmpty && _filterUids.isEmpty) {
          setState(() => _filterUids = {self});
        }
        return;
      }
      final members = await OrgDirectory().listMembers(orgId);
      final bookable = [
        for (final m in members)
          if (isBookablePractitioner(m)) m,
      ];
      final names = <String, String>{};
      for (final m in bookable) {
        final stored = await db.getPractitionerName(uid: m.uid);
        final label = (stored != null && stored.trim().isNotEmpty)
            ? stored.trim()
            : memberLabel(m);
        names[m.uid] = label;
      }
      if (self.isNotEmpty) {
        final selfName = await db.getPractitionerName(uid: self);
        if (selfName != null && selfName.trim().isNotEmpty) {
          names[self] = selfName.trim();
        }
      }
      if (!mounted) return;
      final bookableUids = {for (final m in bookable) m.uid};
      var selected = <String>{};
      final raw = await db.getSetting(calendarFilterUidsKey(orgId, self));
      for (final uid in parseCalendarFilterUids(raw)) {
        if (bookableUids.contains(uid) || uid == self) selected.add(uid);
      }
      if (selected.isEmpty) {
        if (self.isNotEmpty &&
            (bookableUids.contains(self) || bookableUids.isEmpty)) {
          selected = {self};
        } else if (bookable.isNotEmpty) {
          selected = {bookable.first.uid};
        }
      }
      setState(() {
        _members = members;
        _memberNames = names;
        _filterUids = selected;
      });
    } catch (_) {
      final self = NotesAuth.currentUser?.uid ?? '';
      if (!mounted || self.isEmpty) return;
      setState(() {
        if (_filterUids.isEmpty) _filterUids = {self};
      });
    }
  }

  Future<void> _persistFilter() async {
    if (_orgId.isEmpty || _selfUid.isEmpty) return;
    try {
      final db = AppDatabaseProvider.of(context);
      await db.setSetting(
        calendarFilterUidsKey(_orgId, _selfUid),
        encodeCalendarFilterUids(_filterUids),
      );
    } catch (_) {}
  }

  bool _matchesFilter(String practitionerUid) => matchesCalendarFilter(
        filterUids: _filterUids,
        practitionerUid: practitionerUid,
        selfUid: _selfUid,
      );

  List<({Appointment appointment, Client client})> _filteredRows(
    List<({Appointment appointment, Client client})> rows,
  ) {
    if (_filterUids.isEmpty) return rows;
    return [
      for (final r in rows)
        if (_matchesFilter(r.appointment.practitionerUid)) r,
    ];
  }

  Map<DateTime, int> _countsFromRows(
    List<({Appointment appointment, Client client})> rows,
  ) {
    final counts = <DateTime, int>{};
    for (final r in _filteredRows(rows)) {
      final a = r.appointment.startsAt;
      final d = DateTime(a.year, a.month, a.day);
      counts[d] = (counts[d] ?? 0) + 1;
    }
    return counts;
  }

  String get _filterButtonLabel {
    if (_filterUids.length == 1 &&
        _selfUid.isNotEmpty &&
        _filterUids.contains(_selfUid)) {
      return 'Me';
    }
    if (_filterUids.isEmpty) return 'Me';
    return '${_filterUids.length}';
  }

  List<({String uid, String label, bool isSelf})> get _filterOptions {
    final seen = <String>{};
    final out = <({String uid, String label, bool isSelf})>[];
    if (_selfUid.isNotEmpty) {
      seen.add(_selfUid);
      out.add((uid: _selfUid, label: 'Me', isSelf: true));
    }
    for (final m in _bookableMembers) {
      if (!seen.add(m.uid)) continue;
      out.add((
        uid: m.uid,
        label: _memberNames[m.uid] ?? memberLabel(m),
        isSelf: false,
      ));
    }
    return out;
  }

  Future<void> _openPractitionerFilter() async {
    final options = _filterOptions;
    if (options.isEmpty) return;
    var draft = {..._filterUids};
    if (draft.isEmpty && _selfUid.isNotEmpty) draft = {_selfUid};

    final applied = await showModalBottomSheet<Set<String>>(
      context: context,
      backgroundColor: PelviColors.of(context).surface,
      barrierColor: PelviColors.of(context).overlay,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(PelviRadius.lg),
        ),
      ),
      builder: (context) {
        return _PractitionerFilterSheet(
          options: options,
          initial: draft,
        );
      },
    );
    if (applied == null || !mounted) return;
    setState(() => _filterUids = applied);
    await _persistFilter();
  }

  @override
  Widget build(BuildContext context) {
    if (isDesktopShell(context)) {
      return const WebCalendarPage();
    }

    final db = AppDatabaseProvider.of(context);
    final text = Theme.of(context).textTheme;
    final today = _dateOnly(DateTime.now());
    final monthStart = DateTime(_month.year, _month.month);
    final monthEnd = DateTime(_month.year, _month.month + 1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: PelviSpace.sm),
            child: Center(
              child: Material(
                color: PelviColors.of(context).surface,
                borderRadius: BorderRadius.circular(PelviRadius.sm),
                child: InkWell(
                  onTap: _openPractitionerFilter,
                  borderRadius: BorderRadius.circular(PelviRadius.sm),
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(PelviRadius.sm),
                      border: Border.all(color: PelviColors.of(context).border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _filterButtonLabel,
                          style: text.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: PelviColors.of(context).ink,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.filter_list,
                          size: 18,
                          color: PelviColors.of(context).inkMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder(
        stream: db.watchDefaultAppointmentMinutes(),
        builder: (context, minsSnap) {
          final defaultMinutes = minsSnap.data ?? 60;
          return StreamBuilder(
            stream: db.watchAppointmentsWithClientOnDay(_selected),
            builder: (context, daySnap) {
              final rows = daySnap.data == null
                  ? null
                  : _filteredRows(daySnap.data!);
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: PelviSpace.page,
                      ),
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
                  const SliverToBoxAdapter(
                    child: SizedBox(height: PelviSpace.xs),
                  ),
                  SliverToBoxAdapter(
                    child: StreamBuilder(
                      stream: db.watchAppointmentsWithClientInRange(
                        monthStart,
                        monthEnd,
                      ),
                      builder: (context, snap) {
                        final counts = _countsFromRows(
                          snap.data ?? const [],
                        );
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
                          borderRadius:
                              BorderRadius.circular(PelviRadius.md),
                          border: Border.all(
                            color: PelviColors.of(context).border,
                          ),
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
                              foregroundColor:
                                  PelviColors.of(context).pink700,
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
                        final multi = _filterUids.length > 1;
                        final uid = row.appointment.practitionerUid.isEmpty
                            ? _selfUid
                            : row.appointment.practitionerUid;
                        return AppointmentAgendaRow(
                          appointment: row.appointment,
                          client: row.client,
                          past: past,
                          defaultMinutes: defaultMinutes,
                          railColor: multi
                              ? practitionerColors(
                                  c: PelviColors.of(context),
                                  uid: uid,
                                  selfUid: _selfUid,
                                  rosterUids: [
                                    for (final m in _bookableMembers) m.uid,
                                  ],
                                ).accent
                              : null,
                          practitionerLabel: multi
                              ? (_memberNames[uid] ??
                                  (uid == _selfUid ? 'Me' : null))
                              : null,
                        );
                      },
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _PractitionerFilterSheet extends StatefulWidget {
  const _PractitionerFilterSheet({
    required this.options,
    required this.initial,
  });

  final List<({String uid, String label, bool isSelf})> options;
  final Set<String> initial;

  @override
  State<_PractitionerFilterSheet> createState() =>
      _PractitionerFilterSheetState();
}

class _PractitionerFilterSheetState extends State<_PractitionerFilterSheet> {
  late Set<String> _draft;

  @override
  void initState() {
    super.initState();
    _draft = {...widget.initial};
  }

  void _toggle(String uid) {
    setState(() {
      final next = {..._draft};
      if (next.contains(uid)) {
        if (next.length <= 1) return;
        next.remove(uid);
      } else {
        next.add(uid);
      }
      _draft = next;
    });
  }

  void _selectAll() {
    setState(() {
      _draft = {for (final o in widget.options) o.uid};
    });
  }

  Color _badgeFill(int index, PelviPalette c) {
    final fills = [c.pink400, c.purple400, c.pink700];
    return fills[index % fills.length];
  }

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final text = Theme.of(context).textTheme;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          PelviSpace.page,
          PelviSpace.sm,
          PelviSpace.page,
          PelviSpace.md + bottom,
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
                  color: c.border,
                  borderRadius: BorderRadius.circular(PelviRadius.full),
                ),
              ),
            ),
            const SizedBox(height: PelviSpace.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Filter practitioners',
                    style: text.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: _selectAll,
                  style: TextButton.styleFrom(
                    foregroundColor: c.pink700,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Select all',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: PelviSpace.sm),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.45,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.options.length,
                itemBuilder: (context, index) {
                  final o = widget.options[index];
                  final selected = _draft.contains(o.uid);
                  final initials = o.isSelf
                      ? 'ME'
                      : practitionerInitials(o.label);
                  return InkWell(
                    onTap: () => _toggle(o.uid),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: PelviSpace.sm + 2,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: selected,
                              onChanged: (_) => _toggle(o.uid),
                              activeColor: c.pink700,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(PelviRadius.sm),
                              ),
                              side: BorderSide(color: c.border, width: 1.5),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          const SizedBox(width: PelviSpace.md),
                          Expanded(
                            child: Text(
                              o.label,
                              style: text.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: c.ink,
                              ),
                            ),
                          ),
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: _badgeFill(index, c),
                            child: Text(
                              initials,
                              style: text.labelSmall?.copyWith(
                                color: c.inkInverse,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: PelviSpace.md),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_draft),
                style: FilledButton.styleFrom(
                  backgroundColor: c.pink700,
                  foregroundColor: c.inkInverse,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(PelviRadius.full),
                  ),
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
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
    // Sunday-first: weekday % 7 → col (Sun=0 … Sat=6).
    final leading = first.weekday % 7;
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
                              highlightColor:
                                  PelviColors.of(context).surfaceMuted,
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
                                        decorationColor:
                                            PelviColors.of(context).inkMuted,
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
