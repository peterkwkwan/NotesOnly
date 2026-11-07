import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/empty_state.dart';
import '../appointments/appointment_form_screen.dart';
import 'client_form_screen.dart';
import 'client_format.dart';

Future<void> _launchExternal(Uri uri) async {
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> _onPhoneTap(BuildContext context, String phone) async {
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Phone'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'call'),
          child: const Text('Phone call'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'whatsapp'),
          child: const Text('WhatsApp'),
        ),
      ],
    ),
  );
  if (choice == null) return;
  if (choice == 'call') {
    await _launchExternal(Uri(scheme: 'tel', path: phone));
  } else {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    await _launchExternal(Uri.parse('https://wa.me/$digits'));
  }
}

class ClientProfileScreen extends StatefulWidget {
  const ClientProfileScreen({super.key, required this.clientId});

  final int clientId;

  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  bool _selecting = false;
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppDatabaseProvider.of(context).touchRecentClient(widget.clientId);
    });
  }

  void _exitSelect() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _enterSelect(int id) {
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..add(id);
    });
  }

  void _toggleSelected(int id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  Future<void> _confirmDeleteSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          ids.length == 1
              ? 'Delete appointment?'
              : 'Delete ${ids.length} appointments?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: PelviColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final db = AppDatabaseProvider.of(context);
    for (final id in ids) {
      await db.deleteAppointment(id);
    }
    if (!mounted) return;
    _exitSelect();
  }

  @override
  Widget build(BuildContext context) {
    final db = AppDatabaseProvider.of(context);
    final clientId = widget.clientId;

    return StreamBuilder<Client?>(
      stream: db.watchClient(clientId),
      builder: (context, snap) {
        final client = snap.data;
        if (snap.connectionState == ConnectionState.waiting && client == null) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: PelviColors.pink700),
            ),
          );
        }
        if (client == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Client')),
            body: QuietEmptyState(
              title: 'Client gone',
              body: 'This profile is no longer in the local database.',
              primaryLabel: 'Back',
              onPrimary: () => Navigator.of(context).pop(),
            ),
          );
        }

        final text = Theme.of(context).textTheme;
        final name = clientDisplayName(client);
        final n = _selected.length;

        return PopScope(
          canPop: !_selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _selecting) _exitSelect();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(_selecting ? '$n selected' : name),
              actions: [
                if (_selecting) ...[
                  TextButton(
                    onPressed: _exitSelect,
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: n == 0 ? null : _confirmDeleteSelected,
                    style: TextButton.styleFrom(
                      foregroundColor: PelviColors.danger,
                    ),
                    child: const Text('Delete'),
                  ),
                ] else
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ClientFormScreen(existing: client),
                        ),
                      );
                    },
                    child: const Text('Edit'),
                  ),
              ],
            ),
            body: ListView(
              children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    PelviSpace.page,
                    PelviSpace.lg,
                    PelviSpace.page,
                    PelviSpace.md,
                  ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: text.headlineMedium),
                    if ((client.phone != null && client.phone!.isNotEmpty) ||
                        (client.email != null &&
                            client.email!.isNotEmpty)) ...[
                      const SizedBox(height: PelviSpace.md),
                      if (client.phone != null &&
                          client.phone!.isNotEmpty)
                        _PhoneLink(phone: client.phone!),
                      if (client.email != null &&
                          client.email!.isNotEmpty) ...[
                        if (client.phone != null &&
                            client.phone!.isNotEmpty)
                          const SizedBox(height: PelviSpace.sm),
                        _EmailLink(email: client.email!),
                      ],
                    ],
                    if ((client.emergencyContact != null &&
                            client.emergencyContact!.isNotEmpty) ||
                        (client.emergencyContactPhone != null &&
                            client.emergencyContactPhone!.isNotEmpty)) ...[
                      const SizedBox(height: PelviSpace.lg),
                      const Divider(height: 1),
                      const SizedBox(height: PelviSpace.lg),
                      Text('EMERGENCY', style: text.labelMedium),
                      if (client.emergencyContact != null &&
                          client.emergencyContact!.isNotEmpty) ...[
                        const SizedBox(height: PelviSpace.sm),
                        Text(
                          client.emergencyContact!,
                          style: text.bodyMedium,
                        ),
                      ],
                      if (client.emergencyContactPhone != null &&
                          client.emergencyContactPhone!.isNotEmpty) ...[
                        const SizedBox(height: PelviSpace.sm),
                        _PhoneLink(phone: client.emergencyContactPhone!),
                      ],
                    ],
                    const SizedBox(height: PelviSpace.lg),
                    const Divider(height: 1),
                    StreamBuilder<bool>(
                      stream: db.watchRecallMuted(client.id),
                      builder: (context, muteSnap) {
                        final muted = muteSnap.data ?? false;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: PelviSpace.sm,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Mute recalls',
                                      style: text.labelLarge,
                                    ),
                                    Text(
                                      muted
                                          ? 'Hidden from Due and Notifications'
                                          : 'Show in Due when inactive',
                                      style: text.labelMedium,
                                    ),
                                  ],
                                ),
                              ),
                              Switch.adaptive(
                                value: muted,
                                onChanged: (v) =>
                                    db.setRecallMuted(client.id, v),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    const SizedBox(height: PelviSpace.lg),
                    Text('CLIENT SUMMARY', style: text.labelMedium),
                    const SizedBox(height: PelviSpace.sm),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(PelviSpace.md),
                      decoration: BoxDecoration(
                        color: PelviColors.surface,
                        borderRadius: BorderRadius.circular(PelviRadius.md),
                        border: Border.all(color: PelviColors.border),
                      ),
                      child: Text(
                        'TBD — AI summary of past SOAP notes, '
                        'with emphasis on the latest visit.',
                        style: text.bodyMedium?.copyWith(
                          color: PelviColors.inkMuted,
                        ),
                      ),
                    ),
                    if (client.notes != null && client.notes!.isNotEmpty) ...[
                      const SizedBox(height: PelviSpace.lg),
                      Text('NOTES', style: text.labelMedium),
                      const SizedBox(height: PelviSpace.sm),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 96),
                        child: SingleChildScrollView(
                          child: Text(
                            client.notes!,
                            style: text.bodyMedium?.copyWith(
                              color: PelviColors.inkMuted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              StreamBuilder<List<Appointment>>(
                stream: db.watchAppointmentsForClient(clientId),
                builder: (context, apptSnap) {
                  final appts = apptSnap.data ?? const <Appointment>[];
                  void openNew() {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AppointmentFormScreen(
                          clientId: client.id,
                        ),
                      ),
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                    PelviSpace.page,
                    PelviSpace.md,
                    PelviSpace.page,
                    PelviSpace.sm,
                  ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('APPOINTMENTS', style: text.labelMedium),
                            if (appts.isNotEmpty) ...[
                              const SizedBox(height: PelviSpace.sm),
                              FilledButton(
                                onPressed: openNew,
                                child: const Text('New appointment'),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (appts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                    PelviSpace.page,
                    PelviSpace.sm,
                    PelviSpace.page,
                    PelviSpace.lg,
                  ),
                          child: DashedEmptyWell(
                            message: 'No appointments yet for this client.',
                            ctaLabel: 'New appointment',
                            onCta: openNew,
                          ),
                        )
                      else
                        for (final (i, appt) in appts.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          _AppointmentRow(
                            appointment: appt,
                            selecting: _selecting,
                            selected: _selected.contains(appt.id),
                            onOpen: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => AppointmentFormScreen(
                                    existing: appt,
                                  ),
                                ),
                              );
                            },
                            onLongPress: () => _enterSelect(appt.id),
                            onToggle: () => _toggleSelected(appt.id),
                          ),
                        ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        );
      },
    );
  }
}

class _PhoneLink extends StatelessWidget {
  const _PhoneLink({required this.phone});

  final String phone;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _onPhoneTap(context, phone),
      child: Row(
        children: [
          const Icon(
            Icons.phone_outlined,
            size: 18,
            color: PelviColors.pink700,
          ),
          const SizedBox(width: PelviSpace.sm),
          Expanded(
            child: Text(
              phone,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: PelviColors.pink700,
                    decoration: TextDecoration.underline,
                    decorationColor: PelviColors.pink700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmailLink extends StatelessWidget {
  const _EmailLink({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _launchExternal(Uri(scheme: 'mailto', path: email)),
      child: Row(
        children: [
          const Icon(
            Icons.email_outlined,
            size: 18,
            color: PelviColors.inkMuted,
          ),
          const SizedBox(width: PelviSpace.sm),
          Expanded(
            child: Text(
              email,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: PelviColors.inkMuted,
                    decoration: TextDecoration.underline,
                    decorationColor: PelviColors.inkMuted,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentRow extends StatelessWidget {
  const _AppointmentRow({
    required this.appointment,
    required this.selecting,
    required this.selected,
    required this.onOpen,
    required this.onLongPress,
    required this.onToggle,
  });

  final Appointment appointment;
  final bool selecting;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: selecting ? onToggle : onOpen,
      onLongPress: selecting ? onToggle : onLongPress,
      splashColor: PelviColors.surfaceMuted,
      highlightColor: PelviColors.surfaceMuted,
      child: ColoredBox(
        color: selected ? PelviColors.surfaceMuted : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PelviSpace.md,
            vertical: PelviSpace.sm + 4,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        formatApptWhen(appointment.startsAt),
                        style: text.labelLarge,
                      ),
                      Text(
                        appointmentStatusLabel(appointment.status),
                        style: text.labelMedium?.copyWith(
                          color: appointmentStatusColor(appointment.status),
                        ),
                      ),
                    ],
                  ),
                ),
                if (selecting)
                  Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected
                        ? PelviColors.pink700
                        : PelviColors.inkMuted,
                    size: 22,
                  )
                else
                  const Icon(
                    Icons.chevron_right,
                    color: PelviColors.inkMuted,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
