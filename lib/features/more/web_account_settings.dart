import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/auth.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/show_snack.dart';
import '../notes/soap_templates.dart';
import '../shell/desktop_chrome.dart';
import '../templates/template_body.dart';

/// Personal defaults for every signed-in role (desktop).
class WebAccountSettings extends StatefulWidget {
  const WebAccountSettings({super.key});

  @override
  State<WebAccountSettings> createState() => _WebAccountSettingsState();
}

enum _AccountSection {
  profile,
  scheduling,
  calendar,
  templates,
}

class _WebAccountSettingsState extends State<WebAccountSettings> {
  final _scroll = ScrollController();

  late final TextEditingController _name;

  bool _loaded = false;
  bool _applying = false;
  bool _dirty = false;
  String _templateId = blankId;
  List<SoapTemplate> _publishedTemplates = const [];
  _AccountSection _section = _AccountSection.profile;

  int _durationMins = 60;
  String _opens = AppDatabase.defaultClinicHoursStart;
  String _closes = AppDatabase.defaultClinicHoursEnd;
  String _timezone = AppDatabase.defaultTimezone;

  String _snapName = '';
  int _snapDurationMins = 60;
  String _snapOpens = AppDatabase.defaultClinicHoursStart;
  String _snapCloses = AppDatabase.defaultClinicHoursEnd;
  String _snapTimezone = AppDatabase.defaultTimezone;
  String _snapTemplateId = blankId;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController()..addListener(_onFieldChanged);
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
    final published = await publishedSoapTemplateChoices(db);
    final resolved = published.any((t) => t.id == tmpl)
        ? tmpl
        : (published.isNotEmpty ? published.first.id : blankId);
    if (!mounted) return;
    setState(() {
      _snapName = name;
      _snapDurationMins = mins;
      _snapOpens = hours.$1;
      _snapCloses = hours.$2;
      _snapTimezone = tz;
      _publishedTemplates = published;
      _snapTemplateId = resolved;
      _applySnapshot();
      _dirty = false;
    });
  }

  void _applySnapshot() {
    _applying = true;
    _name.text = _snapName;
    _durationMins = _snapDurationMins;
    _opens = _snapOpens;
    _closes = _snapCloses;
    _timezone = _snapTimezone;
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
    final mins = AppDatabase.normalizeAppointmentMinutes(_durationMins);
    final opens = _opens;
    final closes = _closes;
    final tzRaw = _timezone.trim().isEmpty
        ? AppDatabase.defaultTimezone
        : _timezone.trim();

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
      _snapDurationMins = mins;
      _snapOpens = opens;
      _snapCloses = closes;
      _snapTimezone = tzRaw;
      _snapTemplateId = _templateId;
      _applySnapshot();
      _dirty = false;
    });
    showPelviSnackBar(context, 'Account settings saved');
  }

  Future<void> _pickClinicTime({required bool opens}) async {
    final raw = opens ? _opens : _closes;
    final parts = raw.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.first) ?? (opens ? 9 : 18),
      minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked == null) return;
    final hhmm =
        '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (opens) {
        _opens = hhmm;
      } else {
        _closes = hhmm;
      }
      _dirty = true;
    });
  }

  void _goSection(_AccountSection section) {
    setState(() => _section = section);
  }

  Future<void> _toggleGoogleCalendar(bool enable) async {
    final gcal = AppDatabaseProvider.googleCalendarOf(context);
    if (gcal == null) {
      showPelviSnackBar(context, 'Google Calendar sync is unavailable');
      return;
    }
    if (!enable) {
      await gcal.disable();
      return;
    }
    showPelviSnackBar(
      context,
      'Finish Google consent in the browser…',
    );
    final ok = await gcal.enable();
    if (!mounted) return;
    if (!ok) {
      showPelviSnackBar(
        context,
        'Calendar permission was denied or timed out — sync stays off',
      );
      return;
    }
    showPelviSnackBar(context, 'Google Calendar connected');
  }

  int get _publishedCount => _publishedTemplates.length;

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
              _LabeledControl(
                label: 'Default duration',
                helper: 'Used when the appointment end time is unset.',
                child: _MinutesDropdown(
                  value: _durationMins,
                  onChanged: (v) {
                    setState(() {
                      _durationMins = v;
                      _dirty = true;
                    });
                  },
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _LabeledControl(
                      label: 'Clinic opens',
                      child: _TimeField(
                        value: _opens,
                        onTap: () => unawaited(_pickClinicTime(opens: true)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _LabeledControl(
                      label: 'Clinic closes',
                      child: _TimeField(
                        value: _closes,
                        onTap: () => unawaited(_pickClinicTime(opens: false)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Divider(height: 1, color: c.border),
              const SizedBox(height: 18),
              _LabeledControl(
                label: 'Timezone',
                helper: 'Label only (device clock).',
                child: _TimezoneDropdown(
                  value: _timezone,
                  onChanged: (v) {
                    setState(() {
                      _timezone = v;
                      _dirty = true;
                    });
                  },
                ),
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
                        '$_opens–$_closes.',
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
      _AccountSection.calendar => _Panel(
          title: 'Google Calendar',
          child: StreamBuilder<bool>(
            stream: AppDatabaseProvider.of(context)
                .watchGoogleCalendarSyncEnabled(),
            builder: (context, enabledSnap) {
              final on = enabledSnap.data ?? false;
              return StreamBuilder<String>(
                stream: AppDatabaseProvider.of(context)
                    .watchGoogleCalendarSyncStatus(),
                builder: (context, statusSnap) {
                  final status = statusSnap.data ?? '';
                  final statusLine = !on
                      ? null
                      : switch (status) {
                          'connected' => 'Connected',
                          'connecting' =>
                            'Connecting… finish Google consent in the browser',
                          'needs_permission' => 'Needs permission',
                          'error' => 'Temporary error',
                          _ => 'Connecting…',
                        };
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Sync my appointments to Google Calendar',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: c.ink,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Creates and updates events on your Google '
                                  'primary calendar. Client names appear in '
                                  'event titles.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.45,
                                    color: c.inkMuted,
                                  ),
                                ),
                                if (statusLine != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    statusLine,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: c.inkMuted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Switch.adaptive(
                            value: on,
                            onChanged: (v) => _toggleGoogleCalendar(v),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
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
                templates: _publishedTemplates,
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
            DesktopPageHeader(
              title: 'Account settings',
              actions: [
                DesktopOutlineAction(
                  label: 'Discard changes',
                  onPressed: _dirty ? _discard : null,
                ),
                DesktopFilledAction(
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
        item(_AccountSection.calendar, 'Google Calendar'),
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
    return _LabeledControl(
      label: label,
      helper: helper,
      child: TextField(
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
    );
  }
}

class _LabeledControl extends StatelessWidget {
  const _LabeledControl({
    required this.label,
    required this.child,
    this.helper,
  });

  final String label;
  final Widget child;
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
        child,
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

class _MinutesDropdown extends StatelessWidget {
  const _MinutesDropdown({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final selected = AppDatabase.allowedAppointmentMinutes.contains(value)
        ? value
        : AppDatabase.normalizeAppointmentMinutes(value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(PelviRadius.sm),
        border: Border.all(color: c.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: selected,
          isExpanded: true,
          icon: Icon(Icons.expand_more, color: c.inkMuted, size: 20),
          style: TextStyle(fontSize: 13, height: 1.5, color: c.ink),
          items: [
            for (final m in AppDatabase.allowedAppointmentMinutes)
              DropdownMenuItem(value: m, child: Text('$m minutes')),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({required this.value, required this.onTap});

  final String value;
  final VoidCallback onTap;

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
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PelviRadius.sm),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(fontSize: 13, height: 1.5, color: c.ink),
                ),
              ),
              Icon(Icons.schedule, size: 18, color: c.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimezoneDropdown extends StatelessWidget {
  const _TimezoneDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final zones = [
      if (value.isNotEmpty && !AppDatabase.commonTimezones.contains(value))
        value,
      ...AppDatabase.commonTimezones,
    ];
    final selected =
        zones.contains(value) ? value : AppDatabase.defaultTimezone;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(PelviRadius.sm),
        border: Border.all(color: c.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          isExpanded: true,
          icon: Icon(Icons.expand_more, color: c.inkMuted, size: 20),
          style: TextStyle(fontSize: 13, height: 1.5, color: c.ink),
          items: [
            for (final z in zones)
              DropdownMenuItem(
                value: z,
                child: Text(AppDatabase.timezoneLabel(z)),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _TemplateDropdown extends StatelessWidget {
  const _TemplateDropdown({
    required this.value,
    required this.templates,
    required this.onChanged,
  });

  final String value;
  final List<SoapTemplate> templates;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final items = templates.isEmpty
        ? soapTemplates
            .where((t) => !draftBuiltinTemplateIds.contains(t.id))
            .toList()
        : templates;
    final selected = items.any((t) => t.id == value)
        ? value
        : (items.isNotEmpty ? items.first.id : blankId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(PelviRadius.sm),
        border: Border.all(color: c.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          isExpanded: true,
          icon: Icon(Icons.expand_more, color: c.inkMuted, size: 20),
          style: TextStyle(fontSize: 13, height: 1.5, color: c.ink),
          items: [
            for (final t in items)
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

