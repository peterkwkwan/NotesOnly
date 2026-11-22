import 'package:flutter/material.dart';

import '../../data/appointment_overlap.dart';
import '../../data/auth.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/org.dart';
import '../../theme/theme.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/show_snack.dart';
import '../clients/client_format.dart';
import '../notes/note_format.dart';
import '../notes/open_note.dart';
import '../shell/desktop_chrome.dart';

/// Desktop full-page edit flow (Figma `Desktop / Edit appointment`).
class WebEditAppointmentPage extends StatefulWidget {
  const WebEditAppointmentPage({
    super.key,
    required this.appointment,
    this.clientName,
  });

  final Appointment appointment;

  /// Optional display name for breadcrumbs (avoids a flash of "…").
  final String? clientName;

  @override
  State<WebEditAppointmentPage> createState() => _WebEditAppointmentPageState();
}

class _WebEditAppointmentPageState extends State<WebEditAppointmentPage> {
  late DateTime _day;
  late TimeOfDay _time;
  late AppointmentStatus _status;
  bool _saving = false;
  bool? _hasNote;
  String? _clientName;
  bool _canMutate = true;

  @override
  void initState() {
    super.initState();
    final existing = widget.appointment;
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
    _clientName = widget.clientName;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadClientName();
      _loadHasNote();
      _loadCanMutate();
    });
  }

  Future<void> _loadCanMutate() async {
    if (!mounted) return;
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
        practitionerUid: widget.appointment.practitionerUid,
      );
    });
  }

  DateTime get _startsAt => DateTime(
        _day.year,
        _day.month,
        _day.day,
        _time.hour,
        _time.minute,
      );

  String get _crumbWhen =>
      '${formatNoteDate(_startsAt)}, ${formatApptTime(_startsAt)}';

  Future<void> _loadClientName() async {
    if (_clientName != null && _clientName!.isNotEmpty) return;
    final client = await AppDatabaseProvider.of(context)
        .getClient(widget.appointment.clientId);
    if (!mounted || client == null) return;
    setState(() => _clientName = clientDisplayName(client));
  }

  Future<void> _loadHasNote() async {
    final note = await AppDatabaseProvider.of(context)
        .getNoteForAppointment(widget.appointment.id);
    if (!mounted) return;
    setState(() => _hasNote = note != null);
  }

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
    await openNoteForAppointment(
      context,
      appointmentId: widget.appointment.id,
      clientId: widget.appointment.clientId,
      noteDate: _startsAt,
    );
    if (!mounted) return;
    await _loadHasNote();
  }

  Future<void> _confirmDelete() async {
    if (_saving || !_canMutate) return;
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
      await AppDatabaseProvider.of(context)
          .deleteAppointment(widget.appointment.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      showPelviSnackBar(context, 'Could not delete: $e');
      setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (!_canMutate) {
      showPelviSnackBar(
        context,
        'Only an owner or admin can change another practitioner\'s booking',
      );
      return;
    }
    setState(() => _saving = true);
    final db = AppDatabaseProvider.of(context);
    try {
      await db.updateAppointment(
        id: widget.appointment.id,
        startsAt: _startsAt,
        status: _status,
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

  @override
  Widget build(BuildContext context) {
    final db = AppDatabaseProvider.of(context);
    final c = PelviColors.of(context);
    final name = (_clientName == null || _clientName!.isEmpty)
        ? '…'
        : _clientName!;
    final crumb = 'Clients / $name / $_crumbWhen';

    return ColoredBox(
      color: c.canvas,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DesktopBreadcrumb(
              text: crumb,
              onAncestorTap: (_) {
                final nav = Navigator.of(context);
                if (nav.canPop()) nav.pop();
              },
            ),
            Text(
              'Edit appointment',
              style: TextStyle(
                fontSize: 29,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 28),
            Container(
              width: 560,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(PelviRadius.lg),
                border: Border.all(color: c.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _FieldLabel('CLIENT'),
                  const SizedBox(height: 6),
                  FutureBuilder<Client?>(
                    future: db.getClient(widget.appointment.clientId),
                    builder: (context, snap) {
                      final display = snap.data == null
                          ? name
                          : clientDisplayName(snap.data!);
                      return _FieldBox(value: display);
                    },
                  ),
                  const SizedBox(height: 20),
                  const _FieldLabel('DATE'),
                  const SizedBox(height: 6),
                  _FieldBox(
                    value: formatNoteDate(_day),
                    onTap: _canMutate ? _pickDate : null,
                  ),
                  const SizedBox(height: 20),
                  const _FieldLabel('TIME'),
                  const SizedBox(height: 6),
                  _FieldBox(
                    value: formatApptTime(
                      DateTime(0, 1, 1, _time.hour, _time.minute),
                    ),
                    onTap: _canMutate ? _pickTime : null,
                  ),
                  const SizedBox(height: 20),
                  const _FieldLabel('STATUS'),
                  const SizedBox(height: 6),
                  _FieldBox(
                    value: appointmentStatusLabel(_status),
                    valueColor: appointmentStatusColor(_status, c),
                    onTap: _canMutate ? _pickStatus : null,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _saving || !_canMutate ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: c.pink700,
                      foregroundColor: c.inkInverse,
                      disabledBackgroundColor: c.surfaceMuted,
                      disabledForegroundColor: c.inkMuted,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(PelviRadius.sm),
                      ),
                    ),
                    child: _saving
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: c.inkInverse,
                            ),
                          )
                        : const Text(
                            'Save changes',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _saving ? null : _openSoap,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: c.surface,
                      foregroundColor: c.ink,
                      side: BorderSide(color: c.border),
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(PelviRadius.sm),
                      ),
                    ),
                    child: Text(
                      _hasNote == true ? 'Open SOAP note' : 'Create SOAP note',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_canMutate) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: _saving ? null : _confirmDelete,
                      style: TextButton.styleFrom(
                        foregroundColor: c.danger,
                        disabledForegroundColor: c.inkMuted,
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                      child: const Text(
                        'Delete',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
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
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        height: 1.5,
        color: PelviColors.of(context).inkMuted,
      ),
    );
  }
}

class _FieldBox extends StatelessWidget {
  const _FieldBox({
    required this.value,
    this.muted = false,
    this.valueColor,
    this.onTap,
  });

  final String value;
  final bool muted;
  final Color? valueColor;
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
          width: double.infinity,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PelviRadius.sm),
            border: Border.all(color: c.border),
          ),
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: muted ? c.inkMuted : (valueColor ?? c.ink),
            ),
          ),
        ),
      ),
    );
  }
}
