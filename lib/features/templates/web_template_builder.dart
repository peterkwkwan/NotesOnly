import 'package:flutter/material.dart';

import '../../theme/theme.dart';

enum SoapSection { subjective, objective, assessment, plan }

enum FieldType { longText, shortText, singleChoice, multipleChoice, numeric }

extension on SoapSection {
  String get letter => switch (this) {
        SoapSection.subjective => 'S',
        SoapSection.objective => 'O',
        SoapSection.assessment => 'A',
        SoapSection.plan => 'P',
      };

  String get label => switch (this) {
        SoapSection.subjective => 'Subjective',
        SoapSection.objective => 'Objective',
        SoapSection.assessment => 'Assessment',
        SoapSection.plan => 'Plan',
      };
}

extension on FieldType {
  String get label => switch (this) {
        FieldType.longText => 'Long text',
        FieldType.shortText => 'Short text',
        FieldType.singleChoice => 'Single choice',
        FieldType.multipleChoice => 'Multiple choice',
        FieldType.numeric => 'Numeric',
      };

  bool get isMultiline => this == FieldType.longText;
}

class _DraftField {
  _DraftField({
    required this.id,
    required this.type,
    required this.section,
    required this.label,
    this.helpText = '',
    this.placeholder = '',
    this.required = false,
  });

  final String id;
  FieldType type;
  SoapSection section;
  String label;
  String helpText;
  String placeholder;
  bool required;
}

/// Quiet web template editor, shown in the desktop content pane.
///
/// shortcut: no Drift/Firestore template schema yet — local in-memory draft only;
/// upgrade when custom templates are modeled.
class WebTemplateBuilder extends StatefulWidget {
  const WebTemplateBuilder({
    super.key,
    this.initialName = 'Postnatal Check',
    this.initialDescription = 'Guided prompts for a postnatal review.',
    this.seedPostnatal = true,
    this.onBackToLibrary,
  });

  final String initialName;
  final String initialDescription;
  final bool seedPostnatal;
  final VoidCallback? onBackToLibrary;

  @override
  State<WebTemplateBuilder> createState() => _WebTemplateBuilderState();
}

class _WebTemplateBuilderState extends State<WebTemplateBuilder> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _labelCtrl;
  late final TextEditingController _helpCtrl;
  late final TextEditingController _placeholderCtrl;

  late List<_DraftField> _fields;
  late SoapSection _section;
  String? _selectedId;
  int _idSeq = 0;
  bool _dirty = true;
  bool _preview = false;
  bool _showMore = false;

  @override
  void initState() {
    super.initState();
    _fields = widget.seedPostnatal ? _seedPostnatal() : _seedBlank();
    _selectedId = _fields.first.id;
    _section = _fields.first.section;
    final sel = _fields.first;
    _nameCtrl = TextEditingController(text: widget.initialName);
    _descCtrl = TextEditingController(text: widget.initialDescription);
    _labelCtrl = TextEditingController(text: sel.label);
    _helpCtrl = TextEditingController(text: sel.helpText);
    _placeholderCtrl = TextEditingController(text: sel.placeholder);
    _nameCtrl.addListener(_markDirty);
    _descCtrl.addListener(_markDirty);
  }

  List<_DraftField> _seedBlank() {
    _idSeq += 1;
    return [
      _DraftField(
        id: 'f$_idSeq',
        type: FieldType.longText,
        section: SoapSection.subjective,
        label: 'New field',
        placeholder: 'Enter value…',
      ),
    ];
  }

  List<_DraftField> _seedPostnatal() {
    _DraftField f({
      required FieldType type,
      required SoapSection section,
      required String label,
      String help = '',
      String placeholder = '',
      bool required = false,
    }) {
      _idSeq += 1;
      return _DraftField(
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

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  _DraftField? get _selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final f in _fields) {
      if (f.id == id) return f;
    }
    return null;
  }

  List<_DraftField> _in(SoapSection section) =>
      _fields.where((f) => f.section == section).toList();

  void _syncSelectedControllers() {
    final sel = _selected;
    if (sel == null) return;
    sel.label = _labelCtrl.text;
    sel.helpText = _helpCtrl.text;
    sel.placeholder = _placeholderCtrl.text;
  }

  void _bind(_DraftField? field) {
    _selectedId = field?.id;
    _labelCtrl.text = field?.label ?? '';
    _helpCtrl.text = field?.helpText ?? '';
    _placeholderCtrl.text = field?.placeholder ?? '';
    _showMore = false;
  }

  void _onDraftText() {
    _syncSelectedControllers();
    _markDirty();
  }

  void _selectSection(SoapSection section) {
    if (section == _section && !_preview) return;
    _syncSelectedControllers();
    final inSection = _in(section);
    setState(() {
      _section = section;
      _preview = false;
      if (inSection.every((f) => f.id != _selectedId)) {
        _bind(inSection.isEmpty ? null : inSection.first);
      }
    });
  }

  void _selectField(_DraftField field) {
    if (field.id == _selectedId && !_preview) return;
    _syncSelectedControllers();
    setState(() {
      _section = field.section;
      _preview = false;
      _bind(field);
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
    _syncSelectedControllers();
    _idSeq += 1;
    final field = _DraftField(
      id: 'f$_idSeq',
      type: FieldType.longText,
      section: _section,
      label: 'New question',
      placeholder: 'Enter value…',
    );
    setState(() {
      _fields = [..._fields]..insert(_insertIndex(_section), field);
      _preview = false;
      _bind(field);
      _dirty = true;
    });
  }

  void _deleteSelected() {
    final sel = _selected;
    if (sel == null) return;
    final idx = _fields.indexWhere((f) => f.id == sel.id);
    final section = sel.section;
    final local = _in(section).indexWhere((f) => f.id == sel.id);
    setState(() {
      _fields = [..._fields]..removeAt(idx);
      final rest = _in(section);
      _bind(rest.isEmpty ? null : rest[local.clamp(0, rest.length - 1)]);
      _dirty = true;
    });
  }

  void _save() {
    _syncSelectedControllers();
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Saved in this session only — custom templates are not stored yet.',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_markDirty);
    _descCtrl.removeListener(_markDirty);
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _labelCtrl.dispose();
    _helpCtrl.dispose();
    _placeholderCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Scaffold(
      backgroundColor: c.canvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bar(context),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 760;
                final outline = _outline(context);
                if (!wide) {
                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        outline,
                        Divider(height: 1, color: c.border),
                        _main(context),
                      ],
                    ),
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 248,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(right: BorderSide(color: c.border)),
                        ),
                        child: SingleChildScrollView(child: outline),
                      ),
                    ),
                    Expanded(child: SingleChildScrollView(child: _main(context))),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(BuildContext context) {
    final c = PelviColors.of(context);
    final nameStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: c.ink,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Image.asset(
                'assets/brand/notesonly-monogram.png',
                width: 26,
                height: 28,
                filterQuality: FilterQuality.high,
              ),
              const SizedBox(width: 10),
              Text(
                'NotesOnly',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                  color: c.ink,
                ),
              ),
              const SizedBox(width: 20),
              IconButton(
                tooltip: 'Templates',
                onPressed: widget.onBackToLibrary,
                icon: Icon(Icons.arrow_back, size: 18, color: c.ink),
              ),
              Expanded(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _nameCtrl,
                  builder: (context, value, _) {
                    final name = value.text.trim();
                    return Text(
                      name.isEmpty ? 'Untitled template' : name,
                      style: nameStyle,
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  backgroundColor: c.pink700,
                  foregroundColor: c.inkInverse,
                  minimumSize: const Size(72, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(PelviRadius.sm),
                  ),
                ),
                child: const Text(
                  'Save',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _outline(BuildContext context) {
    final c = PelviColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 12, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 12),
            child: Text(
              'OUTLINE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: c.inkMuted,
              ),
            ),
          ),
          for (final section in SoapSection.values)
            _sectionTile(context, section),
        ],
      ),
    );
  }

  Widget _sectionTile(BuildContext context, SoapSection section) {
    final c = PelviColors.of(context);
    final selected = section == _section;
    final count = _in(section).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: selected ? c.pink50 : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => _selectSection(section),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? c.pink700 : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? c.pink700 : c.border,
                      ),
                    ),
                    child: Text(
                      section.letter,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: selected ? c.inkInverse : c.inkMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      section.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                        color: c.ink,
                      ),
                    ),
                  ),
                  if (selected)
                    Text(
                      '$count',
                      style: TextStyle(fontSize: 13, color: c.inkMuted),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (selected)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 32),
              child: TextButton(
                onPressed: _addQuestion,
                style: TextButton.styleFrom(
                  foregroundColor: c.pink700,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  '+ Add question',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _main(BuildContext context) {
    final c = PelviColors.of(context);
    final prompts = _in(_section);
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 28, 36, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Templates / Edit',
                style: TextStyle(fontSize: 13, color: c.inkMuted),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  _syncSelectedControllers();
                  setState(() => _preview = !_preview);
                },
                style: TextButton.styleFrom(
                  foregroundColor: c.pink700,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Preview',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: _preview ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            maxLines: 1,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.6,
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
                fontSize: 30,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.6,
                color: c.inkMuted,
              ),
            ),
          ),
          const SizedBox(height: 22),
          if (_preview)
            _previewBody(context)
          else ...[
            Text(
              _section.label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 14),
            if (prompts.isEmpty)
              Text(
                'No questions yet',
                style: TextStyle(fontSize: 13, color: c.inkMuted),
              )
            else
              for (final field in prompts) ...[
                _prompt(context, field),
                const SizedBox(height: 10),
              ],
          ],
        ],
      ),
    );
  }

  Widget _promptTitle(PelviPalette c, String raw) {
    final title = raw.trim();
    return Text(
      title.isEmpty ? 'Untitled question' : title,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: c.ink,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _prompt(BuildContext context, _DraftField field) {
    final c = PelviColors.of(context);
    final selected = field.id == _selectedId;
    final title = field.label.trim();
    return Material(
      color: selected ? c.pink50 : c.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? c.pink50 : c.border),
      ),
      child: Stack(
        children: [
          if (selected)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 3,
              child: ColoredBox(color: c.pink700),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => _selectField(field),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: selected
                            ? ValueListenableBuilder<TextEditingValue>(
                                valueListenable: _labelCtrl,
                                builder: (context, value, _) => _promptTitle(
                                  c,
                                  value.text,
                                ),
                              )
                            : _promptTitle(c, title),
                      ),
                      const SizedBox(width: 12),
                      _TypeChip(label: field.type.label),
                    ],
                  ),
                ),
              ),
              if (selected) _promptEditor(context, field),
            ],
          ),
        ],
      ),
    );
  }

  Widget _promptEditor(BuildContext context, _DraftField field) {
    final c = PelviColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LabeledField(
            label: 'Label',
            child: _TextBox(controller: _labelCtrl, onChanged: (_) => _onDraftText()),
          ),
          const SizedBox(height: 14),
          Text(
            'Type',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: PopupMenuButton<FieldType>(
              tooltip: 'Field type',
              padding: EdgeInsets.zero,
              onSelected: (type) {
                _syncSelectedControllers();
                setState(() {
                  field.type = type;
                  _dirty = true;
                });
              },
              itemBuilder: (context) => [
                for (final type in FieldType.values)
                  PopupMenuItem(value: type, child: Text(type.label)),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    field.type.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: c.purple700,
                    ),
                  ),
                  Icon(Icons.expand_more, size: 18, color: c.purple700),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _showMore = !_showMore),
              style: TextButton.styleFrom(
                foregroundColor: c.ink,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _showMore ? 'Less' : 'More',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          if (_showMore) ...[
            const SizedBox(height: 12),
            _LabeledField(
              label: 'Help text',
              child: _TextBox(
                controller: _helpCtrl,
                minLines: 2,
                onChanged: (_) => _onDraftText(),
              ),
            ),
            const SizedBox(height: 14),
            _LabeledField(
              label: 'Placeholder',
              child: _TextBox(
                controller: _placeholderCtrl,
                onChanged: (_) => _onDraftText(),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Required',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: c.ink,
                        ),
                      ),
                      Text(
                        'Needed before a note can be completed.',
                        style: TextStyle(fontSize: 11, color: c.inkMuted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: field.required,
                  onChanged: (value) {
                    _syncSelectedControllers();
                    setState(() {
                      field.required = value;
                      _dirty = true;
                    });
                  },
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _deleteSelected,
                style: TextButton.styleFrom(
                  foregroundColor: c.danger,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Delete question',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _previewBody(BuildContext context) {
    final c = PelviColors.of(context);
    final sections = [
      for (final section in SoapSection.values)
        if (_in(section).isNotEmpty) section,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _descCtrl,
          maxLines: 1,
          style: TextStyle(fontSize: 13, color: c.inkMuted),
          decoration: InputDecoration(
            isCollapsed: true,
            filled: false,
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            hintText: 'Description',
            hintStyle: TextStyle(fontSize: 13, color: c.inkMuted),
          ),
        ),
        const SizedBox(height: 22),
        if (sections.isEmpty)
          Text(
            'No questions yet',
            style: TextStyle(fontSize: 13, color: c.inkMuted),
          )
        else
          for (final section in sections) ...[
            Text(
              section.label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 12),
            for (final field in _in(section)) ...[
              _PreviewField(field: field),
              const SizedBox(height: 16),
            ],
          ],
        const SizedBox(height: 8),
        Text(
          'Preview responses are not saved as clinical notes.',
          style: TextStyle(fontSize: 11, color: c.inkMuted),
        ),
      ],
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.purple50,
        borderRadius: BorderRadius.circular(PelviRadius.full),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          fontWeight: FontWeight.w500,
          color: c.purple700,
        ),
      ),
    );
  }
}

class _PreviewField extends StatelessWidget {
  const _PreviewField({required this.field});

  final _DraftField field;

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

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

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
          ),
        ),
        const SizedBox(height: 7),
        child,
      ],
    );
  }
}

class _TextBox extends StatelessWidget {
  const _TextBox({
    required this.controller,
    this.minLines = 1,
    this.onChanged,
  });

  final TextEditingController controller;
  final int minLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: minLines > 1 ? null : 1,
      onChanged: onChanged,
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
    );
  }
}
