import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/theme.dart';
import '../appointments/appointment_form_screen.dart';
import '../notes/note_format.dart';
import '../notes/open_note.dart';
import '../shell/desktop_chrome.dart';
import 'client_format.dart';
import 'phone_field.dart';

enum _HistoryTab { all, appointments, notes }

/// In-place draft for the profile fields. Seeded on edit, discarded on cancel.
class _ClientDraft {
  final first = TextEditingController();
  final last = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  final emergency = TextEditingController();
  final emergencyPhone = TextEditingController();
  final notes = TextEditingController();

  void load(Client client) {
    first.text = client.firstName;
    last.text = client.lastName;
    phone.text = client.phone ?? '';
    email.text = client.email ?? '';
    emergency.text = client.emergencyContact ?? '';
    emergencyPhone.text = client.emergencyContactPhone ?? '';
    notes.text = client.notes ?? '';
  }

  void dispose() {
    first.dispose();
    last.dispose();
    phone.dispose();
    email.dispose();
    emergency.dispose();
    emergencyPhone.dispose();
    notes.dispose();
  }
}

/// Desktop Client profile body (Figma `47:21845`). Shell chrome stays outside.
class WebClientProfile extends StatefulWidget {
  const WebClientProfile({super.key, required this.clientId});

  final int clientId;

  @override
  State<WebClientProfile> createState() => _WebClientProfileState();
}

class _WebClientProfileState extends State<WebClientProfile> {
  _HistoryTab _tab = _HistoryTab.all;
  int? _selectedApptId;
  final _draft = _ClientDraft();
  bool _editing = false;
  bool _saving = false;
  bool _showRequired = false;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _beginEdit(Client client) {
    _draft.load(client);
    setState(() {
      _editing = true;
      _showRequired = false;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editing = false;
      _showRequired = false;
    });
  }

  Future<void> _save(Client client) async {
    if (_saving) return;
    final missingName =
        _draft.first.text.trim().isEmpty || _draft.last.text.trim().isEmpty;
    if (missingName) {
      setState(() => _showRequired = true);
      return;
    }
    setState(() => _saving = true);
    final db = AppDatabaseProvider.of(context);
    try {
      final ok = await db.updateClient(
        id: client.id,
        firstName: _draft.first.text,
        lastName: _draft.last.text,
        phone: _draft.phone.text,
        email: _draft.email.text,
        emergencyContact: _draft.emergency.text,
        emergencyContactPhone: _draft.emergencyPhone.text,
        notes: _draft.notes.text,
      );
      if (!mounted || !ok) return;
      setState(() {
        _editing = false;
        _showRequired = false;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _launchExternal(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _onPhoneTap(String phone) async {
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

  Appointment? _nextAppointment(List<Appointment> appts) {
    final now = DateTime.now();
    Appointment? best;
    for (final a in appts) {
      if (a.status == AppointmentStatus.cancelled) continue;
      if (a.startsAt.isBefore(now)) continue;
      if (best == null || a.startsAt.isBefore(best.startsAt)) best = a;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final db = AppDatabaseProvider.of(context);
    final c = PelviColors.of(context);

    return ColoredBox(
      color: c.canvas,
      child: StreamBuilder<Client?>(
        stream: db.watchClient(widget.clientId),
        builder: (context, clientSnap) {
          final client = clientSnap.data;
          if (client == null) {
            return Center(
              child: clientSnap.connectionState == ConnectionState.waiting
                  ? CircularProgressIndicator(color: c.pink700)
                  : Text(
                      'Client gone',
                      style: TextStyle(color: c.inkMuted),
                    ),
            );
          }

          final name = clientDisplayName(client);

          return StreamBuilder<List<Appointment>>(
            stream: db.watchAppointmentsForClient(widget.clientId),
            builder: (context, apptSnap) {
              final appts = apptSnap.data ?? const <Appointment>[];
              final selectedId = _selectedApptId ??
                  (appts.isEmpty ? null : appts.first.id);
              Appointment? selected;
              for (final a in appts) {
                if (a.id == selectedId) {
                  selected = a;
                  break;
                }
              }
              final next = _nextAppointment(appts);

              return StreamBuilder<List<Note>>(
                stream: db.watchNotesForClient(widget.clientId),
                builder: (context, noteSnap) {
                  final notes = noteSnap.data ?? const <Note>[];
                  Note? selectedNote;
                  if (selected != null) {
                    for (final n in notes) {
                      if (n.appointmentId == selected.id) {
                        selectedNote = n;
                        break;
                      }
                    }
                  }

                  return StreamBuilder<List<int>>(
                    stream: db.watchPinnedClientIds(),
                    builder: (context, pinSnap) {
                      final pinned =
                          (pinSnap.data ?? const <int>[]).contains(client.id);

                      return StreamBuilder<String?>(
                        stream: db.watchPractitionerName(),
                        builder: (context, pracSnap) {
                          final practitioner =
                              (pracSnap.data ?? '').trim().isEmpty
                                  ? 'Practitioner'
                                  : pracSnap.data!.trim();

                          return CustomScrollView(
                            slivers: [
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  32,
                                  32,
                                  32,
                                  40,
                                ),
                                sliver: SliverList(
                                  delegate: SliverChildListDelegate([
                                    _PageHeading(
                                      clientName: name,
                                      editing: _editing,
                                      saving: _saving,
                                      onEdit: () => _beginEdit(client),
                                      onCancel: _cancelEdit,
                                      onSave: () => _save(client),
                                      onNewAppt: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                AppointmentFormScreen(
                                              clientId: client.id,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 26),
                                    _OverviewCard(
                                      client: client,
                                      pinned: pinned,
                                      next: next,
                                      editing: _editing,
                                      draft: _draft,
                                      showRequired: _showRequired,
                                      onPhone: client.phone != null &&
                                              client.phone!.isNotEmpty
                                          ? () =>
                                              _onPhoneTap(client.phone!)
                                          : null,
                                      onEmail: client.email != null &&
                                              client.email!.isNotEmpty
                                          ? () => _launchExternal(
                                                Uri(
                                                  scheme: 'mailto',
                                                  path: client.email!,
                                                ),
                                              )
                                          : null,
                                    ),
                                    const SizedBox(height: 26),
                                    _WorkspaceRow(
                                      client: client,
                                      editing: _editing,
                                      draft: _draft,
                                      appts: appts,
                                      notes: notes,
                                      tab: _tab,
                                      selectedApptId: selected?.id,
                                      selectedAppt: selected,
                                      selectedNote: selectedNote,
                                      practitioner: practitioner,
                                      name: name,
                                      onTab: (t) =>
                                          setState(() => _tab = t),
                                      onSelectAppt: (id) => setState(
                                        () => _selectedApptId = id,
                                      ),
                                      onMute: (v) => db.setRecallMuted(
                                        client.id,
                                        v,
                                      ),
                                      muteStream:
                                          db.watchRecallMuted(client.id),
                                      onCreateSoap: () {
                                        final appt = selected;
                                        if (appt == null) return;
                                        openNoteForAppointment(
                                          context,
                                          appointmentId: appt.id,
                                          clientId: client.id,
                                          noteDate: appt.startsAt,
                                        );
                                      },
                                      onOpenAppt: (appt) {
                                        Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                AppointmentFormScreen(
                                              existing: appt,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ]),
                                ),
                              ),
                            ],
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

class _PageHeading extends StatelessWidget {
  const _PageHeading({
    required this.clientName,
    required this.editing,
    required this.saving,
    required this.onEdit,
    required this.onCancel,
    required this.onSave,
    required this.onNewAppt,
  });

  final String clientName;
  final bool editing;
  final bool saving;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final VoidCallback onNewAppt;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Row(
      key: const Key('client-profile-heading'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DesktopBreadcrumb(
                text: 'Clients / $clientName',
                onAncestorTap: (_) {
                  final nav = Navigator.of(context);
                  if (nav.canPop()) nav.pop();
                },
              ),
              Text(
                'Client profile',
                style: TextStyle(
                  fontSize: 29,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              Text(
                'Contact details, appointment history and notes — together',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: c.inkMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        if (editing) ...[
          OutlinedButton(
            onPressed: saving ? null : onCancel,
            style: OutlinedButton.styleFrom(
              backgroundColor: c.surface,
              foregroundColor: c.ink,
              side: BorderSide(color: c.border),
              minimumSize: const Size(0, 38),
              maximumSize: const Size(double.infinity, 38),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(PelviRadius.sm),
              ),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: saving ? null : onSave,
            style: FilledButton.styleFrom(
              backgroundColor: c.pink700,
              foregroundColor: c.inkInverse,
              minimumSize: const Size(0, 38),
              maximumSize: const Size(double.infinity, 38),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(PelviRadius.sm),
              ),
            ),
            child: const Text(
              'Save',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ] else
          OutlinedButton.icon(
            onPressed: onEdit,
            icon: Icon(Icons.edit_outlined, size: 16, color: c.ink),
            label: Text(
              'Edit details',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: c.surface,
              side: BorderSide(color: c.border),
              minimumSize: const Size(0, 38),
              maximumSize: const Size(double.infinity, 38),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(PelviRadius.sm),
              ),
            ),
          ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: onNewAppt,
          icon: const Icon(Icons.add, size: 16),
          label: const Text(
            'New appointment',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: c.pink700,
            foregroundColor: c.inkInverse,
            minimumSize: const Size(0, 38),
            maximumSize: const Size(double.infinity, 38),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.client,
    required this.pinned,
    required this.next,
    required this.editing,
    required this.draft,
    required this.showRequired,
    required this.onPhone,
    required this.onEmail,
  });

  final Client client;
  final bool pinned;
  final Appointment? next;
  final bool editing;
  final _ClientDraft draft;
  final bool showRequired;
  final VoidCallback? onPhone;
  final VoidCallback? onEmail;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final name = clientDisplayName(client);

    return Container(
      key: const Key('client-identity-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.pink50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              clientInitials(client),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                color: c.pink700,
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: editing
                ? _IdentityFields(draft: draft, showRequired: showRequired)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: TextStyle(
                                fontSize: 24,
                                height: 1.5,
                                fontWeight: FontWeight.w500,
                                color: c.ink,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (pinned) ...[
                            const SizedBox(width: 10),
                            Icon(Icons.push_pin, size: 15, color: c.purple700),
                          ],
                        ],
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 24,
                        runSpacing: 4,
                        children: [
                          if (client.phone != null && client.phone!.isNotEmpty)
                            InkWell(
                              onTap: onPhone,
                              child: Text(
                                displayPhone(client.phone!),
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.5,
                                  color: c.pink700,
                                ),
                              ),
                            ),
                          if (client.email != null && client.email!.isNotEmpty)
                            InkWell(
                              onTap: onEmail,
                              child: Text(
                                client.email!,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.5,
                                  color: c.pink700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'NEXT APPOINTMENT',
                style: TextStyle(
                  fontSize: 10,
                  height: 1.5,
                  color: c.inkMuted,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                next == null
                    ? 'None scheduled'
                    : '${formatNoteDate(next!.startsAt)} · ${formatApptTime(next!.startsAt)}',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                  color: c.ink,
                ),
              ),
              if (next != null) ...[
                const SizedBox(height: 5),
                _StatusPill(label: appointmentStatusLabel(next!.status)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkspaceRow extends StatelessWidget {
  const _WorkspaceRow({
    required this.client,
    required this.editing,
    required this.draft,
    required this.appts,
    required this.notes,
    required this.tab,
    required this.selectedApptId,
    required this.selectedAppt,
    required this.selectedNote,
    required this.practitioner,
    required this.name,
    required this.onTab,
    required this.onSelectAppt,
    required this.onMute,
    required this.muteStream,
    required this.onCreateSoap,
    required this.onOpenAppt,
  });

  final Client client;
  final bool editing;
  final _ClientDraft draft;
  final List<Appointment> appts;
  final List<Note> notes;
  final _HistoryTab tab;
  final int? selectedApptId;
  final Appointment? selectedAppt;
  final Note? selectedNote;
  final String practitioner;
  final String name;
  final ValueChanged<_HistoryTab> onTab;
  final ValueChanged<int> onSelectAppt;
  final ValueChanged<bool> onMute;
  final Stream<bool> muteStream;
  final VoidCallback? onCreateSoap;
  final ValueChanged<Appointment> onOpenAppt;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final details = _DetailsColumn(
          client: client,
          editing: editing,
          draft: draft,
          muteStream: muteStream,
          onMute: onMute,
        );
        final history = _HistoryColumn(
          tab: tab,
          appts: appts,
          notes: notes,
          selectedApptId: selectedApptId,
          practitioner: practitioner,
          onTab: onTab,
          onSelectAppt: onSelectAppt,
          onOpenAppt: onOpenAppt,
        );
        final detail = _VisitDetailPanel(
          name: name,
          appointment: selectedAppt,
          note: selectedNote,
          onCreateSoap: onCreateSoap,
        );

        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              details,
              const SizedBox(height: 24),
              history,
              const SizedBox(height: 24),
              detail,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 276, child: details),
            const SizedBox(width: 24),
            SizedBox(width: 340, child: history),
            const SizedBox(width: 24),
            Expanded(child: detail),
          ],
        );
      },
    );
  }
}

class _DetailsColumn extends StatelessWidget {
  const _DetailsColumn({
    required this.client,
    required this.editing,
    required this.draft,
    required this.muteStream,
    required this.onMute,
  });

  final Client client;
  final bool editing;
  final _ClientDraft draft;
  final Stream<bool> muteStream;
  final ValueChanged<bool> onMute;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final hasEmergency = (client.emergencyContact != null &&
            client.emergencyContact!.isNotEmpty) ||
        (client.emergencyContactPhone != null &&
            client.emergencyContactPhone!.isNotEmpty);
    final notes = (client.notes ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Contact & preferences',
                style: TextStyle(
                  fontSize: 17,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 18),
              if (editing) ...[
                _ProfileField(
                  label: 'EMERGENCY CONTACT',
                  controller: draft.emergency,
                  hint: 'Optional',
                  capitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 18),
                _ProfileField(
                  label: 'EMERGENCY PHONE',
                  controller: draft.emergencyPhone,
                  hint: 'Optional',
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                ),
              ] else ...[
                Text(
                  'EMERGENCY CONTACT',
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: c.inkMuted,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hasEmergency
                      ? [
                          if (client.emergencyContact != null &&
                              client.emergencyContact!.isNotEmpty)
                            client.emergencyContact!,
                          if (client.emergencyContactPhone != null &&
                              client.emergencyContactPhone!.isNotEmpty)
                            client.emergencyContactPhone!,
                        ].join(' · ')
                      : 'Not set',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: hasEmergency ? c.ink : c.inkMuted,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Divider(height: 1, color: c.border),
              const SizedBox(height: 18),
              StreamBuilder<bool>(
                stream: muteStream,
                builder: (context, snap) {
                  final muted = snap.data ?? false;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Mute recalls',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                fontWeight: FontWeight.w500,
                                color: c.ink,
                              ),
                            ),
                          ),
                          Switch.adaptive(
                            value: muted,
                            onChanged: onMute,
                          ),
                        ],
                      ),
                      Text(
                        muted
                            ? 'Hidden from Due and Notifications'
                            : 'Show in Due when inactive',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.5,
                          color: c.inkMuted,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Client notes',
                style: TextStyle(
                  fontSize: 17,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 18),
              if (editing)
                _ProfileField(
                  controller: draft.notes,
                  hint: 'Optional',
                  minLines: 3,
                  maxLines: 3,
                  keyboardType: TextInputType.multiline,
                  capitalization: TextCapitalization.sentences,
                )
              else
                Text(
                  notes.isEmpty ? 'No profile notes yet.' : notes,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: notes.isEmpty ? c.inkMuted : c.ink,
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                'As recorded in the client profile.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: c.inkMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: c.purple50,
            borderRadius: BorderRadius.circular(PelviRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CLIENT SUMMARY',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: c.purple700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'TBD — AI summary of past SOAP notes, with emphasis on the latest visit.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: c.purple700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HistoryColumn extends StatelessWidget {
  const _HistoryColumn({
    required this.tab,
    required this.appts,
    required this.notes,
    required this.selectedApptId,
    required this.practitioner,
    required this.onTab,
    required this.onSelectAppt,
    required this.onOpenAppt,
  });

  final _HistoryTab tab;
  final List<Appointment> appts;
  final List<Note> notes;
  final int? selectedApptId;
  final String practitioner;
  final ValueChanged<_HistoryTab> onTab;
  final ValueChanged<int> onSelectAppt;
  final ValueChanged<Appointment> onOpenAppt;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    // Figma All history shows appointment cards; Notes tab is SOAP-only.
    final showAppts =
        tab == _HistoryTab.all || tab == _HistoryTab.appointments;
    final showNotes = tab == _HistoryTab.notes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: Row(
            children: [
              Flexible(
                child: _HistTab(
                  label: 'All history',
                  selected: tab == _HistoryTab.all,
                  onTap: () => onTab(_HistoryTab.all),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: _HistTab(
                  label: 'Appointments',
                  selected: tab == _HistoryTab.appointments,
                  onTap: () => onTab(_HistoryTab.appointments),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: _HistTab(
                  label: 'Notes',
                  selected: tab == _HistoryTab.notes,
                  onTap: () => onTab(_HistoryTab.notes),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (showAppts) ...[
          Text(
            'APPOINTMENT HISTORY',
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: c.inkMuted,
            ),
          ),
          const SizedBox(height: 12),
          if (appts.isEmpty)
            Text(
              'No appointments yet for this client.',
              style: TextStyle(fontSize: 12, color: c.inkMuted),
            )
          else
            for (final appt in appts) ...[
              _HistoryCard(
                appointment: appt,
                practitioner: practitioner,
                selected: appt.id == selectedApptId,
                onTap: () {
                  onSelectAppt(appt.id);
                  onOpenAppt(appt);
                },
              ),
              const SizedBox(height: 12),
            ],
          Text(
            'Appointment status is shown as recorded. No completed treatment is implied.',
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: c.inkMuted,
            ),
          ),
        ],
        if (showNotes) ...[
          if (showAppts) const SizedBox(height: 22),
          Text(
            'SOAP NOTES',
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: c.inkMuted,
            ),
          ),
          const SizedBox(height: 12),
          if (notes.isEmpty)
            Text(
              'No SOAP notes yet.',
              style: TextStyle(fontSize: 12, color: c.inkMuted),
            )
          else
            for (final note in notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _NoteHistoryCard(note: note),
              ),
        ],
      ],
    );
  }
}

class _HistTab extends StatelessWidget {
  const _HistTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return InkWell(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? c.pink700 : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? c.pink700 : c.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.appointment,
    required this.practitioner,
    required this.selected,
    required this.onTap,
  });

  final Appointment appointment;
  final String practitioner;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Material(
      color: selected ? c.pink50 : c.surface,
      borderRadius: BorderRadius.circular(PelviRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PelviRadius.md),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PelviRadius.md),
            border: Border.all(
              color: selected ? c.pink700 : c.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      formatNoteDate(appointment.startsAt),
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: c.inkMuted),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '${formatApptTime(appointment.startsAt)} · $practitioner',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: c.inkMuted,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _StatusPill(
                    label: appointmentStatusLabel(appointment.status),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 10),
                    Text(
                      'Selected',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: c.pink700,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteHistoryCard extends StatelessWidget {
  const _NoteHistoryCard({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(PelviRadius.md),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatNoteDate(note.noteDate),
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'SOAP note',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: c.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _VisitDetailPanel extends StatelessWidget {
  const _VisitDetailPanel({
    required this.name,
    required this.appointment,
    required this.note,
    required this.onCreateSoap,
  });

  final String name;
  final Appointment? appointment;
  final Note? note;
  final VoidCallback? onCreateSoap;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);

    if (appointment == null) {
      return _Panel(
        child: Text(
          'Select an appointment to review visit details and SOAP notes.',
          style: TextStyle(fontSize: 12, height: 1.5, color: c.inkMuted),
        ),
      );
    }

    final a = appointment!;
    final s = note?.subjective.trim() ?? '';
    final o = note?.objective.trim() ?? '';
    final asmt = note?.assessment.trim() ?? '';
    final p = note?.plan.trim() ?? '';
    final hasNote = note != null;
    final emptySoap = !hasNote ||
        (s.isEmpty && o.isEmpty && asmt.isEmpty && p.isEmpty);

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Visit & note detail',
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
              ),
              Icon(Icons.more_horiz, size: 18, color: c.inkMuted),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '$name · ${formatNoteDate(a.startsAt)} · ${formatApptTime(a.startsAt)}',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: c.inkMuted,
            ),
          ),
          const SizedBox(height: 12),
          _StatusPill(
            label: '${appointmentStatusLabel(a.status)} visit',
          ),
          const SizedBox(height: 18),
          Divider(height: 1, color: c.border),
          const SizedBox(height: 18),
          Text(
            emptySoap
                ? 'No SOAP note is shown for this visit. Start with a blank note or select a published template.'
                : 'SOAP note for this visit.',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: c.inkMuted,
            ),
          ),
          const SizedBox(height: 18),
          _SoapPreview(label: 'Subjective', body: s),
          _SoapPreview(label: 'Objective', body: o),
          _SoapPreview(label: 'Assessment', body: asmt),
          _SoapPreview(label: 'Plan', body: p),
          if (onCreateSoap != null) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              height: 38,
              child: FilledButton.tonalIcon(
                onPressed: onCreateSoap,
                icon: Icon(Icons.edit_note_outlined, size: 16, color: c.pink700),
                label: Text(
                  hasNote ? 'Open SOAP note' : 'Create SOAP note',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.pink700,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: c.pink50,
                  foregroundColor: c.pink700,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(PelviRadius.sm),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Review history alongside the selected visit without leaving the profile.',
            style: TextStyle(
              fontSize: 10,
              height: 1.5,
              color: c.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _SoapPreview extends StatelessWidget {
  const _SoapPreview({required this.label, required this.body});

  final String label;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body.isEmpty ? 'Not entered' : body,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: c.inkMuted,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: c.border),
        ],
      ),
    );
  }
}

class _IdentityFields extends StatelessWidget {
  const _IdentityFields({required this.draft, required this.showRequired});

  final _ClientDraft draft;
  final bool showRequired;

  String? _required(TextEditingController controller) =>
      showRequired && controller.text.trim().isEmpty ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final firstError = _required(draft.first);
    final lastError = _required(draft.last);
    final showError = firstError != null || lastError != null;
    // Same band as the read-only name + contact lines (the 64px avatar).
    final fields = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 30,
          child: Row(
            children: [
              Expanded(
                child: _CompactField(
                  controller: draft.first,
                  hint: 'First name',
                  danger: firstError != null,
                  capitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CompactField(
                  controller: draft.last,
                  hint: 'Last name',
                  danger: lastError != null,
                  capitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                ),
              ),
            ],
          ),
        ),
        if (showError) ...[
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Required',
              style: TextStyle(fontSize: 11, height: 1.2, color: c.danger),
            ),
          ),
        ],
        const SizedBox(height: 4),
        SizedBox(
          height: 30,
          child: Row(
            children: [
              Expanded(
                child: PhoneField(
                  controller: draft.phone,
                  compact: true,
                  textInputAction: TextInputAction.next,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CompactField(
                  controller: draft.email,
                  hint: 'Email',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (showError) return fields;
    return SizedBox(height: 64, child: fields);
  }
}

class _CompactField extends StatefulWidget {
  const _CompactField({
    required this.controller,
    required this.hint,
    this.danger = false,
    this.keyboardType,
    this.capitalization = TextCapitalization.none,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String hint;
  final bool danger;
  final TextInputType? keyboardType;
  final TextCapitalization capitalization;
  final TextInputAction? textInputAction;

  @override
  State<_CompactField> createState() => _CompactFieldState();
}

class _CompactFieldState extends State<_CompactField> {
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode()
      ..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(PelviRadius.sm),
        border: Border.all(
          color: widget.danger
              ? c.danger
              : _focus.hasFocus
                  ? c.pink700
                  : c.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            keyboardType: widget.keyboardType,
            textCapitalization: widget.capitalization,
            textInputAction: widget.textInputAction,
            style: TextStyle(fontSize: 13, height: 1.2, color: c.ink),
            cursorColor: c.pink700,
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: widget.hint,
              hintStyle: TextStyle(
                fontSize: 13,
                height: 1.2,
                color: c.inkMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.controller,
    this.label,
    this.hint,
    this.keyboardType,
    this.capitalization = TextCapitalization.none,
    this.textInputAction,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final TextInputType? keyboardType;
  final TextCapitalization capitalization;
  final TextInputAction? textInputAction;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(PelviRadius.sm),
      borderSide: BorderSide(color: c.border),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: TextStyle(
              fontSize: 10,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: c.inkMuted,
            ),
          ),
          const SizedBox(height: 6),
        ],
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: capitalization,
          textInputAction: textInputAction,
          minLines: minLines,
          maxLines: maxLines,
          style: TextStyle(fontSize: 13, height: 1.5, color: c.ink),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(fontSize: 13, height: 1.5, color: c.inkMuted),
            filled: true,
            fillColor: c.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: BorderSide(color: c.pink700, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: child,
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.pink50,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          height: 1.5,
          fontWeight: FontWeight.w500,
          color: c.pink700,
        ),
      ),
    );
  }
}
