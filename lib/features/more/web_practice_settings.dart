import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/backup.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/online.dart';
import '../../data/sync.dart';
import '../../theme/theme.dart';
import '../../widgets/desktop_settings_controls.dart';
import '../../widgets/show_snack.dart';
import '../shell/desktop_chrome.dart';
import 'practice_members_panel.dart';

/// Figma `NotesOnly · Practice settings` — Owner/Admin clinic settings.
class WebPracticeSettings extends StatefulWidget {
  const WebPracticeSettings({super.key});

  @override
  State<WebPracticeSettings> createState() => _WebPracticeSettingsState();
}

enum _SettingsSection {
  members,
  recall,
  data,
  preferences,
}

class _WebPracticeSettingsState extends State<WebPracticeSettings> {
  final _scroll = ScrollController();

  late final TextEditingController _clinicName;
  late final TextEditingController _recallDays;

  bool _loaded = false;
  bool _applying = false;
  bool _dirty = false;
  bool _recallNotifs = true;
  _SettingsSection _section = _SettingsSection.members;

  String _snapClinicName = '';
  int _snapRecallDays = 30;
  bool _snapRecallNotifs = true;

  @override
  void initState() {
    super.initState();
    _clinicName = TextEditingController()..addListener(_onFieldChanged);
    _recallDays = TextEditingController(text: '30')
      ..addListener(_onFieldChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      unawaited(_loadFromDb());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _clinicName.dispose();
    _recallDays.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (!_loaded || _applying) return;
    setState(() => _dirty = true);
  }

  Future<void> _loadFromDb() async {
    final db = AppDatabaseProvider.of(context);
    final name = (await db.getClinicName()) ?? '';
    final recall = await db.getRecallDays();
    final notifs = await db.getRecallNotificationsEnabled();
    if (!mounted) return;
    setState(() {
      _snapClinicName = name;
      _snapRecallDays = recall < 0 ? 30 : recall;
      _snapRecallNotifs = notifs;
      _applySnapshot();
      _dirty = false;
    });
  }

  void _applySnapshot() {
    _applying = true;
    _clinicName.text = _snapClinicName;
    _recallDays.text = '$_snapRecallDays';
    _recallNotifs = _snapRecallNotifs;
    _applying = false;
  }

  void _discard() {
    setState(() {
      _applySnapshot();
      _dirty = false;
    });
  }

  Future<void> _save() async {
    final db = AppDatabaseProvider.of(context);
    final name = _clinicName.text.trim();
    if (name.isEmpty) {
      showPelviSnackBar(context, 'Clinic name cannot be empty');
      return;
    }
    final recall = int.tryParse(_recallDays.text.trim());
    if (recall == null || recall < 0) {
      showPelviSnackBar(context, 'Recall window must be a number of days');
      return;
    }

    await db.setClinicName(name);
    await db.setRecallDays(recall);
    await db.setRecallNotificationsEnabled(_recallNotifs);

    if (!mounted) return;
    setState(() {
      _snapClinicName = name;
      _snapRecallDays = recall;
      _snapRecallNotifs = _recallNotifs;
      _applySnapshot();
      _dirty = false;
    });
    showPelviSnackBar(context, 'Practice settings saved');
  }

  void _goSection(_SettingsSection section) {
    setState(() => _section = section);
  }

  Widget _sectionBody(PelviPalette c, String clinicLabel) {
    return switch (_section) {
      _SettingsSection.preferences => _Panel(
          title: 'Clinic name',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                clinicLabel,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: c.ink,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              DesktopSettingsRow(
                label: 'Clinic name',
                helper: 'Shown in the sidebar for everyone in this clinic.',
                showDivider: false,
                control: DesktopSettingsTextControl(
                  controller: _clinicName,
                  width: 260,
                ),
              ),
            ],
          ),
        ),
      _SettingsSection.members => const _Panel(
          title: 'Members',
          child: PracticeMembersPanel(),
        ),
      _SettingsSection.recall => _Panel(
          title: 'Recall management',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DesktopSettingsRow(
                label: 'Recall window',
                helper: 'Clients with no visit in the window appear in Due.',
                control: DesktopSettingsTextControl(
                  controller: _recallDays,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  suffixText: 'days',
                ),
              ),
              DesktopSettingsRow(
                label: 'Recall notifications',
                helper: 'Daily local reminder when clients are due',
                control: Switch.adaptive(
                  value: _recallNotifs,
                  onChanged: (v) {
                    setState(() {
                      _recallNotifs = v;
                      _dirty = true;
                    });
                  },
                ),
              ),
              DesktopSettingsRow(
                label: 'Individual recall preferences',
                helper:
                    'Mute recalls in a client profile to exclude that client from Due. Review selected clients together in the directory.',
                showDivider: false,
                control: _PinkSoftAction(
                  icon: Icons.people_outline,
                  label: 'Open recall management',
                  onPressed: () =>
                      ShellNavigation.of(context).goTo(DesktopDest.clients),
                ),
              ),
            ],
          ),
        ),
      _SettingsSection.data => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Panel(
              title: 'Data & backup',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DesktopSettingsRow(
                    label: 'Export JSON backup',
                    helper: 'Clients, appointments, notes + settings',
                    control: DesktopOutlineAction(
                      icon: Icons.download_outlined,
                      label: 'Export JSON',
                      onPressed: () => unawaited(_exportJson()),
                    ),
                  ),
                  DesktopSettingsRow(
                    label: 'Export CSV',
                    helper:
                        'Three spreadsheet files: clients, appointments and notes.',
                    control: DesktopOutlineAction(
                      icon: Icons.download_outlined,
                      label: 'Export CSV',
                      onPressed: () => unawaited(_exportCsv()),
                    ),
                  ),
                  const _WebSyncRow(),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Exports are separate from clinic preference changes.',
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: c.inkMuted,
              ),
            ),
          ],
        ),
    };
  }

  Future<void> _exportJson() async {
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
      if (mounted) showPelviSnackBar(context, 'Export failed: $e');
    }
  }

  Future<void> _exportCsv() async {
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
      if (mounted) showPelviSnackBar(context, 'CSV export failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final clinicLabel =
        _clinicName.text.trim().isEmpty ? 'Clinic' : _clinicName.text.trim();
    final showSave = _section != _SettingsSection.members &&
        _section != _SettingsSection.data;

    return ColoredBox(
      color: c.canvas,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopPageHeader(
              title: 'Practice settings',
              actions: [
                if (showSave) ...[
                  DesktopOutlineAction(
                    label: 'Discard changes',
                    onPressed: _dirty ? _discard : null,
                  ),
                  DesktopFilledAction(
                    label: 'Save changes',
                    onPressed: _dirty ? () => unawaited(_save()) : null,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 26),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 980;
                final subnav = SizedBox(
                  width: 176,
                  child: _Subnav(
                    section: _section,
                    onSelect: _goSection,
                  ),
                );
                final body = _sectionBody(c, clinicLabel);
                if (!wide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      subnav,
                      const SizedBox(height: 22),
                      body,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    subnav,
                    const SizedBox(width: 24),
                    Expanded(child: body),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Subnav extends StatelessWidget {
  const _Subnav({required this.section, required this.onSelect});

  final _SettingsSection section;
  final ValueChanged<_SettingsSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    Widget item(_SettingsSection s, String label) {
      final selected = section == s;
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: selected ? c.pink50 : Colors.transparent,
          borderRadius: BorderRadius.circular(PelviRadius.sm),
          child: InkWell(
            onTap: () => onSelect(s),
            borderRadius: BorderRadius.circular(PelviRadius.sm),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? c.pink700 : c.inkMuted,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        item(_SettingsSection.members, 'Members'),
        item(_SettingsSection.recall, 'Recall management'),
        item(_SettingsSection.data, 'Data & backup'),
        item(_SettingsSection.preferences, 'Clinic name'),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _PinkSoftAction extends StatelessWidget {
  const _PinkSoftAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Material(
      color: c.pink50,
      borderRadius: BorderRadius.circular(PelviRadius.sm),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(PelviRadius.sm),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: c.pink700),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.pink700,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WebSyncRow extends StatefulWidget {
  const _WebSyncRow();

  @override
  State<_WebSyncRow> createState() => _WebSyncRowState();
}

class _WebSyncRowState extends State<_WebSyncRow> {
  bool _online = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshOnline());
  }

  Future<void> _refreshOnline() async {
    final online = await deviceLooksOnline();
    if (!mounted) return;
    if (online != _online) setState(() => _online = online);
  }

  Future<void> _syncNow() async {
    if (!_online || _busy) return;
    setState(() => _busy = true);
    final sync = AppDatabaseProvider.syncOf(context);
    final status = await sync.syncNow();
    if (!mounted) return;
    setState(() => _busy = false);
    showPelviSnackBar(
      context,
      status == SyncStatus.synced
          ? 'Synced'
          : 'Could not sync — try again',
    );
    unawaited(_refreshOnline());
  }

  @override
  Widget build(BuildContext context) {
    final db = AppDatabaseProvider.of(context);
    final sync = AppDatabaseProvider.syncOf(context);
    return StreamBuilder<SyncStatus>(
      stream: sync.watchStatus(),
      initialData: SyncStatus.idle,
      builder: (context, snap) {
        final status = snap.data ?? SyncStatus.idle;
        final label = switch (status) {
          SyncStatus.synced => 'Up to date',
          SyncStatus.pending => 'Waiting to sync',
          SyncStatus.syncing => 'Updating…',
          SyncStatus.error => 'Could not sync',
          SyncStatus.idle => 'Not syncing',
        };
        return StreamBuilder<String?>(
          stream: db.watchSetting(AppDatabase.syncLastSuccessKey),
          builder: (context, lastSnap) {
            final last = lastSnap.data;
            final detail = switch (status) {
              SyncStatus.synced => (last == null || last.isEmpty)
                  ? 'Your clinic data is up to date'
                  : 'Last updated $last',
              SyncStatus.pending => 'Will update when you are back online',
              SyncStatus.syncing => 'Updating…',
              SyncStatus.error => 'Tap Sync now to try again',
              SyncStatus.idle => 'Sign in to keep devices in sync',
            };
            return DesktopSettingsRow(
              label: 'Cloud sync · $label',
              helper: detail,
              showDivider: false,
              control: DesktopOutlineAction(
                icon: Icons.cloud_sync_outlined,
                label: _busy
                    ? 'Updating…'
                    : (!_online ? 'Offline' : 'Sync now'),
                onPressed: (!_online || _busy)
                    ? null
                    : () => unawaited(_syncNow()),
              ),
            );
          },
        );
      },
    );
  }
}
