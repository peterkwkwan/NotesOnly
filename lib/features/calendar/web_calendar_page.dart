import 'package:flutter/material.dart';

import '../../data/appointment_overlap.dart';
import '../../data/auth.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/org.dart';
import '../../data/org_directory.dart';
import '../../theme/theme.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/show_snack.dart';
import '../appointments/appointment_form_screen.dart';
import '../clients/client_format.dart';
import '../notes/note_format.dart';
import '../shell/desktop_chrome.dart';

enum _CalView { day, week, month }

/// Week overlay stays readable past this; day columns can raise later.
const _maxCalendarPractitioners = 3;

String _calendarFilterUidsKey(String orgId, String uid) =>
    'calendar_filter_uids__${orgId}__$uid';

class _PracColors {
  const _PracColors({
    required this.fill,
    required this.accent,
    required this.text,
  });

  final Color fill;
  final Color accent;
  final Color text;
}

/// Pink = me; others get purple / teal / amber by roster order.
_PracColors _personColors({
  required PelviPalette c,
  required String uid,
  required String selfUid,
  required List<String> rosterUids,
}) {
  final id = uid.isEmpty ? selfUid : uid;
  if (id.isEmpty || id == selfUid) {
    return _PracColors(fill: c.pink50, accent: c.pink400, text: c.pink700);
  }
  // shortcut: teal/amber are fixed light swatches; upgrade if dark-calendar QA cares
  final extras = <_PracColors>[
    _PracColors(fill: c.purple50, accent: c.purple400, text: c.purple700),
    const _PracColors(
      fill: Color(0xFFE6F5F0),
      accent: Color(0xFF5BA88A),
      text: Color(0xFF1F7A5C),
    ),
    const _PracColors(
      fill: Color(0xFFFBF0E6),
      accent: Color(0xFFE0A066),
      text: Color(0xFFB56A1E),
    ),
  ];
  final others = [for (final u in rosterUids) if (u != selfUid) u];
  final idx = others.indexOf(id);
  final pick =
      idx < 0 ? id.hashCode.abs() % extras.length : idx % extras.length;
  return extras[pick];
}

String _shortPersonName(String full) {
  final t = full.trim();
  if (t.isEmpty) return '?';
  if (t.contains('@')) {
    final local = t.split('@').first;
    final parts = local.split(RegExp(r'[._\-+]+'));
    final first = parts.isEmpty ? local : parts.first;
    if (first.isEmpty) return local;
    return '${first[0].toUpperCase()}${first.substring(1)}';
  }
  return t.split(RegExp(r'\s+')).first;
}

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
  ({Appointment appointment, Client client})? _reassign;
  String? _reassignUid;
  List<OrgMember> _members = const [];
  bool _canReassign = false;
  bool _rosterStarted = false;
  String _selfUid = '';
  String _orgId = '';
  Set<String> _filterUids = {};
  Map<String, String> _memberNames = {};

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rosterStarted) return;
    _rosterStarted = true;
    _loadRoster();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRoster() async {
    try {
      final db = AppDatabaseProvider.of(context);
      final orgId = await db.getSetting(AppDatabase.activeOrgIdKey);
      final roles =
          parseOrgRoles(await db.getSetting(AppDatabase.activeOrgRolesKey));
      final self = NotesAuth.currentUser?.uid ?? '';
      if (!mounted) return;
      setState(() {
        _canReassign = mayReassignBooking(roles);
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
      final raw =
          await db.getSetting(_calendarFilterUidsKey(orgId, self));
      if (raw != null && raw.isNotEmpty) {
        for (final part in raw.split(',')) {
          final uid = part.trim();
          if (uid.isEmpty) continue;
          if (bookableUids.contains(uid) || uid == self) selected.add(uid);
        }
      }
      if (selected.isEmpty) {
        if (self.isNotEmpty &&
            (bookableUids.contains(self) || bookableUids.isEmpty)) {
          selected = {self};
        } else if (bookable.isNotEmpty) {
          selected = {bookable.first.uid};
        }
      }
      if (selected.length > _maxCalendarPractitioners) {
        selected = selected.take(_maxCalendarPractitioners).toSet();
      }
      setState(() {
        _members = members;
        _memberNames = names;
        _filterUids = selected;
      });
    } catch (_) {
      // Offline or signed out: the panel still shows the booked uid.
      final self = NotesAuth.currentUser?.uid ?? '';
      if (!mounted || self.isEmpty) return;
      if (_filterUids.isEmpty) setState(() => _filterUids = {self});
    }
  }

  List<OrgMember> get _bookableMembers => [
        for (final m in _members)
          if (isBookablePractitioner(m)) m,
      ];

  List<String> get _rosterUids {
    final uids = [for (final m in _bookableMembers) m.uid];
    if (_selfUid.isNotEmpty && !uids.contains(_selfUid)) {
      return [_selfUid, ...uids];
    }
    return uids;
  }

  bool _matchesFilter(String practitionerUid) {
    if (_filterUids.isEmpty) return true;
    final uid = practitionerUid.isEmpty ? _selfUid : practitionerUid;
    if (uid.isEmpty) return _filterUids.contains(_selfUid);
    return _filterUids.contains(uid);
  }

  List<({Appointment appointment, Client client})> _filteredRows(
    List<({Appointment appointment, Client client})> rows,
  ) {
    if (_filterUids.isEmpty) return rows;
    return [
      for (final r in rows)
        if (_matchesFilter(r.appointment.practitionerUid)) r,
    ];
  }

  String _nameForUid(String uid) {
    final stored = _memberNames[uid];
    if (stored != null && stored.isNotEmpty) return stored;
    for (final m in _members) {
      if (m.uid == uid) return memberLabel(m);
    }
    return uid;
  }

  Future<void> _persistFilter() async {
    if (_orgId.isEmpty || _selfUid.isEmpty) return;
    try {
      final db = AppDatabaseProvider.of(context);
      await db.setSetting(
        _calendarFilterUidsKey(_orgId, _selfUid),
        _filterUids.join(','),
      );
    } catch (_) {}
  }

  void _toggleFilterUid(String uid) {
    final next = {..._filterUids};
    if (next.contains(uid)) {
      if (next.length <= 1) return;
      next.remove(uid);
    } else {
      if (next.length >= _maxCalendarPractitioners) return;
      next.add(uid);
    }
    setState(() => _filterUids = next);
    _persistFilter();
  }

  void _filterOnlyMe() {
    final me = _selfUid.isNotEmpty
        ? _selfUid
        : (_bookableMembers.isNotEmpty ? _bookableMembers.first.uid : '');
    if (me.isEmpty) return;
    setState(() => _filterUids = {me});
    _persistFilter();
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
      _reassign = null;
      _reassignUid = null;
      _selected = _dateOnly(d);
      _starts = s;
      _ends = TimeOfDay(hour: (s.hour + 1) % 24, minute: s.minute);
      _clientId = null;
      _notesCtrl.clear();
    });
  }

  void _openReassign(({Appointment appointment, Client client}) row) {
    setState(() {
      _reassign = row;
      _reassignUid = row.appointment.practitionerUid;
      _panelOpen = true;
      _selected = _dateOnly(row.appointment.startsAt);
      if (_view == _CalView.week) _anchor = _mondayOf(_selected);
    });
  }

  void _closePanel() {
    setState(() {
      _panelOpen = false;
      _reassign = null;
      _reassignUid = null;
    });
  }

  Future<void> _saveReassign(AppDatabase db) async {
    final row = _reassign;
    final uid = _reassignUid;
    if (row == null || uid == null || uid.isEmpty || _saving) return;
    if (!_canReassign || uid == row.appointment.practitionerUid) return;
    OrgMember? target;
    for (final member in _members) {
      if (member.uid == uid) target = member;
    }
    if (target == null || !isBookablePractitioner(target)) {
      showPelviSnackBar(context, 'Choose an active practitioner');
      return;
    }
    setState(() => _saving = true);
    try {
      await db.updateAppointment(
        id: row.appointment.id,
        startsAt: row.appointment.startsAt,
        practitionerUid: uid,
      );
      if (!mounted) return;
      setState(() {
        _reassign = null;
        _reassignUid = null;
        _panelOpen = false;
      });
      showPelviSnackBar(context, 'Booking reassigned');
    } on AppointmentConflictException catch (e) {
      if (!mounted) return;
      showPelviSnackBar(
        context,
        appointmentConflictCopy(
          clientName: clientDisplayName(e.client),
          startsAt: e.appointment.startsAt,
        ),
      );
    } catch (e) {
      if (mounted) showPelviSnackBar(context, 'Could not reassign: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                          final rows = _filteredRows(
                            apptSnap.data ?? const [],
                          );

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
                                        // Mirror panel Save when a client is picked.
                                        showSave: _reassign == null &&
                                            _panelOpen &&
                                            _clientId != null,
                                        canSave: _clientId != null && !_saving,
                                        saving: _saving,
                                        onSave: () =>
                                            _save(db, defaultMins),
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
                                        filter: _PractitionerFilter(
                                          members: _bookableMembers,
                                          selfUid: _selfUid,
                                          selfName: practitioner.isEmpty
                                              ? 'Practitioner'
                                              : practitioner,
                                          memberNames: _memberNames,
                                          selectedUids: _filterUids,
                                          rosterUids: _rosterUids,
                                          onToggle: _toggleFilterUid,
                                          onOnlyMe: _filterOnlyMe,
                                        ),
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
                                                    selfUid: _selfUid,
                                                    rosterUids: _rosterUids,
                                                    filterUids: _filterUids,
                                                    nameForUid: _nameForUid,
                                                    draft: _panelOpen &&
                                                            _reassign == null
                                                        ? (
                                                            day: _selected,
                                                            starts: _starts,
                                                          )
                                                        : null,
                                                    onTapAppointment:
                                                        _openReassign,
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
                                              child: _reassign == null
                                                  ? _NewAppointmentPanel(
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
                                              )
                                              : _ReassignPanel(
                                                  row: _reassign!,
                                                  members: _members,
                                                  practitionerUid:
                                                      _reassignUid ??
                                                          _reassign!
                                                              .appointment
                                                              .practitionerUid,
                                                  canReassign: _canReassign,
                                                  saving: _saving,
                                                  onClose: _closePanel,
                                                  onPick: (uid) => setState(
                                                    () => _reassignUid = uid,
                                                  ),
                                                  onSave: () =>
                                                      _saveReassign(db),
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
    required this.showSave,
    required this.canSave,
    required this.saving,
    required this.onSave,
  });

  final DateTime subtitleMonth;
  final VoidCallback onToday;
  final VoidCallback onAdd;
  final bool showSave;
  final bool canSave;
  final bool saving;
  final VoidCallback onSave;

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
          onPressed: showSave ? (canSave ? onSave : null) : onAdd,
          icon: Icon(showSave ? Icons.save_outlined : Icons.add, size: 16),
          label: Text(
            showSave
                ? (saving ? 'Saving…' : 'Save appointment')
                : 'Add appointment',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          style: FilledButton.styleFrom(
            backgroundColor:
                showSave && !canSave ? c.surfaceMuted : c.pink700,
            foregroundColor:
                showSave && !canSave ? c.inkMuted : c.inkInverse,
            disabledBackgroundColor: c.surfaceMuted,
            disabledForegroundColor: c.inkMuted,
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
    required this.view,
    required this.onPrev,
    required this.onNext,
    required this.onView,
    required this.filter,
  });

  final String navLabel;
  final _CalView view;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<_CalView> onView;
  final Widget filter;

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
        filter,
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

class _PractitionerFilter extends StatefulWidget {
  const _PractitionerFilter({
    required this.members,
    required this.selfUid,
    required this.selfName,
    required this.memberNames,
    required this.selectedUids,
    required this.rosterUids,
    required this.onToggle,
    required this.onOnlyMe,
  });

  final List<OrgMember> members;
  final String selfUid;
  final String selfName;
  final Map<String, String> memberNames;
  final Set<String> selectedUids;
  final List<String> rosterUids;
  final ValueChanged<String> onToggle;
  final VoidCallback onOnlyMe;

  @override
  State<_PractitionerFilter> createState() => _PractitionerFilterState();
}

class _PractitionerFilterState extends State<_PractitionerFilter> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  String _labelFor(String uid) {
    if (uid == widget.selfUid) return widget.selfName;
    final named = widget.memberNames[uid];
    if (named != null && named.isNotEmpty) return named;
    for (final m in widget.members) {
      if (m.uid == uid) return memberLabel(m);
    }
    return uid;
  }

  List<({String uid, String label, bool isSelf})> get _options {
    final seen = <String>{};
    final out = <({String uid, String label, bool isSelf})>[];
    if (widget.selfUid.isNotEmpty) {
      seen.add(widget.selfUid);
      out.add((
        uid: widget.selfUid,
        label: widget.selfName,
        isSelf: true,
      ));
    }
    for (final m in widget.members) {
      if (!seen.add(m.uid)) continue;
      out.add((
        uid: m.uid,
        label: widget.memberNames[m.uid] ?? memberLabel(m),
        isSelf: false,
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final selected = [
      for (final o in _options)
        if (widget.selectedUids.contains(o.uid)) o,
    ];
    final atMax = widget.selectedUids.length >= _maxCalendarPractitioners;

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) {
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _portal.hide,
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),
              CompositedTransformFollower(
                link: _link,
                showWhenUnlinked: false,
                targetAnchor: Alignment.bottomRight,
                followerAnchor: Alignment.topRight,
                offset: const Offset(0, 6),
                child: Material(
                  elevation: 8,
                  color: c.surface,
                  shadowColor: c.ink.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 280,
                      maxWidth: 320,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'PRACTITIONERS · MAX $_maxCalendarPractitioners',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                              color: c.inkMuted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final o in _options)
                            _PractitionerOptionRow(
                              label: o.isSelf
                                  ? 'My calendar'
                                  : o.label,
                              subtitle: o.isSelf ? o.label : null,
                              selected:
                                  widget.selectedUids.contains(o.uid),
                              disabled: atMax &&
                                  !widget.selectedUids.contains(o.uid),
                              colors: _personColors(
                                c: c,
                                uid: o.uid,
                                selfUid: widget.selfUid,
                                rosterUids: widget.rosterUids,
                              ),
                              onTap: () {
                                if (atMax &&
                                    !widget.selectedUids
                                        .contains(o.uid)) {
                                  return;
                                }
                                widget.onToggle(o.uid);
                              },
                            ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () {
                                  widget.onOnlyMe();
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: c.pink700,
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  'Only me',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const Spacer(),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            atMax
                                ? 'Week view shows up to $_maxCalendarPractitioners practitioners'
                                : 'Week overlay stays readable at $_maxCalendarPractitioners. Day columns can go higher later.',
                            style: TextStyle(
                              fontSize: 11,
                              color: c.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        child: Material(
          color: c.surface,
          borderRadius: BorderRadius.circular(PelviRadius.sm),
          child: InkWell(
            onTap: () {
              if (_portal.isShowing) {
                _portal.hide();
              } else {
                _portal.show();
              }
            },
            borderRadius: BorderRadius.circular(PelviRadius.sm),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(PelviRadius.sm),
                border: Border.all(color: c.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected.isEmpty)
                    Text(
                      'Select practitioners',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.inkMuted,
                      ),
                    )
                  else if (selected.length == 1 &&
                      selected.first.uid == widget.selfUid)
                    _FilterChipLabel(
                      colors: _personColors(
                        c: c,
                        uid: widget.selfUid,
                        selfUid: widget.selfUid,
                        rosterUids: widget.rosterUids,
                      ),
                      label: 'My calendar',
                    )
                  else
                    for (final o in selected) ...[
                      if (o != selected.first) const SizedBox(width: 6),
                      _FilterChipLabel(
                        colors: _personColors(
                          c: c,
                          uid: o.uid,
                          selfUid: widget.selfUid,
                          rosterUids: widget.rosterUids,
                        ),
                        label: o.isSelf
                            ? 'My calendar'
                            : _shortPersonName(_labelFor(o.uid)),
                      ),
                    ],
                  const SizedBox(width: 6),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: c.ink,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChipLabel extends StatelessWidget {
  const _FilterChipLabel({required this.colors, required this.label});

  final _PracColors colors;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: colors.accent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: PelviColors.of(context).ink,
          ),
        ),
      ],
    );
  }
}

class _PractitionerOptionRow extends StatelessWidget {
  const _PractitionerOptionRow({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.disabled,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final String? subtitle;
  final bool selected;
  final bool disabled;
  final _PracColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final ink = disabled ? c.inkMuted : c.ink;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? colors.fill : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: disabled && !selected ? null : onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: selected,
                    onChanged: disabled && !selected
                        ? null
                        : (_) => onTap(),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    activeColor: c.pink700,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 11,
                            color: c.inkMuted,
                          ),
                        ),
                      if (disabled && !selected)
                        Text(
                          'Limit reached',
                          style: TextStyle(
                            fontSize: 11,
                            color: c.inkMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final child = Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: selected ? c.pink700 : c.ink,
      ),
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
    required this.selfUid,
    required this.rosterUids,
    required this.filterUids,
    required this.nameForUid,
    required this.draft,
    required this.onSelectDay,
    required this.onTapSlot,
    required this.onTapAppointment,
  });

  final List<DateTime> days;
  final DateTime selected;
  final List<({Appointment appointment, Client client})> rows;
  final int startHour;
  final int endHour;
  final int defaultMins;
  final String selfUid;
  final List<String> rosterUids;
  final Set<String> filterUids;
  final String Function(String uid) nameForUid;
  final ({DateTime day, TimeOfDay starts})? draft;
  final ValueChanged<DateTime> onSelectDay;
  final void Function(DateTime day, TimeOfDay time) onTapSlot;
  final void Function(({Appointment appointment, Client client}) row)
      onTapAppointment;

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

  static List<({int lane, int laneCount})> _lanesForDay(
    List<({Appointment appointment, Client client})> dayRows,
    int defaultMins,
  ) {
    final indexed = [
      for (var i = 0; i < dayRows.length; i++) (i: i, row: dayRows[i]),
    ]..sort(
        (a, b) => a.row.appointment.startsAt
            .compareTo(b.row.appointment.startsAt),
      );
    final laneEnds = <DateTime>[];
    final laneOf = List<int>.filled(dayRows.length, 0);
    for (final item in indexed) {
      final start = item.row.appointment.startsAt;
      final end = appointmentEffectiveEnd(
        start,
        item.row.appointment.endsAt,
        defaultMins,
      );
      var lane = 0;
      while (lane < laneEnds.length && laneEnds[lane].isAfter(start)) {
        lane++;
      }
      if (lane == laneEnds.length) {
        laneEnds.add(end);
      } else {
        laneEnds[lane] = end;
      }
      laneOf[item.i] = lane;
    }
    final laneCount = laneEnds.isEmpty ? 1 : laneEnds.length;
    return [
      for (final lane in laneOf) (lane: lane, laneCount: laneCount),
    ];
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
    required _PracColors colors,
    required String practitionerLabel,
    required int lane,
    required int laneCount,
    required VoidCallback onTap,
  }) {
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
    final lanes = laneCount < 1 ? 1 : laneCount;
    final slotW = (colW - 8) / lanes;
    final clientName = clientDisplayName(row.client);
    return Positioned(
      left: gutter + dayIndex * colW + 4 + lane * slotW,
      top: top,
      width: slotW - (lanes > 1 ? 2 : 0),
      height: height,
      child: Tooltip(
        message:
            '${formatApptTime(start)} · $clientName · $practitionerLabel',
        waitDuration: const Duration(milliseconds: 400),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.fill,
                border: Border.all(
                  color: colors.accent.withValues(alpha: 0.45),
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 3, color: colors.accent),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatApptTime(start),
                            style: TextStyle(
                              fontSize: 10,
                              color: colors.text,
                            ),
                          ),
                          Text(
                            clientName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colors.text,
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

  List<Widget> _eventCardsForDay({
    required BuildContext context,
    required PelviPalette c,
    required DateTime day,
    required List<DateTime> days,
    required List<({Appointment appointment, Client client})> rows,
    required double colW,
  }) {
    final dayRows = [
      for (final row in rows)
        if (_sameDay(row.appointment.startsAt, day) &&
            _WeekSchedule._inDayHours(row.appointment.startsAt))
          row,
    ];
    final lanes = _WeekSchedule._lanesForDay(dayRows, widget.defaultMins);
    return [
      for (var i = 0; i < dayRows.length; i++)
        _WeekSchedule._eventCard(
          context: context,
          days: days,
          gutter: _WeekSchedule._gutter,
          colW: colW,
          startHour: _WeekSchedule._dayStart,
          hourH: _WeekSchedule._hourH,
          defaultMins: widget.defaultMins,
          row: dayRows[i],
          colors: _personColors(
            c: c,
            uid: dayRows[i].appointment.practitionerUid,
            selfUid: widget.selfUid,
            rosterUids: widget.rosterUids,
          ),
          practitionerLabel: () {
            final raw = dayRows[i].appointment.practitionerUid;
            final uid = raw.isEmpty ? widget.selfUid : raw;
            final name = widget.nameForUid(uid);
            if (uid == widget.selfUid) return '$name (me)';
            return name;
          }(),
          lane: lanes[i].lane,
          laneCount: lanes[i].laneCount,
          onTap: () => widget.onTapAppointment(dayRows[i]),
        ),
    ];
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
                        for (final day in days)
                          ..._eventCardsForDay(
                            context: context,
                            c: c,
                            day: day,
                            days: days,
                            rows: rows,
                            colW: colW,
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
                  if (widget.filterUids.length <= 1)
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
                    )
                  else ...[
                    for (final uid in widget.rosterUids)
                      if (widget.filterUids.contains(uid)) ...[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _personColors(
                              c: c,
                              uid: uid,
                              selfUid: widget.selfUid,
                              rosterUids: widget.rosterUids,
                            ).accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          uid == widget.selfUid
                              ? '${_shortPersonName(widget.nameForUid(uid))} (me)'
                              : _shortPersonName(widget.nameForUid(uid)),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: c.ink,
                          ),
                        ),
                        const SizedBox(width: 14),
                      ],
                    Text(
                      'Week · overlay · max $_maxCalendarPractitioners',
                      style: TextStyle(fontSize: 10, color: c.inkMuted),
                    ),
                    const SizedBox(width: 14),
                  ],
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

class _ReassignPanel extends StatelessWidget {
  const _ReassignPanel({
    required this.row,
    required this.members,
    required this.practitionerUid,
    required this.canReassign,
    required this.saving,
    required this.onClose,
    required this.onPick,
    required this.onSave,
  });

  final ({Appointment appointment, Client client}) row;
  final List<OrgMember> members;
  final String practitionerUid;
  final bool canReassign;
  final bool saving;
  final VoidCallback onClose;
  final ValueChanged<String> onPick;
  final VoidCallback onSave;

  List<OrgMember> get _bookable => [
        for (final member in members)
          if (isBookablePractitioner(member)) member,
      ];

  String _label(String uid) {
    for (final member in members) {
      if (member.uid != uid) continue;
      final name = memberLabel(member);
      if (!isBookablePractitioner(member)) return '$name (unavailable)';
      return name;
    }
    return uid.isEmpty ? '—' : uid;
  }

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final appt = row.appointment;
    final bookable = _bookable;
    final changed = practitionerUid != appt.practitionerUid;
    OrgMember? selected;
    for (final member in bookable) {
      if (member.uid == practitionerUid) selected = member;
    }
    final canSave = canReassign && changed && selected != null && !saving;
    final when = appt.endsAt == null
        ? '${formatNoteDate(appt.startsAt)} · ${formatApptTime(appt.startsAt)}'
        : '${formatNoteDate(appt.startsAt)} · ${formatApptTime(appt.startsAt)}'
            '–${formatApptTime(appt.endsAt!)}';

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Appointment',
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
          const SizedBox(height: 12),
          Text(
            clientDisplayName(row.client),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            when,
            style: TextStyle(fontSize: 12, height: 1.5, color: c.inkMuted),
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: c.border),
          const SizedBox(height: 16),
          const _FieldLabel('Practitioner'),
          const SizedBox(height: 7),
          _FieldBox(
            value: _label(practitionerUid),
            muted: practitionerUid.isEmpty,
            onTap: !canReassign || bookable.isEmpty
                ? null
                : () async {
                    final uid = await showPelviPickerSheet<String>(
                      context: context,
                      title: 'Practitioner',
                      selected: practitionerUid,
                      options: [
                        for (final member in bookable)
                          PelviPickerOption(
                            value: member.uid,
                            label: memberLabel(member),
                          ),
                      ],
                    );
                    if (uid != null) onPick(uid);
                  },
          ),
          const SizedBox(height: 8),
          Text(
            canReassign
                ? 'The appointment stays on this clinic.'
                : 'Owners and admins can move this booking.',
            style: TextStyle(fontSize: 11, height: 1.5, color: c.inkMuted),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: canSave ? onSave : null,
            style: FilledButton.styleFrom(
              backgroundColor: canSave ? c.pink700 : c.surfaceMuted,
              foregroundColor: canSave ? c.inkInverse : c.inkMuted,
              disabledBackgroundColor: c.surfaceMuted,
              disabledForegroundColor: c.inkMuted,
              minimumSize: const Size(0, 38),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(PelviRadius.sm),
              ),
            ),
            child: Text(
              saving ? 'Saving…' : 'Reassign',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
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
