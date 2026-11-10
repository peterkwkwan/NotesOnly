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
import '../notes/soap_templates.dart';
import '../org/org_access_screen.dart';
import '../shell/desktop_chrome.dart';
import 'practice_members_panel.dart';

/// Figma `NotesOnly · Practice settings` (`47:22570`) — desktop body only.
class WebPracticeSettings extends StatefulWidget {
  const WebPracticeSettings({super.key});

  @override
  State<WebPracticeSettings> createState() => _WebPracticeSettingsState();
}

enum _SettingsSection {
  preferences,
  members,
  scheduling,
  recall,
  templates,
  data,
}

class _WebPracticeSettingsState extends State<WebPracticeSettings> {
  final _scroll = ScrollController();
  final _prefKey = GlobalKey();
  final _membersKey = GlobalKey();
  final _schedKey = GlobalKey();
  final _recallKey = GlobalKey();
  final _tmplKey = GlobalKey();
  final _dataKey = GlobalKey();

  late final TextEditingController _name;
  late final TextEditingController _duration;
  late final TextEditingController _opens;
  late final TextEditingController _closes;
  late final TextEditingController _timezone;
  late final TextEditingController _recallDays;

  bool _loaded = false;
  bool _applying = false;
  bool _dirty = false;
  bool _recallNotifs = true;
  String _templateId = blankId;
  _SettingsSection _section = _SettingsSection.preferences;

  // Snapshots for Discard.
  String _snapName = '';
  String _snapDuration = '';
  String _snapOpens = '';
  String _snapCloses = '';
  String _snapTimezone = '';
  String _snapRecallDays = '';
  bool _snapRecallNotifs = true;
  String _snapTemplateId = blankId;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController()..addListener(_onFieldChanged);
    _duration = TextEditingController()..addListener(_onFieldChanged);
    _opens = TextEditingController()..addListener(_onFieldChanged);
    _closes = TextEditingController()..addListener(_onFieldChanged);
    _timezone = TextEditingController()..addListener(_onFieldChanged);
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
    _name.dispose();
    _duration.dispose();
    _opens.dispose();
    _closes.dispose();
    _timezone.dispose();
    _recallDays.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (!_loaded || _applying) return;
    setState(() => _dirty = true);
  }

  Future<void> _loadFromDb() async {
    final db = AppDatabaseProvider.of(context);
    final name = (await db.getPractitionerName()) ?? '';
    final mins = await db.getDefaultAppointmentMinutes();
    final hours = await db.watchClinicHours().first;
    final tz = await db.getTimezone();
    final recall = await db.getRecallDays();
    final notifs = await db.getRecallNotificationsEnabled();
    final tmpl = await db.getSetting('default_soap_template') ?? blankId;
    if (!mounted) return;
    setState(() {
      _snapName = name;
      _snapDuration = '$mins minutes';
      _snapOpens = hours.$1;
      _snapCloses = hours.$2;
      _snapTimezone = tz.replaceAll('_', ' ');
      _snapRecallDays = recall <= 0 ? 'Never' : '$recall days';
      _snapRecallNotifs = notifs;
      _snapTemplateId = soapTemplateById(tmpl).id;
      _applySnapshot();
      _dirty = false;
    });
  }

  void _applySnapshot() {
    _applying = true;
    _name.text = _snapName;
    _duration.text = _snapDuration;
    _opens.text = _snapOpens;
    _closes.text = _snapCloses;
    _timezone.text = _snapTimezone;
    _recallDays.text = _snapRecallDays;
    _recallNotifs = _snapRecallNotifs;
    _templateId = _snapTemplateId;
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
    final name = _name.text.trim();
    if (name.isEmpty) {
      showPelviSnackBar(context, 'Practitioner name cannot be empty');
      return;
    }
    final mins = _parseMinutes(_duration.text);
    if (mins == null) {
      showPelviSnackBar(context, 'Default duration must be a number of minutes');
      return;
    }
    final opens = _normalizeHhmm(_opens.text);
    final closes = _normalizeHhmm(_closes.text);
    if (opens == null || closes == null) {
      showPelviSnackBar(context, 'Clinic hours must look like 09:00');
      return;
    }
    final recall = _parseRecallDays(_recallDays.text);
    if (recall == null) {
      showPelviSnackBar(context, 'Recall window must be Never or N days');
      return;
    }
    final tzRaw = _timezone.text.trim().replaceAll(' ', '_');
    if (tzRaw.isEmpty) {
      showPelviSnackBar(context, 'Timezone cannot be empty');
      return;
    }

    await db.setPractitionerName(name);
    await db.setDefaultAppointmentMinutes(mins);
    await db.setClinicHoursStart(opens);
    await db.setClinicHoursEnd(closes);
    await db.setTimezone(tzRaw);
    await db.setRecallDays(recall);
    await db.setRecallNotificationsEnabled(_recallNotifs);
    // shortcut: key not in ensureDefaults; note editor does not read it yet
    await db.setSetting('default_soap_template', _templateId);

    if (!mounted) return;
    setState(() {
      _snapName = name;
      _snapDuration = '$mins minutes';
      _snapOpens = opens;
      _snapCloses = closes;
      _snapTimezone = tzRaw.replaceAll('_', ' ');
      _snapRecallDays = recall <= 0 ? 'Never' : '$recall days';
      _snapRecallNotifs = _recallNotifs;
      _snapTemplateId = _templateId;
      _applySnapshot();
      _dirty = false;
    });
    showPelviSnackBar(context, 'Practice settings saved');
  }

  static int? _parseMinutes(String raw) {
    final m = RegExp(r'(\d+)').firstMatch(raw.trim());
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  static int? _parseRecallDays(String raw) {
    final t = raw.trim().toLowerCase();
    if (t == 'never' || t == '0' || t == '0 days') return 0;
    final m = RegExp(r'(\d+)').firstMatch(t);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  static String? _normalizeHhmm(String raw) {
    final t = raw.trim();
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t);
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!);
    final min = int.tryParse(m.group(2)!);
    if (h == null || min == null || h > 23 || min > 59) return null;
    return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }

  void _goSection(_SettingsSection section) {
    setState(() => _section = section);
    final key = switch (section) {
      _SettingsSection.preferences => _prefKey,
      _SettingsSection.members => _membersKey,
      _SettingsSection.scheduling => _schedKey,
      _SettingsSection.recall => _recallKey,
      _SettingsSection.templates => _tmplKey,
      _SettingsSection.data => _dataKey,
    };
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
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

  int get _publishedCount =>
      soapTemplates.where((t) => !t.isBlank).length;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final displayName =
        _name.text.trim().isEmpty ? 'Practitioner' : _name.text.trim();

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
                        'The small defaults that keep your day running smoothly',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: c.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
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
                final mainCol = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    KeyedSubtree(
                      key: _prefKey,
                      child: _Panel(
                        title: 'Practice preferences',
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
                                    practitionerInitials(displayName),
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
                                      displayName,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: c.ink,
                                        height: 1.5,
                                      ),
                                    ),
                                    Text(
                                      'Practitioner',
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
                              label: 'Practitioner name',
                              controller: _name,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    KeyedSubtree(
                      key: _membersKey,
                      child: const _Panel(
                        title: 'Members',
                        child: PracticeMembersPanel(),
                      ),
                    ),
                    const SizedBox(height: 22),
                    KeyedSubtree(
                      key: _schedKey,
                      child: _Panel(
                        title: 'Scheduling defaults',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Field(
                              label: 'Default duration',
                              controller: _duration,
                              helper:
                                  'Used when the appointment end time is unset.',
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: _Field(
                                    label: 'Clinic opens',
                                    controller: _opens,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _Field(
                                    label: 'Clinic closes',
                                    controller: _closes,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Divider(height: 1, color: c.border),
                            const SizedBox(height: 18),
                            _Field(
                              label: 'Timezone',
                              controller: _timezone,
                              helper: 'Label only (device clock).',
                            ),
                            const SizedBox(height: 18),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: c.canvas,
                                borderRadius:
                                    BorderRadius.circular(PelviRadius.sm),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.schedule,
                                      size: 16, color: c.inkMuted),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'The week view uses your clinic hours, '
                                      '${_opens.text.trim().isEmpty ? '09:00' : _opens.text.trim()}–'
                                      '${_closes.text.trim().isEmpty ? '18:00' : _closes.text.trim()}.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        height: 1.5,
                                        color: c.inkMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    KeyedSubtree(
                      key: _tmplKey,
                      child: _Panel(
                        title: 'Template defaults',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Default SOAP template',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: c.ink,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 7),
                            _TemplateDropdown(
                              value: _templateId,
                              onChanged: (id) {
                                setState(() {
                                  _templateId = id;
                                  _dirty = true;
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Start with four open SOAP sections. You can choose another published template when writing a note.',
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.5,
                                color: c.inkMuted,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                InkWell(
                                  onTap: () => ShellNavigation.of(context)
                                      .goTo(DesktopDest.templates),
                                  child: Text(
                                    'Manage SOAP templates →',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: c.pink700,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.purple50,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '$_publishedCount published',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: c.purple700,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
                final sideCol = SizedBox(
                  width: wide ? 360 : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      KeyedSubtree(
                        key: _recallKey,
                        child: _Panel(
                          title: 'Recall management',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _Field(
                                label: 'Recall window',
                                controller: _recallDays,
                                helper:
                                    'Clients with no visit in the window appear in Due.',
                              ),
                              const SizedBox(height: 18),
                              Divider(height: 1, color: c.border),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                onPressed: () => ShellNavigation.of(context)
                                    .goTo(DesktopDest.clients),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      KeyedSubtree(
                        key: _dataKey,
                        child: _Panel(
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
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Exports are separate from practice preference changes.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.5,
                          color: c.inkMuted,
                        ),
                      ),
                    ],
                  ),
                );

                if (!wide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      subnav,
                      const SizedBox(height: 22),
                      mainCol,
                      const SizedBox(height: 22),
                      sideCol,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    subnav,
                    const SizedBox(width: 24),
                    Expanded(child: mainCol),
                    const SizedBox(width: 24),
                    sideCol,
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
        item(_SettingsSection.preferences, 'Practice preferences'),
        item(_SettingsSection.members, 'Members'),
        item(_SettingsSection.scheduling, 'Scheduling'),
        item(_SettingsSection.recall, 'Recall management'),
        item(_SettingsSection.templates, 'Template defaults'),
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
                'Review your practice defaults in one place. Changes are saved when you choose Save changes.',
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

class _TemplateDropdown extends StatelessWidget {
  const _TemplateDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(PelviRadius.sm),
        border: Border.all(color: c.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.expand_more, color: c.inkMuted, size: 20),
          style: TextStyle(fontSize: 13, height: 1.5, color: c.ink),
          items: [
            for (final t in soapTemplates)
              DropdownMenuItem(value: t.id, child: Text(t.label)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
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

/// Compact sync status + Sync now (assignment: data & backup / sync).
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
