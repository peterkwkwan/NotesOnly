import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/backup.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/online.dart';
import '../../data/sync.dart';
import '../../theme/theme.dart';
import '../../widgets/show_snack.dart';
import '../org/org_access_screen.dart';
import '../shell/desktop_chrome.dart';
import 'practice_members_panel.dart';

/// Figma `NotesOnly · Practice settings` — Owner/Admin clinic settings.
class WebPracticeSettings extends StatefulWidget {
  const WebPracticeSettings({super.key});

  @override
  State<WebPracticeSettings> createState() => _WebPracticeSettingsState();
}

enum _SettingsSection {
  preferences,
  members,
  recall,
  data,
}

class _WebPracticeSettingsState extends State<WebPracticeSettings> {
  final _scroll = ScrollController();

  late final TextEditingController _clinicName;
  late final TextEditingController _recallDays;

  bool _loaded = false;
  bool _applying = false;
  bool _dirty = false;
  bool _recallNotifs = true;
  _SettingsSection _section = _SettingsSection.preferences;

  String _snapClinicName = '';
  String _snapRecallDays = '';
  bool _snapRecallNotifs = true;

  @override
  void initState() {
    super.initState();
    _clinicName = TextEditingController()..addListener(_onFieldChanged);
    _recallDays = TextEditingController()..addListener(_onFieldChanged);
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
      _snapRecallDays = recall <= 0 ? 'Never' : '$recall days';
      _snapRecallNotifs = notifs;
      _applySnapshot();
      _dirty = false;
    });
  }

  void _applySnapshot() {
    _applying = true;
    _clinicName.text = _snapClinicName;
    _recallDays.text = _snapRecallDays;
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
    final recall = _parseRecallDays(_recallDays.text);
    if (recall == null) {
      showPelviSnackBar(context, 'Recall window must be Never or N days');
      return;
    }

    await db.setClinicName(name);
    await db.setRecallDays(recall);
    await db.setRecallNotificationsEnabled(_recallNotifs);

    if (!mounted) return;
    setState(() {
      _snapClinicName = name;
      _snapRecallDays = recall <= 0 ? 'Never' : '$recall days';
      _snapRecallNotifs = _recallNotifs;
      _applySnapshot();
      _dirty = false;
    });
    showPelviSnackBar(context, 'Practice settings saved');
  }

  static int? _parseRecallDays(String raw) {
    final t = raw.trim().toLowerCase();
    if (t == 'never' || t == '0' || t == '0 days') return 0;
    final m = RegExp(r'(\d+)').firstMatch(t);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
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
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.pink50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      practitionerInitials(clinicLabel),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: c.pink700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
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
                      Text(
                        'Organization',
                        style: TextStyle(
                          fontSize: 11,
                          color: c.inkMuted,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _Field(
                label: 'Clinic name',
                controller: _clinicName,
                helper: 'Shown in the sidebar for everyone in this clinic.',
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
              _Field(
                label: 'Recall window',
                controller: _recallDays,
                helper: 'Clients with no visit in the window appear in Due.',
              ),
              const SizedBox(height: 18),
              Divider(height: 1, color: c.border),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recall notifications',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: c.ink,
                            height: 1.5,
                          ),
                        ),
                        Text(
                          'Daily local reminder when clients are due',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.5,
                            color: c.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: _recallNotifs,
                    onChanged: (v) {
                      setState(() {
                        _recallNotifs = v;
                        _dirty = true;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Divider(height: 1, color: c.border),
              const SizedBox(height: 18),
              Text(
                'Individual recall preferences',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: c.ink,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Mute recalls in a client profile to exclude that client from Due. Review selected clients together in the directory.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: c.inkMuted,
                ),
              ),
              const SizedBox(height: 18),
              _PinkSoftAction(
                icon: Icons.people_outline,
                label: 'Open recall management',
                onPressed: () =>
                    ShellNavigation.of(context).goTo(DesktopDest.clients),
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
                  Text(
                    'Export JSON backup',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: c.ink,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Clients, appointments, notes + settings',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: c.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 9),
                  _OutlineAction(
                    icon: Icons.download_outlined,
                    label: 'Export JSON',
                    onPressed: () => unawaited(_exportJson()),
                  ),
                  const SizedBox(height: 18),
                  Divider(height: 1, color: c.border),
                  const SizedBox(height: 18),
                  Text(
                    'Export CSV',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: c.ink,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Three spreadsheet files: clients, appointments and notes.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: c.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 9),
                  _OutlineAction(
                    icon: Icons.download_outlined,
                    label: 'Export CSV',
                    onPressed: () => unawaited(_exportCsv()),
                  ),
                  const SizedBox(height: 18),
                  Divider(height: 1, color: c.border),
                  const SizedBox(height: 18),
                  Text(
                    'Cloud sync',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: c.ink,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const _WebSyncStrip(),
                  const SizedBox(height: 9),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const OrgAccessScreen(),
                          ),
                        );
                      },
                      child: const Text('Invites'),
                    ),
                  ),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const DesktopBreadcrumb(),
                      Text(
                        'Practice settings',
                        style: TextStyle(
                          fontSize: 29,
                          height: 1.5,
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Clinic-wide preferences for owners and admins',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: c.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (showSave) ...[
                  _OutlineAction(
                    label: 'Discard changes',
                    onPressed: _dirty ? _discard : null,
                  ),
                  const SizedBox(width: 10),
                  _FilledAction(
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
        item(_SettingsSection.preferences, 'Clinic name'),
        item(_SettingsSection.members, 'Members'),
        item(_SettingsSection.recall, 'Recall management'),
        item(_SettingsSection.data, 'Data & backup'),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.tune, size: 18, color: c.inkMuted),
              const SizedBox(height: 10),
              Text(
                'Clinic settings for owners and admins. Personal defaults live under Account settings.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: c.inkMuted,
                ),
              ),
            ],
          ),
        ),
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
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.helper,
  });

  final String label;
  final TextEditingController controller;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: c.ink,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          style: TextStyle(fontSize: 13, height: 1.5, color: c.ink),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.all(12),
            filled: true,
            fillColor: c.surface,
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
        if (helper != null) ...[
          const SizedBox(height: 7),
          Text(
            helper!,
            style: TextStyle(fontSize: 11, height: 1.5, color: c.inkMuted),
          ),
        ],
      ],
    );
  }
}

class _OutlineAction extends StatelessWidget {
  const _OutlineAction({
    required this.label,
    this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final enabled = onPressed != null;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(PelviRadius.sm),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(PelviRadius.sm),
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(PelviRadius.sm),
                border: Border.all(color: c.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: c.ink),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                      height: 1.5,
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
}

class _FilledAction extends StatelessWidget {
  const _FilledAction({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final enabled = onPressed != null;
    return Material(
      color: enabled ? c.pink700 : c.pink200,
      borderRadius: BorderRadius.circular(PelviRadius.sm),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(PelviRadius.sm),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.inkInverse,
              height: 1.5,
            ),
          ),
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
        child: Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
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
        ),
      ),
    );
  }
}

class _WebSyncStrip extends StatefulWidget {
  const _WebSyncStrip();

  @override
  State<_WebSyncStrip> createState() => _WebSyncStripState();
}

class _WebSyncStripState extends State<_WebSyncStrip> {
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
    final c = PelviColors.of(context);
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StreamBuilder<String?>(
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
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: status == SyncStatus.error
                            ? c.danger
                            : c.inkMuted,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 9),
            _OutlineAction(
              icon: Icons.cloud_sync_outlined,
              label: _busy
                  ? 'Updating…'
                  : (!_online ? 'Offline' : 'Sync now'),
              onPressed: (!_online || _busy)
                  ? null
                  : () => unawaited(_syncNow()),
            ),
          ],
        );
      },
    );
  }
}
