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
            style: TextButton.styleFrom(foregroundColor: PelviColors.of(context).danger),
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
          return Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: PelviColors.of(context).pink700),
            ),
          );
        }
        if (client == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Client profile')),
            body: QuietEmptyState(
              title: 'Client gone',
              body: 'This profile is no longer in the local database.',
              primaryLabel: 'Back',
              onPrimary: () => Navigator.of(context).pop(),
            ),
          );
        }

        final text = Theme.of(context).textTheme;
        final c = PelviColors.of(context);
        final name = clientDisplayName(client);
        final n = _selected.length;
        final hasEmergency = (client.emergencyContact != null &&
                client.emergencyContact!.isNotEmpty) ||
            (client.emergencyContactPhone != null &&
                client.emergencyContactPhone!.isNotEmpty);

        return PopScope(
          canPop: !_selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _selecting) _exitSelect();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(_selecting ? '$n selected' : 'Client profile'),
              actions: [
                if (_selecting) ...[
                  TextButton(
                    onPressed: _exitSelect,
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: n == 0 ? null : _confirmDeleteSelected,
                    style: TextButton.styleFrom(
                      foregroundColor: c.danger,
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
              padding: const EdgeInsets.fromLTRB(
                PelviSpace.page,
                PelviSpace.md,
                PelviSpace.page,
                PelviSpace.lg,
              ),
              children: [
                Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.pink50,
                        borderRadius: BorderRadius.circular(23),
                      ),
                      child: Text(
                        clientInitials(client),
                        style: text.titleMedium?.copyWith(
                          fontSize: 23,
                          fontWeight: FontWeight.w500,
                          color: c.pink700,
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: PelviSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: text.titleMedium?.copyWith(
                              fontSize: 23,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.7,
                              color: c.ink,
                              height: 1.2,
                            ),
                          ),
                          if (client.phone != null &&
                              client.phone!.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _ContactLink(
                              icon: Icons.phone_outlined,
                              label: client.phone!,
                              onTap: () =>
                                  _onPhoneTap(context, client.phone!),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (client.email != null && client.email!.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _ContactLink(
                    icon: Icons.mail_outlined,
                    label: client.email!,
                    onTap: () => _launchExternal(
                      Uri(scheme: 'mailto', path: client.email!),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(PelviRadius.lg),
                    border: Border.all(color: c.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(17),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasEmergency) ...[
                          Text('EMERGENCY', style: text.labelMedium),
                          if (client.emergencyContact != null &&
                              client.emergencyContact!.isNotEmpty) ...[
                            const SizedBox(height: PelviSpace.sm),
                            Text(
                              client.emergencyContact!,
                              style: text.bodyMedium?.copyWith(
                                fontSize: 15,
                                color: c.ink,
                              ),
                            ),
                          ],
                          if (client.emergencyContactPhone != null &&
                              client.emergencyContactPhone!.isNotEmpty) ...[
                            const SizedBox(height: PelviSpace.sm),
                            _ContactLink(
                              icon: Icons.phone_outlined,
                              label: client.emergencyContactPhone!,
                              onTap: () => _onPhoneTap(
                                context,
                                client.emergencyContactPhone!,
                              ),
                            ),
                          ],
                          const SizedBox(height: 15),
                          Divider(height: 1, color: c.border),
                          const SizedBox(height: 15),
                        ],
                        StreamBuilder<bool>(
                          stream: db.watchRecallMuted(client.id),
                          builder: (context, muteSnap) {
                            final muted = muteSnap.data ?? false;
                            return Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Mute recalls',
                                        style: text.labelLarge?.copyWith(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: c.ink,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        muted
                                            ? 'Hidden from Due and Notifications'
                                            : 'Show in Due when inactive',
                                        style: text.bodySmall?.copyWith(
                                          fontSize: 12,
                                          color: c.inkMuted,
                                        ),
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
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 13,
                      color: c.purple700,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'CLIENT SUMMARY',
                      style: text.labelMedium?.copyWith(
                        color: c.purple700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(PelviSpace.md),
                  decoration: BoxDecoration(
                    color: c.purple50,
                    borderRadius: BorderRadius.circular(PelviRadius.md),
                  ),
                  child: Text(
                    'TBD — AI summary of past SOAP notes, '
                    'with emphasis on the latest visit.',
                    style: text.bodyMedium?.copyWith(
                      color: c.purple700,
                      fontSize: 13,
                      height: 1.65,
                    ),
                  ),
                ),
                if (client.notes != null && client.notes!.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('NOTES', style: text.labelMedium),
                  const SizedBox(height: PelviSpace.sm),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 96),
                    child: SingleChildScrollView(
                      child: Text(
                        client.notes!,
                        style: text.bodyMedium?.copyWith(
                          fontSize: 14,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
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
                        Text('APPOINTMENTS', style: text.labelMedium),
                        if (appts.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: PelviSpace.sm),
                            child: DashedEmptyWell(
                              message:
                                  'No appointments yet for this client.',
                              ctaLabel: 'New appointment',
                              onCta: openNew,
                            ),
                          )
                        else ...[
                          for (final appt in appts)
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
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: FilledButton.icon(
                              onPressed: openNew,
                              icon: const Icon(Icons.add, size: 19),
                              label: const Text('New appointment'),
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    PelviRadius.md,
                                  ),
                                ),
                              ),
                            ),
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

class _ContactLink extends StatelessWidget {
  const _ContactLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 16, color: c.pink700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: c.pink700,
                    fontSize: 14,
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
    final c = PelviColors.of(context);
    final status = appointment.status;
    final pillFg = _statusPillForeground(status, c);
    final pillBg = _statusPillBackground(status, c);

    return InkWell(
      onTap: selecting ? onToggle : onOpen,
      onLongPress: selecting ? onToggle : onLongPress,
      splashColor: c.surfaceMuted,
      highlightColor: c.surfaceMuted,
      child: ColoredBox(
        color: selected ? c.surfaceMuted : Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatApptWhen(appointment.startsAt),
                        style: text.labelLarge?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: PelviSpace.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: pillBg,
                          borderRadius:
                              BorderRadius.circular(PelviRadius.sm),
                        ),
                        child: Text(
                          appointmentStatusLabel(status),
                          style: text.labelMedium?.copyWith(
                            fontSize: 11,
                            height: 1.2,
                            letterSpacing: 0,
                            fontWeight: FontWeight.w500,
                            color: pillFg,
                          ),
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
                    color: selected ? c.pink700 : c.inkMuted,
                    size: 22,
                  )
                else
                  Icon(
                    Icons.chevron_right,
                    color: c.inkMuted,
                    size: 17,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _statusPillForeground(AppointmentStatus status, PelviPalette c) {
  return switch (status) {
    AppointmentStatus.scheduled => c.pink700,
    AppointmentStatus.completed => c.pink700,
    AppointmentStatus.cancelled => c.inkMuted,
    AppointmentStatus.noShow => c.purple700,
  };
}

Color _statusPillBackground(AppointmentStatus status, PelviPalette c) {
  return switch (status) {
    AppointmentStatus.scheduled => c.pink50,
    AppointmentStatus.completed => c.pink50,
    AppointmentStatus.cancelled => c.surfaceMuted,
    AppointmentStatus.noShow => c.purple50,
  };
}
