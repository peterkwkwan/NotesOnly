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

/// Always-editable SOAP note editor with autosave.
class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({super.key, required this.noteId});

  final int noteId;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final _subjective = TextEditingController();
  final _objective = TextEditingController();
  final _assessment = TextEditingController();
  final _plan = TextEditingController();

  // shortcut: OS STT streams text only (no local audio file to delete)
  final SpeechToText _speech = SpeechToText();
  bool _speechReady = false;
  bool _listening = false;
  bool _finishingDictation = false;
  String _liveWords = '';
  SoapSection _lastSection = SoapSection.subjective;

  Note? _note;
  Client? _client;
  Appointment? _appointment;
  bool _loading = true;
  bool _saving = false;
  bool _hydrated = false;
  Timer? _saveDebounce;
  SoapTemplate _template = soapTemplateBlank;

  @override
  void initState() {
    super.initState();
    // of() depends on InheritedWidget — illegal during initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    if (_speechReady) unawaited(_speech.cancel());
    _subjective.dispose();
    _objective.dispose();
    _assessment.dispose();
    _plan.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = AppDatabaseProvider.of(context);
    final note = await db.getNote(widget.noteId);
    if (note == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final client = await db.getClient(note.clientId);
    final appt = note.appointmentId == null
        ? null
        : await db.getAppointment(note.appointmentId!);
    if (!mounted) return;
    setState(() {
      _note = note;
      _client = client;
      _appointment = appt;
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

  TextEditingController _controllerFor(SoapSection section) => switch (section) {
        SoapSection.subjective => _subjective,
        SoapSection.objective => _objective,
        SoapSection.assessment => _assessment,
        SoapSection.plan => _plan,
      };

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

  Future<bool> _onWillPop() async {
    if (_listening) await _speech.cancel();
    _saveDebounce?.cancel();
    await _save();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: PelviColors.pink700),
        ),
      );
    }
    final note = _note;
    if (note == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Note')),
        body: const Center(child: Text('Note not found.')),
      );
    }

    final text = Theme.of(context).textTheme;
    final title = _client == null ? 'SOAP note' : clientDisplayName(_client!);
    final when = formatNoteDate(_appointment?.startsAt ?? note.noteDate);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _onWillPop();
        if (ok && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleLarge,
              ),
              Text(
                when,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelMedium?.copyWith(
                  color: PelviColors.inkMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: PelviSpace.page),
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: PelviColors.pink700,
                    ),
                  ),
                ),
              ),
            if (_client != null)
              IconButton(
                tooltip: 'Client profile',
                onPressed: _goToClientProfile,
                icon: const Icon(Icons.person_outline),
              ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: _DictationFab(
          listening: _listening,
          onPressed: _toggleMic,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
                    PelviSpace.page,
                    PelviSpace.md,
                    PelviSpace.page,
                    PelviSpace.xxl + 72,
                  ),
          children: [
            _NoteEditorHeader(
              listening: _listening,
              liveWords: _liveWords,
              templateLabel: _template.label,
              onCopyLast: _copyLastNote,
              onPickTemplate: _pickTemplate,
            ),
            const SizedBox(height: PelviSpace.lg),
            _SoapField(
              icon: Icons.hearing_outlined,
              label: 'Subjective',
              controller: _subjective,
              onChanged: (_) => _scheduleSave(),
            ),
            const SizedBox(height: PelviSpace.lg),
            _SoapField(
              icon: Icons.visibility_outlined,
              label: 'Objective',
              controller: _objective,
              onChanged: (_) => _scheduleSave(),
            ),
            const SizedBox(height: PelviSpace.lg),
            _SoapField(
              icon: Icons.psychology_outlined,
              label: 'Assessment',
              controller: _assessment,
              onChanged: (_) => _scheduleSave(),
            ),
            const SizedBox(height: PelviSpace.lg),
            _SoapField(
              icon: Icons.checklist_rtl,
              label: 'Plan',
              controller: _plan,
              onChanged: (_) => _scheduleSave(),
            ),
            const SizedBox(height: PelviSpace.md),
            Text(
              'Saves on this device automatically.',
              textAlign: TextAlign.center,
              style: text.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteEditorHeader extends StatelessWidget {
  const _NoteEditorHeader({
    required this.listening,
    required this.liveWords,
    required this.templateLabel,
    required this.onCopyLast,
    required this.onPickTemplate,
  });

  final bool listening;
  final String liveWords;
  final String templateLabel;
  final VoidCallback onCopyLast;
  final VoidCallback onPickTemplate;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (listening) ...[
          Text(
            liveWords.isEmpty ? 'Listening… tap mic to stop' : liveWords,
            style: text.bodyMedium?.copyWith(color: PelviColors.pink700),
          ),
          const SizedBox(height: PelviSpace.md),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onCopyLast,
                icon: const Icon(Icons.content_copy_outlined, size: 18),
                label: const Text('Copy last note'),
              ),
            ),
            const SizedBox(width: PelviSpace.sm),
            Expanded(
              child: Tooltip(
                message: 'Choose template',
                child: FilledButton(
                  onPressed: onPickTemplate,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          templateLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DictationFab extends StatelessWidget {
  const _DictationFab({
    required this.listening,
    required this.onPressed,
  });

  final bool listening;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: listening ? 'Stop dictation' : 'Dictate',
      child: SizedBox(
        width: 54,
        height: 54,
        child: FloatingActionButton(
          heroTag: 'soapDictationFab',
          onPressed: onPressed,
          elevation: 0,
          focusElevation: 0,
          hoverElevation: 0,
          highlightElevation: 0,
          backgroundColor:
              listening ? PelviColors.pink950 : PelviColors.pink700,
          foregroundColor: PelviColors.inkInverse,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PelviRadius.lg),
          ),
          child: Icon(
            listening ? Icons.stop_rounded : Icons.mic_none_rounded,
            size: 24,
          ),
        ),
      ),
    );
  }
}

class _SoapField extends StatelessWidget {
  const _SoapField({
    required this.icon,
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: PelviColors.purple700),
            const SizedBox(width: PelviSpace.sm),
            Text(
              label.toUpperCase(),
              style: text.labelMedium,
            ),
          ],
        ),
        const SizedBox(height: PelviSpace.sm),
        TextField(
          controller: controller,
          minLines: 3,
          maxLines: 8,
          onChanged: onChanged,
          style: text.bodyLarge?.copyWith(color: PelviColors.ink),
          decoration: const InputDecoration(
            filled: true,
            fillColor: PelviColors.surface,
          ),
        ),
      ],
    );
  }
}
