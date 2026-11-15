import 'package:flutter/material.dart';

import '../../data/appointment_overlap.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/show_snack.dart';
import '../clients/client_format.dart';
import '../notes/note_format.dart';
import '../shell/desktop_chrome.dart';
import 'appointment_form_screen.dart';

/// Desktop full-page create flow (Figma `Desktop / New appointment`).
class WebNewAppointmentPage extends StatefulWidget {
  const WebNewAppointmentPage({
    super.key,
    this.clientId,
    this.initialDay,
    this.initialTime,
    this.breadcrumb,
  });

  /// When set, client is locked to this id (e.g. from Client profile).
  final int? clientId;

  /// Optional day seed (defaults to today).
  final DateTime? initialDay;

  /// Optional start time (defaults to [nextWholeHour]).
  final TimeOfDay? initialTime;

  /// Optional deeper crumb (e.g. `Clients / New appointment`). Empty = none.
  final String? breadcrumb;

  @override
  State<WebNewAppointmentPage> createState() => _WebNewAppointmentPageState();
}

class _WebNewAppointmentPageState extends State<WebNewAppointmentPage> {
  late DateTime _day;
  late TimeOfDay _time;
  AppointmentStatus _status = AppointmentStatus.scheduled;
  int? _clientId;
  bool _saving = false;
  String? _clientError;

  bool get _clientLocked => widget.clientId != null;

  @override
  void initState() {
    super.initState();
    final seed = widget.initialDay ?? DateTime.now();
    _day = DateTime(seed.year, seed.month, seed.day);
    _time = widget.initialTime ?? nextWholeHour();
    _clientId = widget.clientId;
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
    if (id != null) {
      setState(() {
        _clientId = id;
        _clientError = null;
      });
    }
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

  Future<void> _save() async {
    final clientId = _clientId;
    if (clientId == null) {
      setState(() => _clientError = 'Pick a client');
      return;
    }
    setState(() => _saving = true);
    final db = AppDatabaseProvider.of(context);
    try {
      await db.insertAppointment(
        clientId: clientId,
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
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = AppDatabaseProvider.of(context);
    final c = PelviColors.of(context);
    final crumb = widget.breadcrumb ?? '';

    return ColoredBox(
      color: c.canvas,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (crumb.isNotEmpty)
              DesktopBreadcrumb(
                text: crumb,
                onAncestorTap: (_) {
                  final nav = Navigator.of(context);
                  if (nav.canPop()) nav.pop();
                },
              )
            else
              const DesktopBreadcrumb(text: ''),
            Text(
              'New appointment',
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
                  if (_clientLocked)
                    FutureBuilder<Client?>(
                      future: db.getClient(widget.clientId!),
                      builder: (context, snap) {
                        final name = snap.data == null
                            ? '…'
                            : clientDisplayName(snap.data!);
                        return _FieldBox(value: name);
                      },
                    )
                  else
                    StreamBuilder<List<Client>>(
                      stream: db.watchClients(),
                      builder: (context, snap) {
                        final clients = snap.data ?? const <Client>[];
                        Client? selected;
                        for (final cl in clients) {
                          if (cl.id == _clientId) {
                            selected = cl;
                            break;
                          }
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _FieldBox(
                              value: selected == null
                                  ? 'Select client'
                                  : clientDisplayName(selected),
                              muted: selected == null,
                              onTap: clients.isEmpty
                                  ? null
                                  : () => _pickClient(clients),
                            ),
                            if (clients.isEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Add a client first, then book a visit.',
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.5,
                                  color: c.inkMuted,
                                ),
                              ),
                            ] else if (_clientError != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                _clientError!,
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.5,
                                  color: c.danger,
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  const SizedBox(height: 20),
                  const _FieldLabel('DATE'),
                  const SizedBox(height: 6),
                  _FieldBox(
                    value: formatNoteDate(_day),
                    onTap: _pickDate,
                  ),
                  const SizedBox(height: 20),
                  const _FieldLabel('TIME'),
                  const SizedBox(height: 6),
                  _FieldBox(
                    value: formatApptTime(
                      DateTime(0, 1, 1, _time.hour, _time.minute),
                    ),
                    onTap: _pickTime,
                  ),
                  const SizedBox(height: 20),
                  const _FieldLabel('STATUS'),
                  const SizedBox(height: 6),
                  _FieldBox(
                    value: appointmentStatusLabel(_status),
                    valueColor: appointmentStatusColor(_status, c),
                    onTap: _pickStatus,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _saving || (!_clientLocked && _clientId == null)
                        ? null
                        : _save,
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
                            'Save appointment',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
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
