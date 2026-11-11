import 'package:flutter/material.dart';

import '../../data/auth.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/theme.dart';
import '../notes/soap_dictation.dart';
import 'template_body.dart';

extension on SoapSection {
  String get letter => switch (this) {
    SoapSection.subjective => 'S',
    SoapSection.objective => 'O',
    SoapSection.assessment => 'A',
    SoapSection.plan => 'P',
  };

  String get blurb => switch (this) {
    SoapSection.subjective => 'What the client reports',
    SoapSection.objective => 'What you observe',
    SoapSection.assessment => 'Your clinical read',
    SoapSection.plan => 'What happens next',
  };
}

/// Desktop template editor for the content pane. The app sidebar and top bar
/// stay outside this widget.
class WebTemplateBuilder extends StatefulWidget {
  const WebTemplateBuilder({
    super.key,
    this.initialName = 'Postnatal Check',
    this.initialDescription = 'Guided prompts for a postnatal review.',
    this.seedPostnatal = true,
    this.remoteId,
    this.fieldsJson,
    this.onBackToLibrary,
  });

  final String initialName;
  final String initialDescription;
  final bool seedPostnatal;

  /// Set when editing an org template. Null starts a new org record on save.
  final String? remoteId;

  /// Saved builder fields. Null uses the postnatal or blank starter.
  final String? fieldsJson;
  final VoidCallback? onBackToLibrary;

  @override
  State<WebTemplateBuilder> createState() => _WebTemplateBuilderState();
}

class _WebTemplateBuilderState extends State<WebTemplateBuilder> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;

  late List<TemplateField> _fields;
  late SoapSection _section;
  String? _selectedId;
  String? _remoteId;
  int _idSeq = 0;
  bool _preview = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final saved = widget.fieldsJson;
    _remoteId = widget.remoteId;
    if (saved != null) {
      _fields = decodeTemplateFields(saved);
      _idSeq = _maxFieldSeq(_fields);
    } else {
      _fields = widget.seedPostnatal ? _seedPostnatal() : _seedBlank();
    }
    final sel = _fields.isEmpty ? null : _fields.first;
    _selectedId = sel?.id;
    _section = sel?.section ?? SoapSection.subjective;
    _nameCtrl = TextEditingController(text: widget.initialName);
    _descCtrl = TextEditingController(text: widget.initialDescription);
  }

  int _maxFieldSeq(List<TemplateField> fields) {
    var max = 0;
    for (final field in fields) {
      final match = RegExp(r'^f(\d+)$').firstMatch(field.id);
      final n = int.tryParse(match?.group(1) ?? '') ?? 0;
      if (n > max) max = n;
    }
    return max;
  }

  List<TemplateField> _seedBlank() {
    _idSeq += 1;
    return [
      TemplateField(
        id: 'f$_idSeq',
        type: FieldType.longText,
        section: SoapSection.subjective,
        label: 'New field',
        placeholder: 'Enter value…',
      ),
    ];
  }

  List<TemplateField> _seedPostnatal() {
    TemplateField f({
      required FieldType type,
      required SoapSection section,
      required String label,
      String help = '',
      String placeholder = '',
      bool required = false,
    }) {
      _idSeq += 1;
      return TemplateField(
        id: 'f$_idSeq',
        type: type,
        section: section,
        label: label,
        helpText: help,
        placeholder: placeholder,
        required: required,
      );
    }

    return [
      f(
        type: FieldType.longText,
        section: SoapSection.subjective,
        label: 'Presenting concerns',
        help:
            'Describe the client’s concerns and priorities in their own words.',
        placeholder: 'Enter the client’s reported concerns…',
        required: true,
      ),
      f(
        type: FieldType.shortText,
        section: SoapSection.subjective,
        label: 'Client goals',
        placeholder: 'Enter goals for this visit…',
      ),
      f(
        type: FieldType.longText,
        section: SoapSection.objective,
        label: 'Observations',
        placeholder: 'Enter observations…',
      ),
      f(
        type: FieldType.shortText,
        section: SoapSection.objective,
        label: 'Measurements',
        placeholder: 'Enter measurements…',
      ),
      f(
        type: FieldType.longText,
        section: SoapSection.assessment,
        label: 'Clinical interpretation',
        placeholder: 'Enter assessment…',
      ),
      f(
        type: FieldType.longText,
        section: SoapSection.plan,
        label: 'Agreed next steps',
        placeholder: 'Enter next steps…',
      ),
      f(
        type: FieldType.shortText,
        section: SoapSection.plan,
        label: 'Follow-up interval',
        placeholder: 'e.g. 2 weeks…',
      ),
      f(
        type: FieldType.longText,
        section: SoapSection.plan,
        label: 'Review notes',
        placeholder: 'Enter review notes…',
      ),
    ];
  }

  TemplateField? get _selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final f in _fields) {
      if (f.id == id) return f;
    }
    return null;
  }

  List<TemplateField> _in(SoapSection section) =>
      _fields.where((f) => f.section == section).toList();

  void _selectSection(SoapSection section) {
    if (section == _section) return;
    final inSection = _in(section);
    setState(() {
      _section = section;
      if (inSection.every((f) => f.id != _selectedId)) {
        _selectedId = inSection.isEmpty ? null : inSection.first.id;
      }
    });
  }

  void _selectField(TemplateField field) {
    if (field.id == _selectedId && !_preview) return;
    setState(() {
      _section = field.section;
      _preview = false;
      _selectedId = field.id;
    });
  }

  int _insertIndex(SoapSection section) {
    var last = -1;
    for (var i = 0; i < _fields.length; i++) {
      if (_fields[i].section == section) last = i;
    }
    if (last >= 0) return last + 1;
    final order = SoapSection.values;
    for (var i = order.indexOf(section) + 1; i < order.length; i++) {
      final idx = _fields.indexWhere((f) => f.section == order[i]);
      if (idx >= 0) return idx;
    }
    return _fields.length;
  }

  void _addQuestion() {
    _idSeq += 1;
    final field = TemplateField(
      id: 'f$_idSeq',
      type: FieldType.longText,
      section: _section,
      label: 'New question',
      placeholder: 'Enter value…',
    );
    setState(() {
      _fields = [..._fields]..insert(_insertIndex(_section), field);
      _preview = false;
      _selectedId = field.id;
    });
  }

  void _deleteSelected() {
    final sel = _selected;
    if (sel == null) return;
    final idx = _fields.indexWhere((f) => f.id == sel.id);
    if (idx < 0) return;
    final section = sel.section;
    final local = _in(section).indexWhere((f) => f.id == sel.id);
    setState(() {
      _fields = [..._fields]..removeAt(idx);
      final rest = _in(section);
      _selectedId = rest.isEmpty
          ? null
          : rest[local.clamp(0, rest.length - 1)].id;
    });
  }

  void _togglePreview() {
    setState(() => _preview = !_preview);
  }

  Future<void> _save() async {
    if (_saving) return;
    final db = AppDatabaseProvider.maybeOf(context);
    if (db == null) return;
    setState(() => _saving = true);
    final authUser = NotesAuth.currentUser;
    final bound = await db.getSetting(AppDatabase.syncBoundUidKey);
    if (!mounted) return;
    final authUid = authUser?.uid ?? '';
    final uid = authUid.isNotEmpty ? authUid : (bound ?? '');
    final liveName = authUser?.displayName?.trim() ?? '';
    try {
      final saved = await db.saveOrgTemplate(
        remoteId: _remoteId,
        name: _nameCtrl.text,
        description: _descCtrl.text.trim(),
        fieldsJson: encodeTemplateFields(_fields),
        createdBy: uid,
        createdByName: liveName,
      );
      if (!mounted) return;
      setState(() => _remoteId = saved.remoteId);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved for the clinic.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save template: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Scaffold(
      backgroundColor: c.canvas,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 640;
          return Padding(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _outline(context),
                      const SizedBox(width: 20),
                      Expanded(child: _editor(context, scroll: true)),
                    ],
                  )
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        _outline(context, pinFooter: false),
                        const SizedBox(height: 20),
                        _editor(context, scroll: false),
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }

  BoxDecoration _card(PelviPalette c) => BoxDecoration(
    color: c.surface,
    borderRadius: BorderRadius.circular(PelviRadius.button),
    border: Border.all(color: c.border),
  );

  Widget _outline(BuildContext context, {bool pinFooter = true}) {
    final c = PelviColors.of(context);
    return SizedBox(
      width: 280,
      child: DecoratedBox(
        decoration: _card(c),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _nameRow(context),
              const SizedBox(height: 12),
              Text(
                'Sections',
                style: TextStyle(
                  fontSize: 11,
                  height: 16 / 11,
                  color: c.inkMuted,
                ),
              ),
              const SizedBox(height: 4),
              for (final section in SoapSection.values)
                _sectionTile(context, section),
              if (pinFooter) const Spacer() else const SizedBox(height: 24),
              Text(
                'Questions are added to the selected section.',
                style: TextStyle(
                  fontSize: 11,
                  height: 15 / 11,
                  color: c.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nameRow(BuildContext context) {
    final c = PelviColors.of(context);
    return Row(
      children: [
        if (widget.onBackToLibrary != null) ...[
          IconButton(
            tooltip: 'Templates',
            onPressed: widget.onBackToLibrary,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            icon: Icon(Icons.chevron_left, size: 18, color: c.ink),
          ),
        ],
        Expanded(
          child: TextField(
            controller: _nameCtrl,
            maxLines: 1,
            style: TextStyle(
              fontSize: 15,
              height: 20 / 15,
              fontWeight: FontWeight.w600,
              color: c.ink,
            ),
            decoration: InputDecoration(
              isCollapsed: true,
              filled: false,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              hintText: 'Untitled template',
              hintStyle: TextStyle(
                fontSize: 15,
                height: 20 / 15,
                fontWeight: FontWeight.w600,
                color: c.inkMuted,
              ),
            ),
          ),
        ),
        Text(
          'Draft',
          style: TextStyle(fontSize: 12, height: 16 / 12, color: c.inkMuted),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          style: TextButton.styleFrom(
            foregroundColor: c.pink700,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'Save',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _sectionTile(BuildContext context, SoapSection section) {
    final c = PelviColors.of(context);
    final selected = section == _section;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? c.pink50 : Colors.transparent,
        borderRadius: BorderRadius.circular(PelviRadius.sm),
        child: InkWell(
          onTap: () => _selectSection(section),
          borderRadius: BorderRadius.circular(PelviRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  child: Text(
                    section.letter,
                    style: TextStyle(
                      fontSize: 12,
                      height: 16 / 12,
                      fontWeight: FontWeight.w600,
                      color: c.pink700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    section.label,
                    style: TextStyle(
                      fontSize: 13,
                      height: 18 / 13,
                      color: c.ink,
                    ),
                  ),
                ),
                Text(
                  '${_in(section).length}',
                  style: TextStyle(
                    fontSize: 12,
                    height: 16 / 12,
                    color: c.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _editor(BuildContext context, {required bool scroll}) {
    final c = PelviColors.of(context);
    final header = _sectionHeader(context);
    final body = _sectionBody(context);
    return DecoratedBox(
      decoration: _card(c),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        child: scroll
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  const SizedBox(height: 14),
                  Expanded(child: SingleChildScrollView(child: body)),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [header, const SizedBox(height: 14), body],
              ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context) {
    final c = PelviColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _section.label,
                style: TextStyle(
                  fontSize: 18,
                  height: 24 / 18,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _section.blurb,
                style: TextStyle(
                  fontSize: 12,
                  height: 16 / 12,
                  color: c.inkMuted,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: _togglePreview,
          child: Text(
            'Preview',
            style: TextStyle(fontSize: 13, height: 18 / 13, color: c.inkMuted),
          ),
        ),
        const SizedBox(width: 8),
        _MiniSwitch(value: _preview, onChanged: (_) => _togglePreview()),
      ],
    );
  }

  Widget _sectionBody(BuildContext context) {
    final c = PelviColors.of(context);
    final prompts = _in(_section);
    if (_preview) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (prompts.isEmpty)
            Text(
              'No questions yet',
              style: TextStyle(fontSize: 13, color: c.inkMuted),
            )
          else
            for (final field in prompts) ...[
              _PreviewField(field: field),
              const SizedBox(height: 16),
            ],
          const SizedBox(height: 8),
          Text(
            'Preview responses are not saved as clinical notes.',
            style: TextStyle(fontSize: 11, color: c.inkMuted),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (prompts.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              'No questions yet',
              style: TextStyle(fontSize: 13, color: c.inkMuted),
            ),
          )
        else
          for (final field in prompts) ...[
            _QuestionRow(
              key: ValueKey(field.id),
              field: field,
              onSelect: () => _selectField(field),
              onType: (type) {
                setState(() {
                  field.type = type;
                  _section = field.section;
                  _selectedId = field.id;
                });
              },
            ),
            if (field.id == _selectedId) ...[
              const SizedBox(height: 8),
              _requiredBar(context, field),
            ],
            const SizedBox(height: 14),
          ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addQuestion,
            icon: Icon(Icons.add, size: 16, color: c.pink700),
            label: const Text('Add question'),
            style: TextButton.styleFrom(
              foregroundColor: c.pink700,
              padding: const EdgeInsets.only(top: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 13,
                height: 18 / 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // shortcut: help text and placeholder stay on the field and still save, surface editors if a clinic needs to change them.
  Widget _requiredBar(BuildContext context, TemplateField field) {
    final c = PelviColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        borderRadius: BorderRadius.circular(PelviRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Required · needed before the note is completed',
                style: TextStyle(
                  fontSize: 12,
                  height: 16 / 12,
                  color: c.inkMuted,
                ),
              ),
            ),
            TextButton(
              onPressed: _deleteSelected,
              style: TextButton.styleFrom(
                foregroundColor: c.danger,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Delete question',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
            _MiniSwitch(
              value: field.required,
              onChanged: (value) {
                setState(() => field.required = value);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionRow extends StatefulWidget {
  const _QuestionRow({
    super.key,
    required this.field,
    required this.onSelect,
    required this.onType,
  });

  final TemplateField field;
  final VoidCallback onSelect;
  final ValueChanged<FieldType> onType;

  @override
  State<_QuestionRow> createState() => _QuestionRowState();
}

class _QuestionRowState extends State<_QuestionRow> {
  late final TextEditingController _labelCtrl;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.field.label);
  }

  @override
  void didUpdateWidget(_QuestionRow old) {
    super.didUpdateWidget(old);
    if (old.field.id != widget.field.id &&
        _labelCtrl.text != widget.field.label) {
      _labelCtrl.text = widget.field.label;
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final field = widget.field;
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 36,
            child: TextField(
              controller: _labelCtrl,
              onTap: widget.onSelect,
              onChanged: (value) => field.label = value,
              style: TextStyle(fontSize: 13, height: 1.2, color: c.ink),
              decoration: _questionDecoration(c),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 136,
          height: 36,
          child: PopupMenuButton<FieldType>(
            tooltip: 'Field type',
            padding: EdgeInsets.zero,
            onSelected: widget.onType,
            itemBuilder: (context) => [
              for (final type in FieldType.values)
                PopupMenuItem(value: type, child: Text(type.label)),
            ],
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(PelviRadius.sm),
                border: Border.all(color: c.border),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 12, right: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        field.type.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: c.ink),
                      ),
                    ),
                    Icon(Icons.expand_more, size: 16, color: c.inkMuted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

InputDecoration _questionDecoration(PelviPalette c) {
  OutlineInputBorder edge(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(PelviRadius.sm),
    borderSide: BorderSide(color: color),
  );
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: c.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    hintText: 'Question',
    border: edge(c.border),
    enabledBorder: edge(c.border),
    focusedBorder: edge(c.pink700),
  );
}

class _MiniSwitch extends StatelessWidget {
  const _MiniSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 20,
      child: FittedBox(
        child: Switch(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

class _PreviewField extends StatelessWidget {
  const _PreviewField({required this.field});

  final TemplateField field;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${field.label}${field.required ? ' *' : ''}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 7),
        Container(
          width: double.infinity,
          constraints: BoxConstraints(
            minHeight: field.type.isMultiline ? 72 : 40,
          ),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(PelviRadius.sm),
          ),
          child: Text(
            field.placeholder.isEmpty ? ' ' : field.placeholder,
            style: TextStyle(fontSize: 13, height: 1.5, color: c.inkMuted),
          ),
        ),
        if (field.helpText.isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(
            field.helpText,
            style: TextStyle(fontSize: 11, height: 1.5, color: c.inkMuted),
          ),
        ],
      ],
    );
  }
}
