import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/auth.dart';
import '../../data/backup.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/online.dart';
import '../../data/sync.dart';
import '../../theme/theme.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/show_snack.dart';
import '../org/org_access_screen.dart';

const _recallDayChoices = <int>[14, 21, 30, 45, 60, 90];
const _durationChoices = <int>[30, 45, 60, 90];
const _timezoneChoices = <String>[
  'Asia/Hong_Kong',
  'Asia/Macau',
  'Asia/Shanghai',
  'Asia/Singapore',
  'America/Toronto',
  'America/Vancouver',
  'UTC',
];

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  Future<void> _editPracticeName(BuildContext context) async {
    final db = AppDatabaseProvider.of(context);
    final current =
        (await db.getPractitionerName(uid: NotesAuth.currentUser?.uid)) ?? '';
    if (!context.mounted) return;
    // Own controller in State; dispose-on-pop hits TextField mid-exit anim.
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => _PracticeNameDialog(initialName: current),
    );
    if (saved == null) return;
    final trimmed = saved.trim();
    if (trimmed.isEmpty) {
      if (context.mounted) {
        showPelviSnackBar(context, 'Practitioner name cannot be empty');
      }
      return;
    }
    await db.setPractitionerName(trimmed, uid: NotesAuth.currentUser?.uid);
  }

  Future<void> _editRecallWindow(BuildContext context) async {
    final db = AppDatabaseProvider.of(context);
    final current = await db.getRecallDays();
    if (!context.mounted) return;
    final picked = await showPelviPickerSheet<int>(
      context: context,
      title: 'Recall window',
      selected: current,
      options: [
        const PelviPickerOption(value: 0, label: 'Never'),
        for (final d in _recallDayChoices)
          PelviPickerOption(value: d, label: '$d days'),
      ],
    );
    if (picked == null) return;
    await db.setRecallDays(picked);
  }

  Future<void> _editDuration(BuildContext context) async {
    final db = AppDatabaseProvider.of(context);
    final current = await db.getDefaultAppointmentMinutes();
    if (!context.mounted) return;
    final picked = await showPelviPickerSheet<int>(
      context: context,
      title: 'Default duration',
      selected: current,
      options: [
        for (final m in _durationChoices)
          PelviPickerOption(value: m, label: '$m min'),
      ],
    );
    if (picked == null) return;
    await db.setDefaultAppointmentMinutes(picked);
  }

  Future<void> _editTimezone(BuildContext context) async {
    final db = AppDatabaseProvider.of(context);
    final current = await db.getTimezone();
    if (!context.mounted) return;
    final picked = await showPelviPickerSheet<String>(
      context: context,
      title: 'Timezone',
      selected: current,
      options: [
        for (final z in _timezoneChoices)
          PelviPickerOption(value: z, label: z.replaceAll('_', ' ')),
      ],
    );
    if (picked == null) return;
    await db.setTimezone(picked);
  }

  Future<void> _editHours(BuildContext context, {required bool start}) async {
    final db = AppDatabaseProvider.of(context);
    final raw = start
        ? await db.getClinicHoursStart()
        : await db.getClinicHoursEnd();
    final parts = raw.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.first) ?? (start ? 9 : 18),
      minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
    );
    if (!context.mounted) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked == null) return;
    final hhmm =
        '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    if (start) {
      await db.setClinicHoursStart(hhmm);
    } else {
      await db.setClinicHoursEnd(hhmm);
    }
  }

  Future<void> _exportJson(BuildContext context) async {
    final db = AppDatabaseProvider.of(context);
    try {
      final map = await buildBackupMap(db);
      final json = encodeBackupJson(map);
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final bytes = Uint8List.fromList(utf8.encode(json));
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes,
              mimeType: 'application/json',
              name: 'notesonly-backup-$stamp.json',
            ),
          ],
          subject: 'NotesOnly backup',
          text: 'NotesOnly backup (clients, appointments, notes)',
        ),
      );
    } catch (e) {
      if (context.mounted) {
        showPelviSnackBar(context, 'Export failed: $e');
      }
    }
  }

  Future<void> _exportCsv(BuildContext context) async {
    final db = AppDatabaseProvider.of(context);
    try {
      final csv = await buildBackupCsv(db);
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(csv.clients)),
              mimeType: 'text/csv',
              name: 'notesonly-clients-$stamp.csv',
            ),
            XFile.fromData(
              Uint8List.fromList(utf8.encode(csv.appointments)),
              mimeType: 'text/csv',
              name: 'notesonly-appointments-$stamp.csv',
            ),
            XFile.fromData(
              Uint8List.fromList(utf8.encode(csv.notes)),
              mimeType: 'text/csv',
              name: 'notesonly-notes-$stamp.csv',
            ),
          ],
          subject: 'NotesOnly CSV export',
          text: 'NotesOnly clients, appointments, and notes (CSV)',
        ),
      );
    } catch (e) {
      if (context.mounted) {
        showPelviSnackBar(context, 'CSV export failed: $e');
      }
    }
  }

  Future<void> _importRestore(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore backup?'),
        content: const Text(
          'This replaces all clients, appointments, and notes on this device '
          'with the JSON backup. Settings in the file overwrite matching keys.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: PelviColors.of(context).danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (picked.isEmpty || !context.mounted) return;

    final file = picked.single;
    final db = AppDatabaseProvider.of(context);
    try {
      final raw = utf8.decode(await file.readAsBytes());
      final map = decodeBackupJson(raw);
      await restoreBackupMap(db, map);
      if (context.mounted) {
        showPelviSnackBar(context, 'Backup restored');
      }
    } catch (e) {
      if (context.mounted) {
        showPelviSnackBar(context, 'Restore failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = AppDatabaseProvider.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Account Settings')),
      body: ListView(
        padding: const EdgeInsets.all(PelviSpace.page),
        children: [
          const _SectionLabel('Practice preferences'),
          const SizedBox(height: PelviSpace.sm),
          _SettingsBlock(
            children: [
              StreamBuilder<String?>(
                stream: db.watchPractitionerName(),
                builder: (_, snap) {
                  final name = snap.data?.trim();
                  return _TappableRow(
                    title: 'Practitioner name',
                    subtitle:
                        (name == null || name.isEmpty) ? 'Not set' : name,
                    // Screen context — StreamBuilder row rebuilds on save.
                    onTap: () => _editPracticeName(context),
                  );
                },
              ),
              const Divider(height: 1),
              StreamBuilder<int>(
                stream: db.watchRecallDays(),
                builder: (context, recallSnap) {
                  final days = recallSnap.data ?? 30;
                  return _TappableRow(
                    title: 'Recall window',
                    subtitle: days <= 0
                        ? 'Never · recalls disabled'
                        : '$days days · clients with no visit in window',
                    onTap: () => _editRecallWindow(context),
                  );
                },
              ),
              const Divider(height: 1),
              StreamBuilder<int>(
                stream: db.watchDefaultAppointmentMinutes(),
                builder: (context, snap) {
                  final mins = snap.data ?? 60;
                  return _TappableRow(
                    title: 'Default duration',
                    subtitle: '$mins min · used when end time is unset',
                    onTap: () => _editDuration(context),
                  );
                },
              ),
              const Divider(height: 1),
              StreamBuilder<(String, String)>(
                stream: db.watchClinicHours(),
                builder: (context, snap) {
                  final start = snap.data?.$1 ?? '09:00';
                  final end = snap.data?.$2 ?? '18:00';
                  return Column(
                    children: [
                      _TappableRow(
                        title: 'Clinic opens',
                        subtitle: start,
                        onTap: () => _editHours(context, start: true),
                      ),
                      const Divider(height: 1),
                      _TappableRow(
                        title: 'Clinic closes',
                        subtitle: end,
                        onTap: () => _editHours(context, start: false),
                      ),
                    ],
                  );
                },
              ),
              const Divider(height: 1),
              StreamBuilder<String>(
                stream: db.watchTimezone(),
                builder: (context, snap) {
                  final tz = snap.data ?? 'Asia/Hong_Kong';
                  return _TappableRow(
                    title: 'Timezone',
                    subtitle:
                        '${tz.replaceAll('_', ' ')} · label only (device clock)',
                    onTap: () => _editTimezone(context),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: PelviSpace.lg),
          _SettingsBlock(
            children: [
              StreamBuilder<bool>(
                stream: db.watchDarkModeEnabled(),
                builder: (context, snap) {
                  final on = snap.data ?? false;
                  return _SwitchRow(
                    title: 'Dark mode',
                    subtitle: 'Use dark chrome across the app',
                    value: on,
                    onChanged: (v) => db.setDarkModeEnabled(v),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: PelviSpace.lg),
          _SettingsBlock(
            children: [
              StreamBuilder<bool>(
                stream: db.watchRecallNotificationsEnabled(),
                builder: (context, snap) {
                  final on = snap.data ?? true;
                  return _SwitchRow(
                    title: 'Recall notifications',
                    subtitle: 'Daily local reminder when clients are due',
                    value: on,
                    onChanged: (v) => db.setRecallNotificationsEnabled(v),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: PelviSpace.lg),
          const _SectionLabel('Data & backup'),
          const SizedBox(height: PelviSpace.sm),
          _SettingsBlock(
            children: [
              _TappableRow(
                title: 'Export JSON backup',
                subtitle: 'Clients, appointments, notes + settings',
                onTap: () => _exportJson(context),
              ),
              const Divider(height: 1),
              _TappableRow(
                title: 'Export CSV',
                subtitle: 'Three spreadsheet files via share sheet',
                onTap: () => _exportCsv(context),
              ),
              const Divider(height: 1),
              _TappableRow(
                title: 'Restore from JSON',
                subtitle: 'Replaces local clinical data',
                onTap: () => _importRestore(context),
              ),
            ],
          ),
          const SizedBox(height: PelviSpace.lg),
          const _SectionLabel('Cloud sync'),
          const SizedBox(height: PelviSpace.sm),
          _SettingsBlock(
            children: [
              _SyncStatusRow(db: db),
              const Divider(height: 1),
              const _SyncNowRow(),
            ],
          ),
          const SizedBox(height: PelviSpace.lg),
          const _SectionLabel('Account'),
          const SizedBox(height: PelviSpace.sm),
          _SettingsBlock(
            children: [
              _AccountRow(
                email: NotesAuth.currentUser?.email,
                displayName: NotesAuth.currentUser?.displayName,
              ),
              const Divider(height: 1),
              _TappableRow(
                title: 'Invites',
                subtitle: 'Send or revoke a clinic invite',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const OrgAccessScreen(),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              _TappableRow(
                title: 'Sign out',
                subtitle: 'Clears this clinic from the device',
                onTap: () => _signOut(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AppDatabaseProvider.of(context).clearLocalClinicForAccountSwitch();
      await NotesAuth.signOut();
    } catch (e) {
      if (context.mounted) {
        showPelviSnackBar(context, 'Sign out failed: $e');
      }
    }
  }
}

class _SyncStatusRow extends StatelessWidget {
  const _SyncStatusRow({required this.db});

  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    final sync = AppDatabaseProvider.syncOf(context);
    final c = PelviColors.of(context);
    return StreamBuilder<SyncStatus>(
      stream: sync.watchStatus(),
      initialData: SyncStatus.idle,
      builder: (context, snap) {
        final status = snap.data ?? SyncStatus.idle;
        return StreamBuilder<String?>(
          stream: db.watchSetting(AppDatabase.syncLastSuccessKey),
          builder: (context, lastSnap) {
            final last = lastSnap.data;
            final subtitle = switch (status) {
              SyncStatus.synced => last == null || last.isEmpty
                  ? 'Your clinic data is up to date'
                  : 'Last updated ${_formatSyncTime(last)}',
              SyncStatus.pending => 'Will update when you are back online',
              SyncStatus.syncing => 'Updating…',
              SyncStatus.error => 'Could not update — tap Sync now to try again',
              SyncStatus.idle => 'Sign in to keep devices in sync',
            };
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: PelviSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _statusLabel(status),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: status == SyncStatus.error
                              ? c.danger
                              : c.inkMuted,
                        ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static String _statusLabel(SyncStatus status) => switch (status) {
        SyncStatus.synced => 'Up to date',
        SyncStatus.pending => 'Waiting to sync',
        SyncStatus.syncing => 'Updating',
        SyncStatus.error => 'Could not sync',
        SyncStatus.idle => 'Not syncing',
      };

  static String _formatSyncTime(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}

enum _SyncNowPhase { idle, updating, success, failed }

/// Manual retry control: disabled offline; online tap → Updating → Success/Failed.
class _SyncNowRow extends StatefulWidget {
  const _SyncNowRow();

  @override
  State<_SyncNowRow> createState() => _SyncNowRowState();
}

class _SyncNowRowState extends State<_SyncNowRow>
    with WidgetsBindingObserver {
  bool _online = true;
  _SyncNowPhase _phase = _SyncNowPhase.idle;
  Timer? _resultClear;
  Timer? _onlinePoll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshOnline());
    _onlinePoll = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(_refreshOnline());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resultClear?.cancel();
    _onlinePoll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshOnline());
    }
  }

  Future<void> _refreshOnline() async {
    final online = await deviceLooksOnline();
    if (!mounted) return;
    if (online != _online) setState(() => _online = online);
  }

  Future<void> _onTap() async {
    if (!_online || _phase == _SyncNowPhase.updating) return;
    setState(() => _phase = _SyncNowPhase.updating);
    final sync = AppDatabaseProvider.syncOf(context);
    final status = await sync.syncNow();
    if (!mounted) return;
    final ok = status == SyncStatus.synced;
    setState(() => _phase = ok ? _SyncNowPhase.success : _SyncNowPhase.failed);
    _resultClear?.cancel();
    _resultClear = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _phase = _SyncNowPhase.idle);
    });
    unawaited(_refreshOnline());
  }

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final enabled = _online && _phase != _SyncNowPhase.updating;
    final (title, subtitle, Color? accent, Widget trailing) = switch (_phase) {
      _SyncNowPhase.updating => (
          'Sync now',
          'Updating…',
          null,
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: c.pink700,
            ),
          ),
        ),
      _SyncNowPhase.success => (
          'Success',
          'Your clinic data is up to date',
          c.success,
          Icon(Icons.check_circle_outline, color: c.success, size: 20),
        ),
      _SyncNowPhase.failed => (
          'Failed',
          'Could not update — try again',
          c.danger,
          Icon(Icons.error_outline, color: c.danger, size: 20),
        ),
      _SyncNowPhase.idle when !_online => (
          'Sync now',
          'Connect to the internet to sync',
          null,
          Icon(Icons.cloud_off_outlined, color: c.inkMuted, size: 20),
        ),
      _SyncNowPhase.idle => (
          'Sync now',
          'Retry syncing your clients and notes now',
          null,
          Icon(Icons.chevron_right, color: c.inkMuted, size: 20),
        ),
    };

    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: PelviSpace.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: enabled || _phase != _SyncNowPhase.idle
                            ? null
                            : c.inkMuted,
                      ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: accent ?? c.inkMuted,
                      ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );

    if (!enabled) {
      return Opacity(opacity: _phase == _SyncNowPhase.idle ? 0.55 : 1, child: content);
    }
    return InkWell(
      onTap: _onTap,
      splashColor: c.surfaceMuted,
      highlightColor: c.surfaceMuted,
      child: content,
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({this.email, this.displayName});

  final String? email;
  final String? displayName;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final title = (displayName != null && displayName!.trim().isNotEmpty)
        ? displayName!.trim()
        : (email ?? 'Signed in');
    final subtitle = email != null && title != email
        ? email!
        : 'Google · Firebase Auth';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PelviSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: c.inkMuted,
                ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium,
    );
  }
}

class _PracticeNameDialog extends StatefulWidget {
  const _PracticeNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_PracticeNameDialog> createState() => _PracticeNameDialogState();
}

class _PracticeNameDialogState extends State<_PracticeNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Practitioner name'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          hintText: 'Clinic or practitioner name',
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _SettingsBlock extends StatelessWidget {
  const _SettingsBlock({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(PelviRadius.lg),
        border: Border.all(color: c.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _TappableRow extends StatelessWidget {
  const _TappableRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      splashColor: PelviColors.of(context).surfaceMuted,
      highlightColor: PelviColors.of(context).surfaceMuted,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: PelviSpace.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.labelLarge),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: PelviColors.of(context).inkMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PelviSpace.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.labelLarge),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
