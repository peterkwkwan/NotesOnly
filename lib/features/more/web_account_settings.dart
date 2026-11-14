import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/auth.dart';
import '../../data/database_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/show_snack.dart';
import '../notes/soap_templates.dart';
import '../shell/desktop_chrome.dart';

/// Personal defaults for every signed-in role (desktop).
class WebAccountSettings extends StatefulWidget {
  const WebAccountSettings({super.key});

  @override
  State<WebAccountSettings> createState() => _WebAccountSettingsState();
}

enum _AccountSection {
  profile,
  scheduling,
  templates,
}

class _WebAccountSettingsState extends State<WebAccountSettings> {
  final _scroll = ScrollController();

  late final TextEditingController _name;
  late final TextEditingController _duration;
  late final TextEditingController _opens;
  late final TextEditingController _closes;
  late final TextEditingController _timezone;

  bool _loaded = false;
  bool _applying = false;
  bool _dirty = false;
  String _templateId = blankId;
  _AccountSection _section = _AccountSection.profile;

  String _snapName = '';
  String _snapDuration = '';
  String _snapOpens = '';
  String _snapCloses = '';
  String _snapTimezone = '';
  String _snapTemplateId = blankId;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController()..addListener(_onFieldChanged);
    _duration = TextEditingController()..addListener(_onFieldChanged);
    _opens = TextEditingController()..addListener(_onFieldChanged);
    _closes = TextEditingController()..addListener(_onFieldChanged);
    _timezone = TextEditingController()..addListener(_onFieldChanged);
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
    super.dispose();
  }

  void _onFieldChanged() {
    if (!_loaded || _applying) return;
    setState(() => _dirty = true);
  }

  Future<void> _loadFromDb() async {
    final db = AppDatabaseProvider.of(context);
    final name =
        (await db.getPractitionerName(uid: NotesAuth.currentUser?.uid)) ?? '';
    final mins = await db.getDefaultAppointmentMinutes();
    final hours = await db.watchClinicHours().first;
    final tz = await db.getTimezone();
    final tmpl = await db.getSetting('default_soap_template') ?? blankId;
    if (!mounted) return;
    setState(() {
      _snapName = name;
      _snapDuration = '$mins minutes';
      _snapOpens = hours.$1;
      _snapCloses = hours.$2;
      _snapTimezone = tz.replaceAll('_', ' ');
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
      showPelviSnackBar(context, 'Display name cannot be empty');
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
    final tzRaw = _timezone.text.trim().replaceAll(' ', '_');
    if (tzRaw.isEmpty) {
      showPelviSnackBar(context, 'Timezone cannot be empty');
      return;
    }

    await db.setPractitionerName(name, uid: NotesAuth.currentUser?.uid);
    await db.setDefaultAppointmentMinutes(mins);
    await db.setClinicHoursStart(opens);
    await db.setClinicHoursEnd(closes);
    await db.setTimezone(tzRaw);
    // shortcut: key not in ensureDefaults; note editor does not read it yet
    await db.setSetting('default_soap_template', _templateId);

    if (!mounted) return;
    setState(() {
      _snapName = name;
      _snapDuration = '$mins minutes';
      _snapOpens = opens;
      _snapCloses = closes;
      _snapTimezone = tzRaw.replaceAll('_', ' ');
      _snapTemplateId = _templateId;
      _applySnapshot();
      _dirty = false;
    });
    showPelviSnackBar(context, 'Account settings saved');
  }

  static int? _parseMinutes(String raw) {
    final m = RegExp(r'(\d+)').firstMatch(raw.trim());
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

  void _goSection(_AccountSection section) {
    setState(() => _section = section);
  }

  int get _publishedCount => soapTemplates.where((t) => !t.isBlank).length;

  Widget _sectionBody(PelviPalette c, String displayName) {
    final signedInEmail = NotesAuth.currentUser?.email?.trim() ?? '';
    return switch (_section) {
      _AccountSection.profile => _Panel(
          title: 'Personal Details',
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
                      if (signedInEmail.isNotEmpty)
                        Text(
                          signedInEmail,
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
                label: 'Display name',
                controller: _name,
                helper:
                    'Shown on the calendar when other members view your schedule.',
              ),
            ],
          ),
        ),
      _AccountSection.scheduling => _Panel(
          title: 'Scheduling defaults',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Field(
                label: 'Default duration',
                controller: _duration,
                helper: 'Used when the appointment end time is unset.',
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
                  borderRadius: BorderRadius.circular(PelviRadius.sm),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.schedule, size: 16, color: c.inkMuted),
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
      _AccountSection.templates => _Panel(
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
                    onTap: () =>
                        ShellNavigation.of(context).goTo(DesktopDest.templates),
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
    };
  }

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
                        'Account settings',
                        style: TextStyle(
                          fontSize: 29,
                          height: 1.5,
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Your name and the defaults you use every day',
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
                final body = _sectionBody(c, displayName);
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

  final _AccountSection section;
  final ValueChanged<_AccountSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    Widget item(_AccountSection s, String label) {
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
        item(_AccountSection.profile, 'Personal Details'),
        item(_AccountSection.scheduling, 'Scheduling'),
        item(_AccountSection.templates, 'Template defaults'),
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
