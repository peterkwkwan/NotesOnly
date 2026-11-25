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
import '../clients/client_format.dart';
import '../clients/client_profile_screen.dart';
import '../notes/note_format.dart';
import '../notes/open_note.dart';

/// Next whole hour for a new appointment (12:48 → 13:00; on the hour → that hour).
TimeOfDay nextWholeHour([DateTime? now]) {
  final n = now ?? DateTime.now();
  if (n.minute > 0) {
    return TimeOfDay(hour: (n.hour + 1) % 24, minute: 0);
  }
  return TimeOfDay(hour: n.hour, minute: 0);
}

/// [start] plus [minutes], wrapping past midnight.
TimeOfDay addMinutesToTimeOfDay(TimeOfDay start, int minutes) {
  final total = start.hour * 60 + start.minute + minutes;
  return TimeOfDay(hour: (total ~/ 60) % 24, minute: total % 60);
}

/// Create or edit an appointment: date/time + client (+ status).
class AppointmentFormScreen extends StatefulWidget {
  const AppointmentFormScreen({
    super.key,
    this.clientId,
    this.initialDay,
    this.initialDurationMins,
    this.initialPractitionerUid,
    this.existing,
  });

  /// When set (and no [existing]), client is locked to this id.
  final int? clientId;

  /// Optional day seed for create (defaults to today).
  final DateTime? initialDay;

  /// Optional duration seed for create (e.g. Book again).
  final int? initialDurationMins;

  /// Optional practitioner seed for create (e.g. Book again).
  final String? initialPractitionerUid;

  /// When set, form edits this appointment.
  final Appointment? existing;

  @override
  State<AppointmentFormScreen> createState() => _AppointmentFormScreenState();
}

class _AppointmentFormScreenState extends State<AppointmentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesCtrl = TextEditingController();
  late DateTime _day;
  late TimeOfDay _time;
  int _durationMins = 60;
  AppointmentStatus _status = AppointmentStatus.scheduled;
  int? _clientId;
  bool _saving = false;
  bool? _hasNote;
  bool _canMutate = true;
  bool _canAssignPractitioner = false;
  String _practitionerUid = '';
  List<OrgMember> _bookable = const [];

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _day = DateTime(
        existing.startsAt.year,
        existing.startsAt.month,
        existing.startsAt.day,
      );
      _time = TimeOfDay(
        hour: existing.startsAt.hour,
        minute: existing.startsAt.minute,
      );
      _status = existing.status;
      _clientId = existing.clientId;
      _notesCtrl.text = existing.notes ?? '';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadHasNote();
        _loadCanMutate();
      });
    } else {
      final seed = widget.initialDay ?? DateTime.now();
      _day = DateTime(seed.year, seed.month, seed.day);
      _time = nextWholeHour();
      _clientId = widget.clientId;
      final seedPrac = widget.initialPractitionerUid?.trim() ?? '';
      _practitionerUid =
          seedPrac.isNotEmpty ? seedPrac : (NotesAuth.currentUser?.uid ?? '');
      final seedDur = widget.initialDurationMins;
      if (seedDur != null) {
        _durationMins = AppDatabase.snapAppointmentDuration(seedDur);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (seedDur == null) _loadDefaultDuration();
        _loadCreatePractitioner();
      });
    }
    if (_editing) {
      _notesCtrl.addListener(_onNotesChanged);
    }
  }

  void _onNotesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_editing) _notesCtrl.removeListener(_onNotesChanged);
    _notesCtrl.dispose();
    super.dispose();
  }

  bool get _isDirty {
    final e = widget.existing;
    if (e == null) return true;
    final notes = _notesCtrl.text.trim();
    final existingNotes = (e.notes ?? '').trim();
    return _clientId != e.clientId ||
        _status != e.status ||
        notes != existingNotes ||
        _startsAt.year != e.startsAt.year ||
        _startsAt.month != e.startsAt.month ||
        _startsAt.day != e.startsAt.day ||
        _startsAt.hour != e.startsAt.hour ||
        _startsAt.minute != e.startsAt.minute;
  }

  Future<void> _loadCreatePractitioner() async {
    if (_editing || !mounted) return;
    final db = AppDatabaseProvider.of(context);
    final roles =
        parseOrgRoles(await db.getSetting(AppDatabase.activeOrgRolesKey));
    final canAssign = mayReassignBooking(roles);
    if (!canAssign) {
      if (!mounted) return;
      setState(() => _canAssignPractitioner = false);
      return;
    }
    final orgId = await db.getSetting(AppDatabase.activeOrgIdKey);
    if (orgId == null || orgId.isEmpty || !mounted) {
      setState(() => _canAssignPractitioner = true);
      return;
    }
    try {
      final members = await OrgDirectory().listMembers(orgId);
      final bookable = [
        for (final m in members)
          if (isBookablePractitioner(m)) m,
      ];
      if (!mounted) return;
      setState(() {
        _canAssignPractitioner = true;
        _bookable = bookable;
        if (_practitionerUid.isEmpty) {
          _practitionerUid = NotesAuth.currentUser?.uid ?? '';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _canAssignPractitioner = true);
    }
  }

  Future<void> _pickPractitioner() async {
    if (!_canAssignPractitioner || _bookable.isEmpty) return;
    final uid = await showPelviPickerSheet<String>(
      context: context,
      title: 'Practitioner',
      selected: _practitionerUid,
      options: [
        for (final member in _bookable)
          PelviPickerOption(
            value: member.uid,
            label: memberLabel(member),
          ),
      ],
    );
    if (uid != null) setState(() => _practitionerUid = uid);
  }

  String _practitionerLabel() {
    for (final member in _bookable) {
      if (member.uid == _practitionerUid) return memberLabel(member);
    }
    return _practitionerUid.isEmpty ? 'Select practitioner' : _practitionerUid;
  }

  Future<void> _loadCanMutate() async {
    final existing = widget.existing;
    if (existing == null || !mounted) return;
    final db = AppDatabaseProvider.of(context);
    final self = NotesAuth.currentUser?.uid ?? '';
    if (self.isEmpty) return;
    final roles =
        parseOrgRoles(await db.getSetting(AppDatabase.activeOrgRolesKey));
    if (!mounted) return;
    setState(() {
      _canMutate = mayMutateBooking(
        actor: roles,
        selfUid: self,
        practitionerUid: existing.practitionerUid,
      );
    });
  }

  Future<void> _loadDefaultDuration() async {
    final mins =
        await AppDatabaseProvider.of(context).getDefaultAppointmentMinutes();
    if (!mounted || _editing) return;
    setState(() {
      _durationMins = AppDatabase.snapAppointmentDuration(mins);
    });
  }

  Future<void> _loadHasNote() async {
    final existing = widget.existing;
    if (existing == null || !mounted) return;
    final note = await AppDatabaseProvider.of(context)
        .getNoteForAppointment(existing.id);
    if (!mounted) return;
    setState(() => _hasNote = note != null);
  }

  DateTime get _startsAt => DateTime(
        _day.year,
        _day.month,
        _day.day,
        _time.hour,
        _time.minute,
      );

  DateTime get _endsAt =>
      _startsAt.add(Duration(minutes: _durationMins));

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _day = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _pickClient(List<Client> clients) async {
    final id = await showPelviPickerSheet<int>(
      context: context,
      title: 'Client',
      selected: _clientId,
      searchable: true,
      searchHint: 'Search name or phone',
      options: [
        for (final c in clients)
          PelviPickerOption(
            value: c.id,
            label: clientDisplayName(c),
            subtitle: (c.phone ?? '').trim().isEmpty ? null : c.phone,
            searchText: '${clientDisplayName(c)} ${c.phone ?? ''}',
          ),
      ],
    );
    if (id != null) setState(() => _clientId = id);
  }

  void _openClientProfile() {
    final id = _clientId;
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClientProfileScreen(clientId: id),
      ),
    );
  }

  Future<void> _pickStatus() async {
    final status = await showPelviPickerSheet<AppointmentStatus>(
      context: context,
      title: 'Status',
      selected: _status,
      options: [
        for (final s in AppointmentStatus.values)
          PelviPickerOption(
            value: s,
            label: appointmentStatusLabel(s),
            labelColor: appointmentStatusColor(s),
          ),
      ],
    );
    if (status != null) setState(() => _status = status);
  }

  Future<void> _pickDuration() async {
    final picked = await showPelviPickerSheet<int>(
      context: context,
      title: 'Duration',
      selected: _durationMins,
      options: [
        for (final m in AppDatabase.appointmentDurationChoices)
          PelviPickerOption(value: m, label: '$m min'),
      ],
    );
    if (picked != null) setState(() => _durationMins = picked);
  }

  Future<void> _openSoap() async {
    final existing = widget.existing;
    final clientId = _clientId;
    if (existing == null || clientId == null) return;
    await openNoteForAppointment(
      context,
      appointmentId: existing.id,
      clientId: clientId,
      noteDate: _startsAt,
    );
    if (!mounted) return;
    await _loadHasNote();
  }

  Future<void> _bookAgain() async {
    final existing = widget.existing;
    if (existing == null || _saving) return;
    final db = AppDatabaseProvider.of(context);
    final defaultMins = await db.getDefaultAppointmentMinutes();
    final end = appointmentEffectiveEnd(
      existing.startsAt,
      existing.endsAt,
      defaultMins,
    );
    final duration = AppDatabase.snapAppointmentDuration(
      end.difference(existing.startsAt).inMinutes,
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppointmentFormScreen(
          clientId: existing.clientId,
          initialDurationMins: duration,
          initialPractitionerUid: existing.practitionerUid,
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final existing = widget.existing;
    if (existing == null || _saving || !_canMutate) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this appointment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: PelviColors.of(context).danger,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await AppDatabaseProvider.of(context).deleteAppointment(existing.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      showPelviSnackBar(context, 'Could not delete: $e');
      setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final clientId = _clientId;
    if (clientId == null) return;
    if (_editing && !_canMutate) {
      showPelviSnackBar(
        context,
        'Only an owner or admin can change another practitioner\'s booking',
      );
      return;
    }
    setState(() => _saving = true);
    final db = AppDatabaseProvider.of(context);
    try {
      if (_editing) {
        await db.updateAppointment(
          id: widget.existing!.id,
          startsAt: _startsAt,
          status: _status,
          clientId: clientId,
          notes: _notesCtrl.text,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }

      await db.insertAppointment(
        clientId: clientId,
        startsAt: _startsAt,
        endsAt: _endsAt,
        status: _status,
        notes: _notesCtrl.text,
        practitionerUid: _canAssignPractitioner && _practitionerUid.isNotEmpty
            ? _practitionerUid
            : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on AppointmentConflictException catch (e) {
      if (!mounted) return;
      showPelviSnackBar(
        context,
        appointmentConflictCopy(
          clientName: clientDisplayName(e.client),
          startsAt: e.appointment.startsAt,
        ),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      showPelviSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _fieldTap({
    required String value,
    required String hint,
    required VoidCallback? onTap,
    String? errorText,
    IconData trailing = Icons.chevron_right,
    Color? valueColor,
  }) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          errorText: errorText,
          suffixIcon: Icon(trailing, size: 18, color: PelviColors.of(context).inkMuted),
        ),
        child: Text(
          value.isEmpty ? hint : value,
          style: text.bodyLarge?.copyWith(
            color: value.isEmpty
                ? PelviColors.of(context).inkMuted
                : (valueColor ?? PelviColors.of(context).ink),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = AppDatabaseProvider.of(context);
    final text = Theme.of(context).textTheme;
    // Locked only when booking from a client profile (create path).
    final lockedClient = !_editing && widget.clientId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit appointment' : 'New appointment'),
        actions: [
          if (_editing && _canMutate)
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(Icons.more_horiz),
              onSelected: (value) {
                if (value == 'delete') _confirmDelete();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'delete',
                  enabled: !_saving,
                  child: Text(
                    'Delete',
                    style: TextStyle(color: PelviColors.of(context).danger),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(PelviSpace.page),
          children: [
            Text('CLIENT', style: text.labelMedium),
            const SizedBox(height: PelviSpace.xs),
            if (lockedClient)
              FutureBuilder<Client?>(
                future: db.getClient(widget.clientId!),
                builder: (context, snap) {
                  final name = snap.data == null
                      ? '…'
                      : clientDisplayName(snap.data!);
                  return InputDecorator(
                    decoration: const InputDecoration(),
                    child: Text(name, style: text.bodyLarge),
                  );
                },
              )
            else
              StreamBuilder<List<Client>>(
                stream: db.watchClients(),
                builder: (context, snap) {
                  final clients = snap.data ?? const <Client>[];
                  if (clients.isEmpty) {
                    return Text(
                      'Add a client first, then book a visit.',
                      style: text.bodyMedium?.copyWith(
                        color: PelviColors.of(context).inkMuted,
                      ),
                    );
                  }
                  Client? selected;
                  for (final c in clients) {
                    if (c.id == _clientId) {
                      selected = c;
                      break;
                    }
                  }
                  return FormField<int>(
                    key: ValueKey(_clientId),
                    initialValue: _clientId,
                    validator: (v) => v == null ? 'Pick a client' : null,
                    builder: (state) {
                      final field = _fieldTap(
                        value: selected == null
                            ? ''
                            : clientDisplayName(selected),
                        hint: 'Select client',
                        errorText: state.errorText,
                        onTap: _editing && !_canMutate
                            ? null
                            : () async {
                                await _pickClient(clients);
                                state.didChange(_clientId);
                              },
                      );
                      if (!_editing || _clientId == null) return field;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: field),
                          IconButton(
                            tooltip: 'Client profile',
                            onPressed: _openClientProfile,
                            icon: const Icon(Icons.person_outline),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            const SizedBox(height: PelviSpace.md),
            Text('DATE', style: text.labelMedium),
            const SizedBox(height: PelviSpace.xs),
            _fieldTap(
              value: formatNoteDate(_day),
              hint: '',
              onTap: _editing && !_canMutate ? null : _pickDate,
              trailing: Icons.calendar_today_outlined,
            ),
            const SizedBox(height: PelviSpace.md),
            Text('TIME', style: text.labelMedium),
            const SizedBox(height: PelviSpace.xs),
            _fieldTap(
              value: formatApptTime(
                DateTime(0, 1, 1, _time.hour, _time.minute),
              ),
              hint: '',
              onTap: _editing && !_canMutate ? null : _pickTime,
              trailing: Icons.schedule_outlined,
            ),
            if (!_editing) ...[
              const SizedBox(height: PelviSpace.md),
              Text('DURATION', style: text.labelMedium),
              const SizedBox(height: PelviSpace.xs),
              _fieldTap(
                value: '$_durationMins min',
                hint: '',
                onTap: _pickDuration,
              ),
              if (_canAssignPractitioner) ...[
                const SizedBox(height: PelviSpace.md),
                Text('PRACTITIONER', style: text.labelMedium),
                const SizedBox(height: PelviSpace.xs),
                _fieldTap(
                  value: _practitionerLabel(),
                  hint: 'Select practitioner',
                  onTap: _bookable.isEmpty ? null : _pickPractitioner,
                ),
              ],
            ],
            const SizedBox(height: PelviSpace.md),
            Text('STATUS', style: text.labelMedium),
            const SizedBox(height: PelviSpace.xs),
            _fieldTap(
              value: appointmentStatusLabel(_status),
              hint: '',
              onTap: _editing && !_canMutate ? null : _pickStatus,
              valueColor: appointmentStatusColor(_status),
            ),
            const SizedBox(height: PelviSpace.md),
            Text('APPOINTMENT NOTES', style: text.labelMedium),
            const SizedBox(height: PelviSpace.xs),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              enabled: !_editing || _canMutate,
              decoration: const InputDecoration(
                hintText: 'Enter optional booking details…',
              ),
            ),
            const SizedBox(height: PelviSpace.lg),
            if (_editing) ...[
              FilledButton.icon(
                onPressed: _saving ? null : _openSoap,
                icon: const Icon(Icons.description_outlined, size: 20),
                label: Text(
                  _hasNote == true ? 'Open SOAP note' : 'Create SOAP note',
                ),
              ),
              const SizedBox(height: PelviSpace.sm),
              OutlinedButton.icon(
                onPressed: _saving ? null : _bookAgain,
                style: OutlinedButton.styleFrom(
                  foregroundColor: PelviColors.of(context).pink700,
                  side: BorderSide(color: PelviColors.of(context).pink700),
                ),
                icon: const Icon(Icons.event_repeat, size: 20),
                label: const Text('Book again'),
              ),
              if (_canMutate && _isDirty) ...[
                const SizedBox(height: PelviSpace.sm),
                TextButton.icon(
                  onPressed: _saving || _clientId == null ? null : _save,
                  icon: _saving
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: PelviColors.of(context).pink700,
                          ),
                        )
                      : const Icon(Icons.save_outlined, size: 20),
                  label: const Text('Save changes'),
                ),
              ],
            ] else
              FilledButton(
                onPressed: _saving || _clientId == null ? null : _save,
                child: _saving
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: PelviColors.of(context).inkInverse,
                        ),
                      )
                    : const Text('Save appointment'),
              ),
          ],
        ),
      ),
    );
  }
}
