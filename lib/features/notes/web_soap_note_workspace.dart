import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/show_snack.dart';
import '../clients/client_format.dart';
import '../clients/client_profile_screen.dart';
import 'dictation_apply_sheet.dart';
import 'note_format.dart';
import 'soap_dictation.dart';
import 'soap_templates.dart';

/// Figma `NotesOnly · SOAP note workspace` page body (shell supplies chrome).
class WebSoapNoteWorkspace extends StatefulWidget {
  const WebSoapNoteWorkspace({
    super.key,
    required this.noteId,
    required this.onBreadcrumb,
  });

  final int noteId;
  final ValueChanged<String?> onBreadcrumb;

  @override
  State<WebSoapNoteWorkspace> createState() => _WebSoapNoteWorkspaceState();
}

class _WebSoapNoteWorkspaceState extends State<WebSoapNoteWorkspace> {
  final _subjective = TextEditingController();
  final _objective = TextEditingController();
  final _assessment = TextEditingController();
  final _plan = TextEditingController();
  final _subjectiveFocus = FocusNode();
  final _objectiveFocus = FocusNode();
  final _assessmentFocus = FocusNode();
  final _planFocus = FocusNode();

  final SpeechToText _speech = SpeechToText();
  bool _speechReady = false;
  bool _listening = false;
  bool _finishingDictation = false;
  String _liveWords = '';
  SoapSection _activeSection = SoapSection.subjective;
  SoapSection _lastSection = SoapSection.subjective;

  Note? _note;
  Client? _client;
  Appointment? _appointment;
  String? _practitioner;
  bool _loading = true;
  bool _saving = false;
  bool _hydrated = false;
  Timer? _saveDebounce;
  SoapTemplate _template = soapTemplateBlank;

  @override
  void initState() {
    super.initState();
    for (final n in [
      _subjectiveFocus,
      _objectiveFocus,
      _assessmentFocus,
      _planFocus,
    ]) {
      n.addListener(_onFocusChange);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didUpdateWidget(WebSoapNoteWorkspace old) {
    super.didUpdateWidget(old);
    if (old.noteId != widget.noteId) {
      _hydrated = false;
      _loading = true;
      _template = soapTemplateBlank;
      _load();
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    if (_speechReady) unawaited(_speech.cancel());
    for (final n in [
      _subjectiveFocus,
      _objectiveFocus,
      _assessmentFocus,
      _planFocus,
    ]) {
      n.removeListener(_onFocusChange);
      n.dispose();
    }
    _subjective.dispose();
    _objective.dispose();
    _assessment.dispose();
    _plan.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    final next = _sectionFromFocus();
    if (next != null && next != _activeSection) {
      setState(() => _activeSection = next);
    }
  }

  SoapSection? _sectionFromFocus() {
    if (_subjectiveFocus.hasFocus) return SoapSection.subjective;
    if (_objectiveFocus.hasFocus) return SoapSection.objective;
    if (_assessmentFocus.hasFocus) return SoapSection.assessment;
    if (_planFocus.hasFocus) return SoapSection.plan;
    return null;
  }

  FocusNode _focusFor(SoapSection s) => switch (s) {
        SoapSection.subjective => _subjectiveFocus,
        SoapSection.objective => _objectiveFocus,
        SoapSection.assessment => _assessmentFocus,
        SoapSection.plan => _planFocus,
      };

  TextEditingController _controllerFor(SoapSection section) => switch (section) {
        SoapSection.subjective => _subjective,
        SoapSection.objective => _objective,
        SoapSection.assessment => _assessment,
        SoapSection.plan => _plan,
      };

  Future<void> _load() async {
    final db = AppDatabaseProvider.of(context);
    final note = await db.getNote(widget.noteId);
    if (note == null) {
      if (mounted) {
        setState(() => _loading = false);
        widget.onBreadcrumb(null);
      }
      return;
    }
    final client = await db.getClient(note.clientId);
    final appt = note.appointmentId == null
        ? null
        : await db.getAppointment(note.appointmentId!);
    final name = await db.watchPractitionerName().first;
    if (!mounted) return;
    final when = appt?.startsAt ?? note.noteDate;
    final crumbClient = client == null ? 'Note' : clientDisplayName(client);
    widget.onBreadcrumb(
      'SOAP notes / $crumbClient / ${_shortDate(when)}',
    );
    setState(() {
      _note = note;
      _client = client;
      _appointment = appt;
      _practitioner = name;
      if (!_hydrated) {
        _subjective.text = note.subjective;
        _objective.text = note.objective;
        _assessment.text = note.assessment;
        _plan.text = note.plan;
        _hydrated = true;
      }
      _loading = false;
    });
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() async {
    final note = _note;
    if (note == null) return;
    setState(() => _saving = true);
    final db = AppDatabaseProvider.of(context);
    await db.updateNoteSoap(
      id: note.id,
      subjective: _subjective.text,
      objective: _objective.text,
      assessment: _assessment.text,
      plan: _plan.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
  }

  Future<void> _copyLastNote() async {
    final note = _note;
    if (note == null) return;
    final db = AppDatabaseProvider.of(context);
    final last = await db.getLastNoteForClient(
      note.clientId,
      exceptNoteId: note.id,
    );
    if (!mounted) return;
    if (last == null) {
      showPelviSnackBar(context, 'No earlier note to copy.');
      return;
    }
    final ok = await db.copySoapIntoNote(targetId: note.id, source: last);
    if (!ok || !mounted) return;
    setState(() {
      _subjective.text = last.subjective;
      _objective.text = last.objective;
      _assessment.text = last.assessment;
      _plan.text = last.plan;
      _template = soapTemplateBlank;
    });
    showPelviSnackBar(context, 'Copied last note.');
  }

  bool get _soapFieldsNonEmpty =>
      _subjective.text.trim().isNotEmpty ||
      _objective.text.trim().isNotEmpty ||
      _assessment.text.trim().isNotEmpty ||
      _plan.text.trim().isNotEmpty;

  int get _filledSectionCount {
    var n = 0;
    if (_subjective.text.trim().isNotEmpty) n++;
    if (_objective.text.trim().isNotEmpty) n++;
    if (_assessment.text.trim().isNotEmpty) n++;
    if (_plan.text.trim().isNotEmpty) n++;
    return n;
  }

  Future<void> _pickTemplate() async {
    final picked = await showPelviPickerSheet<SoapTemplate>(
      context: context,
      title: 'Template',
      selected: _template,
      options: [
        for (final t in soapTemplates)
          PelviPickerOption(value: t, label: t.label),
      ],
    );
    if (!mounted || picked == null) return;
    if (picked.isBlank || !picked.hasFill) {
      setState(() => _template = soapTemplateBlank);
      return;
    }
    if (_soapFieldsNonEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Replace SOAP fields?'),
          content: Text(
            'This will overwrite Subjective, Objective, Assessment, and Plan '
            'with “${picked.label}”.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (!mounted || ok != true) return;
    }
    setState(() {
      _template = picked;
      _subjective.text = picked.subjective;
      _objective.text = picked.objective;
      _assessment.text = picked.assessment;
      _plan.text = picked.plan;
    });
    _scheduleSave();
  }

  Future<bool> _ensureSpeech() async {
    if (_speechReady) return true;
    final ok = await _speech.initialize(
      onStatus: _onSpeechStatus,
      onError: (e) {
        if (!mounted) return;
        showPelviSnackBar(context, 'Dictation error: ${e.errorMsg}');
      },
    );
    if (!mounted) return false;
    _speechReady = ok;
    if (!ok) {
      showPelviSnackBar(
        context,
        'Speech recognition unavailable. Check mic permission.',
      );
    }
    return ok;
  }

  void _onSpeechStatus(String status) {
    if (!mounted || !_listening) return;
    if (status == SpeechToText.doneStatus ||
        status == SpeechToText.notListeningStatus) {
      unawaited(_finishDictation());
    }
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await _finishDictation();
      return;
    }
    if (!await _ensureSpeech()) return;
    _liveWords = '';
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (r) {
        if (!mounted) return;
        setState(() => _liveWords = r.recognizedWords);
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
      ),
    );
  }

  Future<void> _finishDictation() async {
    if (_finishingDictation) return;
    _finishingDictation = true;
    try {
      if (_speech.isListening) await _speech.stop();
      if (!mounted) return;
      setState(() => _listening = false);
      final text = _liveWords.trim();
      _liveWords = '';
      if (text.isEmpty) {
        showPelviSnackBar(context, 'Nothing heard. Try again.');
        return;
      }
      final result = await showDictationApplySheet(
        context: context,
        initialText: text,
        initialSection: _lastSection,
      );
      if (!mounted || result == null) return;
      final c = _controllerFor(result.section);
      c.text = appendSoapTranscript(c.text, result.text);
      _lastSection = result.section;
      _scheduleSave();
      showPelviSnackBar(context, 'Appended to ${result.section.label}.');
    } finally {
      _finishingDictation = false;
    }
  }

  void _goToClientProfile() {
    final client = _client;
    if (client == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClientProfileScreen(clientId: client.id),
      ),
    );
  }

  void _selectSection(SoapSection section) {
    setState(() => _activeSection = section);
    _focusFor(section).requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    if (_loading) {
      return ColoredBox(
        color: c.canvas,
        child: Center(
          child: CircularProgressIndicator(color: c.pink700),
        ),
      );
    }
    final note = _note;
    if (note == null) {
      return ColoredBox(
        color: c.canvas,
        child: const Center(child: Text('Note not found.')),
      );
    }

    final client = _client;
    final when = _appointment?.startsAt ?? note.noteDate;
    final name = client == null ? 'SOAP note' : clientDisplayName(client);
    final filled = _filledSectionCount;

    return ColoredBox(
      color: c.canvas,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 980;
          final body = narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _VisitColumn(
                      client: client,
                      when: when,
                      appointment: _appointment,
                      practitioner: _practitioner,
                      active: _activeSection,
                      filledCount: filled,
                      onSelectSection: _selectSection,
                      onOpenClient: _goToClientProfile,
                    ),
                    const SizedBox(height: 24),
                    _EditorColumn(
                      listening: _listening,
                      liveWords: _liveWords,
                      templateLabel: _template.label,
                      subjective: _subjective,
                      objective: _objective,
                      assessment: _assessment,
                      plan: _plan,
                      subjectiveFocus: _subjectiveFocus,
                      objectiveFocus: _objectiveFocus,
                      assessmentFocus: _assessmentFocus,
                      planFocus: _planFocus,
                      onChanged: (_) {
                        setState(() {});
                        _scheduleSave();
                      },
                      onPickTemplate: _pickTemplate,
                      onCopyLast: _copyLastNote,
                      onDictate: _toggleMic,
                    ),
                    const SizedBox(height: 24),
                    _ContextColumn(
                      templateLabel: _template.label,
                      when: when,
                      appointment: _appointment,
                      practitioner: _practitioner,
                      filledCount: filled,
                      saving: _saving,
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 214,
                      child: _VisitColumn(
                        client: client,
                        when: when,
                        appointment: _appointment,
                        practitioner: _practitioner,
                        active: _activeSection,
                        filledCount: filled,
                        onSelectSection: _selectSection,
                        onOpenClient: _goToClientProfile,
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: _EditorColumn(
                        listening: _listening,
                        liveWords: _liveWords,
                        templateLabel: _template.label,
                        subjective: _subjective,
                        objective: _objective,
                        assessment: _assessment,
                        plan: _plan,
                        subjectiveFocus: _subjectiveFocus,
                        objectiveFocus: _objectiveFocus,
                        assessmentFocus: _assessmentFocus,
                        planFocus: _planFocus,
                        onChanged: (_) {
                          setState(() {});
                          _scheduleSave();
                        },
                        onPickTemplate: _pickTemplate,
                        onCopyLast: _copyLastNote,
                        onDictate: _toggleMic,
                      ),
                    ),
                    const SizedBox(width: 24),
                    SizedBox(
                      width: 258,
                      child: _ContextColumn(
                        templateLabel: _template.label,
                        when: when,
                        appointment: _appointment,
                        practitioner: _practitioner,
                        filledCount: filled,
                        saving: _saving,
                      ),
                    ),
                  ],
                );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PageHeader(
                  subtitle: '$name · ${formatNoteDate(when)}',
                  saving: _saving,
                  onSaveDraft: _save,
                ),
                const SizedBox(height: 26),
                body,
              ],
            ),
          );
        },
      ),
    );
  }
}

String _shortDate(DateTime dt) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
}

String _longDate(DateTime dt) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.subtitle,
    required this.saving,
    required this.onSaveDraft,
  });

  final String subtitle;
  final bool saving;
  final VoidCallback onSaveDraft;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SOAP note',
                style: TextStyle(
                  fontSize: 29,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: c.inkMuted,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: c.purple50,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Draft',
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: c.purple700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton(
          onPressed: onSaveDraft,
          style: FilledButton.styleFrom(
            backgroundColor: c.pink700,
            foregroundColor: c.inkInverse,
            elevation: 0,
            minimumSize: const Size(0, 38),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PelviRadius.sm),
            ),
          ),
          child: Text(
            saving ? 'Saving…' : 'Save draft',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _VisitColumn extends StatelessWidget {
  const _VisitColumn({
    required this.client,
    required this.when,
    required this.appointment,
    required this.practitioner,
    required this.active,
    required this.filledCount,
    required this.onSelectSection,
    required this.onOpenClient,
  });

  final Client? client;
  final DateTime when;
  final Appointment? appointment;
  final String? practitioner;
  final SoapSection active;
  final int filledCount;
  final ValueChanged<SoapSection> onSelectSection;
  final VoidCallback onOpenClient;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final avatar = client == null
        ? (wash: c.pink50, ink: c.pink700)
        : clientAvatarColors(client!, c);
    final initials = client == null ? '?' : clientInitials(client!);
    final display = client == null ? 'Client' : clientDisplayName(client!);
    final visitLine = appointment == null
        ? 'Standalone note · no appointment linked'
        : 'Appointment · ${formatApptTime(appointment!.startsAt)}';
    final pract = (practitioner ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(PelviRadius.button),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: avatar.wash,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    color: avatar.ink,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                display,
                style: TextStyle(
                  fontSize: 18,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                formatNoteDate(when),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: c.inkMuted,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                visitLine,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: c.inkMuted,
                ),
              ),
              const SizedBox(height: 18),
              Divider(height: 1, color: c.border),
              const SizedBox(height: 18),
              Text(
                'PRACTITIONER',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: c.inkMuted,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                pract.isEmpty ? '—' : pract,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 18),
              InkWell(
                onTap: client == null ? null : onOpenClient,
                child: Text(
                  'Open client →',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                    color: c.pink700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'NOTE OUTLINE',
          style: TextStyle(
            fontSize: 10,
            height: 1.5,
            fontWeight: FontWeight.w600,
            color: c.inkMuted,
          ),
        ),
        const SizedBox(height: 6),
        for (final s in SoapSection.values) ...[
          _OutlineRow(
            section: s,
            selected: active == s,
            onTap: () => onSelectSection(s),
          ),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 4),
        Text(
          '$filledCount of 4 sections contain clinical text.',
          style: TextStyle(
            fontSize: 11,
            height: 1.5,
            color: c.inkMuted,
          ),
        ),
      ],
    );
  }
}

class _OutlineRow extends StatelessWidget {
  const _OutlineRow({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final SoapSection section;
  final bool selected;
  final VoidCallback onTap;

  String get _letter => switch (section) {
        SoapSection.subjective => 'S',
        SoapSection.objective => 'O',
        SoapSection.assessment => 'A',
        SoapSection.plan => 'P',
      };

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Material(
      color: selected ? c.pink50 : Colors.transparent,
      borderRadius: BorderRadius.circular(PelviRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PelviRadius.sm),
        child: SizedBox(
          height: 41,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  _letter,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: c.pink700,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  section.label,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? c.pink700 : c.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorColumn extends StatelessWidget {
  const _EditorColumn({
    required this.listening,
    required this.liveWords,
    required this.templateLabel,
    required this.subjective,
    required this.objective,
    required this.assessment,
    required this.plan,
    required this.subjectiveFocus,
    required this.objectiveFocus,
    required this.assessmentFocus,
    required this.planFocus,
    required this.onChanged,
    required this.onPickTemplate,
    required this.onCopyLast,
    required this.onDictate,
  });

  final bool listening;
  final String liveWords;
  final String templateLabel;
  final TextEditingController subjective;
  final TextEditingController objective;
  final TextEditingController assessment;
  final TextEditingController plan;
  final FocusNode subjectiveFocus;
  final FocusNode objectiveFocus;
  final FocusNode assessmentFocus;
  final FocusNode planFocus;
  final ValueChanged<String> onChanged;
  final VoidCallback onPickTemplate;
  final VoidCallback onCopyLast;
  final VoidCallback onDictate;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(PelviRadius.button),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                FilledButton(
                  onPressed: onPickTemplate,
                  style: FilledButton.styleFrom(
                    backgroundColor: c.pink50,
                    foregroundColor: c.pink700,
                    elevation: 0,
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(PelviRadius.sm),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.expand_more, size: 16, color: c.pink700),
                      const SizedBox(width: 8),
                      Text(
                        templateLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.pink700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: onCopyLast,
                  icon: Icon(Icons.copy_outlined, size: 16, color: c.ink),
                  label: Text(
                    'Copy last note',
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
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(PelviRadius.sm),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // shortcut: formatting controls are visual-only until rich text lands
          Container(
            color: c.canvas,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            child: Row(
              children: [
                Text(
                  'Paragraph',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: c.inkMuted,
                  ),
                ),
                Icon(Icons.expand_more, size: 14, color: c.inkMuted),
                const SizedBox(width: 22),
                Text(
                  'B',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                const SizedBox(width: 22),
                Text(
                  'I',
                  style: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: c.ink,
                  ),
                ),
                const SizedBox(width: 22),
                Icon(Icons.format_list_bulleted, size: 16, color: c.ink),
                const SizedBox(width: 22),
                Icon(Icons.format_list_numbered, size: 16, color: c.ink),
                const SizedBox(width: 22),
                Icon(Icons.undo, size: 16, color: c.ink),
                const SizedBox(width: 22),
                InkWell(
                  onTap: onDictate,
                  child: Row(
                    children: [
                      Icon(
                        listening ? Icons.stop_rounded : Icons.mic_none_rounded,
                        size: 16,
                        color: c.pink700,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        listening ? 'Stop' : 'Dictate',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.5,
                          color: c.pink700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (listening)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Text(
                liveWords.isEmpty ? 'Listening…' : liveWords,
                style: TextStyle(fontSize: 13, color: c.pink700),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _SoapSectionField(
                  letter: 'S',
                  label: 'Subjective',
                  hint:
                      'Document the client’s reported concerns, history and goals.',
                  controller: subjective,
                  focusNode: subjectiveFocus,
                  onChanged: onChanged,
                ),
                const SizedBox(height: 22),
                _SoapSectionField(
                  letter: 'O',
                  label: 'Objective',
                  hint:
                      'Record observations and measurements, where relevant.',
                  controller: objective,
                  focusNode: objectiveFocus,
                  onChanged: onChanged,
                ),
                const SizedBox(height: 22),
                _SoapSectionField(
                  letter: 'A',
                  label: 'Assessment',
                  hint: 'Enter your clinical interpretation and reasoning.',
                  controller: assessment,
                  focusNode: assessmentFocus,
                  onChanged: onChanged,
                ),
                const SizedBox(height: 22),
                _SoapSectionField(
                  letter: 'P',
                  label: 'Plan',
                  hint:
                      'Document agreed next steps and follow-up considerations.',
                  controller: plan,
                  focusNode: planFocus,
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SoapSectionField extends StatelessWidget {
  const _SoapSectionField({
    required this.letter,
    required this.label,
    required this.hint,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final String letter;
  final String label;
  final String hint;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.purple50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                letter,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: c.purple700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          focusNode: focusNode,
          minLines: 3,
          maxLines: 8,
          onChanged: onChanged,
          style: TextStyle(fontSize: 14, height: 1.5, color: c.ink),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: c.inkMuted,
            ),
            filled: true,
            fillColor: c.surface,
            contentPadding: const EdgeInsets.all(14),
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
              borderSide: BorderSide(color: c.pink700, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _ContextColumn extends StatelessWidget {
  const _ContextColumn({
    required this.templateLabel,
    required this.when,
    required this.appointment,
    required this.practitioner,
    required this.filledCount,
    required this.saving,
  });

  final String templateLabel;
  final DateTime when;
  final Appointment? appointment;
  final String? practitioner;
  final int filledCount;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final pract = (practitioner ?? '').trim();
    final statusLine = filledCount == 0
        ? 'No clinical text has been entered in this draft.'
        : '$filledCount of 4 sections have clinical text.';
    final apptLine = appointment == null
        ? 'Appointment time not linked'
        : 'Appointment · ${formatApptTime(appointment!.startsAt)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(PelviRadius.button),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Note context',
                style: TextStyle(
                  fontSize: 17,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'TEMPLATE',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: c.inkMuted,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                templateLabel,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Four open SOAP sections. Prompts are guidance, not recorded findings.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: c.inkMuted,
                ),
              ),
              const SizedBox(height: 18),
              Divider(height: 1, color: c.border),
              const SizedBox(height: 18),
              Text(
                'VISIT DATE',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: c.inkMuted,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _longDate(when),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                apptLine,
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
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(PelviRadius.button),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Revision history',
                style: TextStyle(
                  fontSize: 17,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: c.purple50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Current draft',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                    color: c.purple700,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                statusLine,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: c.inkMuted,
                ),
              ),
              const SizedBox(height: 18),
              Divider(height: 1, color: c.border),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.history, size: 16, color: c.inkMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$templateLabel note',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                            color: c.ink,
                          ),
                        ),
                        Text(
                          '${_shortDate(when)} · ${pract.isEmpty ? 'Practitioner' : pract}',
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
              ),
              const SizedBox(height: 18),
              Text(
                saving
                    ? 'Saving on this device…'
                    : 'Save a draft to keep your writing before continuing.',
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
        Text(
          'Review the client and visit date before entering clinical information.',
          style: TextStyle(
            fontSize: 11,
            height: 1.5,
            color: c.inkMuted,
          ),
        ),
      ],
    );
  }
}
