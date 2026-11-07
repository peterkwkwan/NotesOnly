import 'package:flutter/material.dart';

import '../../data/appointment_overlap.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/show_snack.dart';
import '../clients/client_format.dart';
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

/// Create or edit an appointment: date/time + client (+ status).
class AppointmentFormScreen extends StatefulWidget {
  const AppointmentFormScreen({
    super.key,
    this.clientId,
    this.initialDay,
    this.existing,
  });

  /// When set (and no [existing]), client is locked to this id.
  final int? clientId;

  /// Optional day seed for create (defaults to today).
  final DateTime? initialDay;

  /// When set, form edits this appointment.
  final Appointment? existing;

  @override
  State<AppointmentFormScreen> createState() => _AppointmentFormScreenState();
}

class _AppointmentFormScreenState extends State<AppointmentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _day;
  late TimeOfDay _time;
  AppointmentStatus _status = AppointmentStatus.scheduled;
  int? _clientId;
  bool _saving = false;
  bool? _hasNote;

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
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadHasNote());
    } else {
      final seed = widget.initialDay ?? DateTime.now();
      _day = DateTime(seed.year, seed.month, seed.day);
      _time = nextWholeHour();
      _clientId = widget.clientId;
    }
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final clientId = _clientId;
    if (clientId == null) return;
    setState(() => _saving = true);
    final db = AppDatabaseProvider.of(context);
    try {
      if (_editing) {
        await db.updateAppointment(
          id: widget.existing!.id,
          startsAt: _startsAt,
          status: _status,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }

      final apptId = await db.insertAppointment(
        clientId: clientId,
        startsAt: _startsAt,
        status: _status,
      );
      if (!mounted) return;
      final startNote = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Start a SOAP note for this visit?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (startNote == true) {
        await openNoteForAppointment(
          context,
          appointmentId: apptId,
          clientId: clientId,
          noteDate: _startsAt,
        );
        if (!mounted) return;
      }
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
          suffixIcon: Icon(trailing, size: 18, color: PelviColors.inkMuted),
        ),
        child: Text(
          value.isEmpty ? hint : value,
          style: text.bodyLarge?.copyWith(
            color: value.isEmpty
                ? PelviColors.inkMuted
                : (valueColor ?? PelviColors.ink),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = AppDatabaseProvider.of(context);
    final text = Theme.of(context).textTheme;
    final lockedClient = _editing || widget.clientId != null;
    final lockedClientId = widget.existing?.clientId ?? widget.clientId;

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit appointment' : 'New appointment'),
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
                future: db.getClient(lockedClientId!),
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
                        color: PelviColors.inkMuted,
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
                    builder: (state) => _fieldTap(
                      value: selected == null
                          ? ''
                          : clientDisplayName(selected),
                      hint: 'Select client',
                      errorText: state.errorText,
                      onTap: () async {
                        await _pickClient(clients);
                        state.didChange(_clientId);
                      },
                    ),
                  );
                },
              ),
            const SizedBox(height: PelviSpace.md),
            Text('DATE', style: text.labelMedium),
            const SizedBox(height: PelviSpace.xs),
            _fieldTap(
              value: formatNoteDate(_day),
              hint: '',
              onTap: _pickDate,
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
              onTap: _pickTime,
              trailing: Icons.schedule_outlined,
            ),
            const SizedBox(height: PelviSpace.md),
            Text('STATUS', style: text.labelMedium),
            const SizedBox(height: PelviSpace.xs),
            _fieldTap(
              value: appointmentStatusLabel(_status),
              hint: '',
              onTap: _pickStatus,
              valueColor: appointmentStatusColor(_status),
            ),
            const SizedBox(height: PelviSpace.lg),
            FilledButton(
              onPressed: _saving || _clientId == null ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: PelviColors.inkInverse,
                      ),
                    )
                  : Text(_editing ? 'Save changes' : 'Save appointment'),
            ),
            if (_editing) ...[
              const SizedBox(height: PelviSpace.sm),
              OutlinedButton(
                onPressed: _openSoap,
                child: Text(
                  _hasNote == true ? 'Open SOAP note' : 'Create SOAP note',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
