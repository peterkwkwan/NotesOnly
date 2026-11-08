import 'package:flutter/material.dart';

import '../../data/database_provider.dart';
import '../../theme/theme.dart';

/// Figma accent for focused field chrome (`#bc718d`).
const _focusPink = Color(0xFFBC718D);

/// Figma selected nav / outline ink (`#a54d70`).
const _selectedPink = Color(0xFFA54D70);

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

  String get heading => '$letter / $label';
}

extension on FieldType {
  String get label => switch (this) {
        FieldType.longText => 'Long text',
        FieldType.shortText => 'Short text',
        FieldType.singleChoice => 'Single choice',
        FieldType.multipleChoice => 'Multiple choice',
        FieldType.numeric => 'Numeric',
      };

  IconData get icon => switch (this) {
        FieldType.longText => Icons.format_align_left,
        FieldType.shortText => Icons.text_fields,
        FieldType.singleChoice => Icons.radio_button_checked_outlined,
        FieldType.multipleChoice => Icons.checklist_outlined,
        FieldType.numeric => Icons.tag,
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

/// Figma `NotesOnly · Template builder` (47:22340) — desktop shell supplies chrome.
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
  String? _selectedId;
  int _idSeq = 0;
  bool _dirty = true;
  int _version = 2;

  @override
  void initState() {
    super.initState();
    _fields = widget.seedPostnatal ? _seedPostnatal() : _seedBlank();
    _selectedId = _fields.first.id;
    final sel = _fields.first;
    _nameCtrl = TextEditingController(text: widget.initialName);
    _descCtrl = TextEditingController(text: widget.initialDescription);
    _labelCtrl = TextEditingController(text: sel.label);
    _helpCtrl = TextEditingController(text: sel.helpText);
    _placeholderCtrl = TextEditingController(text: sel.placeholder);
    _nameCtrl.addListener(_markDirty);
    _descCtrl.addListener(_markDirty);
    if (!widget.seedPostnatal) _version = 1;
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

  void _selectField(_DraftField field) {
    _syncSelectedControllers();
    setState(() {
      _selectedId = field.id;
      _labelCtrl.text = field.label;
      _helpCtrl.text = field.helpText;
      _placeholderCtrl.text = field.placeholder;
    });
  }

  void _syncSelectedControllers() {
    final sel = _selected;
    if (sel == null) return;
    sel.label = _labelCtrl.text;
    sel.helpText = _helpCtrl.text;
    sel.placeholder = _placeholderCtrl.text;
  }

  void _addField(FieldType type) {
    _syncSelectedControllers();
    final section = _selected?.section ?? SoapSection.subjective;
    _idSeq += 1;
    final field = _DraftField(
      id: 'f$_idSeq',
      type: type,
      section: section,
      label: 'New ${type.label.toLowerCase()}',
      placeholder: 'Enter value…',
    );
    setState(() {
      _fields = [..._fields, field];
      _selectedId = field.id;
      _labelCtrl.text = field.label;
      _helpCtrl.text = field.helpText;
      _placeholderCtrl.text = field.placeholder;
      _dirty = true;
    });
  }

  void _duplicateSelected() {
    final sel = _selected;
    if (sel == null) return;
    _syncSelectedControllers();
    _idSeq += 1;
    final copy = _DraftField(
      id: 'f$_idSeq',
      type: sel.type,
      section: sel.section,
      label: '${sel.label} copy',
      helpText: sel.helpText,
      placeholder: sel.placeholder,
      required: sel.required,
    );
    final idx = _fields.indexWhere((f) => f.id == sel.id);
    setState(() {
      _fields = [..._fields]..insert(idx + 1, copy);
      _selectedId = copy.id;
      _labelCtrl.text = copy.label;
      _helpCtrl.text = copy.helpText;
      _placeholderCtrl.text = copy.placeholder;
      _dirty = true;
    });
  }

  void _deleteSelected() {
    final sel = _selected;
    if (sel == null || _fields.length <= 1) return;
    final idx = _fields.indexWhere((f) => f.id == sel.id);
    setState(() {
      _fields = [..._fields]..removeAt(idx);
      final next = _fields[idx.clamp(0, _fields.length - 1)];
      _selectedId = next.id;
      _labelCtrl.text = next.label;
      _helpCtrl.text = next.helpText;
      _placeholderCtrl.text = next.placeholder;
      _dirty = true;
    });
  }

  void _reorderInSection(SoapSection section, int oldIndex, int newIndex) {
    _syncSelectedControllers();
    final inSection = _fields.where((f) => f.section == section).toList();
    // onReorderItem already adjusts newIndex when moving downward.
    final moved = inSection.removeAt(oldIndex);
    inSection.insert(newIndex.clamp(0, inSection.length), moved);
    final rebuilt = <_DraftField>[];
    for (final s in SoapSection.values) {
      if (s == section) {
        rebuilt.addAll(inSection);
      } else {
        rebuilt.addAll(_fields.where((f) => f.section == s));
      }
    }
    setState(() {
      _fields = rebuilt;
      _dirty = true;
    });
  }

  void _newTemplate() {
    _syncSelectedControllers();
    _idSeq += 1;
    final field = _DraftField(
      id: 'f$_idSeq',
      type: FieldType.longText,
      section: SoapSection.subjective,
      label: 'New field',
      placeholder: 'Enter value…',
    );
    setState(() {
      _nameCtrl.text = 'Untitled template';
      _descCtrl.text = '';
      _fields = [field];
      _selectedId = field.id;
      _labelCtrl.text = field.label;
      _helpCtrl.text = '';
      _placeholderCtrl.text = field.placeholder;
      _version = 1;
      _dirty = true;
    });
  }

  void _gapSnack(String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$action kept in this session only — custom templates are not saved yet.',
        ),
      ),
    );
  }

  @override
  void dispose() {
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
    final db = AppDatabaseProvider.of(context);
    final sel = _selected;

    return ColoredBox(
      color: c.canvas,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 980;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HeaderRow(
                  subtitle:
                      '${_nameCtrl.text.trim().isEmpty ? 'Untitled template' : _nameCtrl.text} · Editing version $_version draft',
                  onBack: widget.onBackToLibrary,
                  onNew: _newTemplate,
                  onSaveDraft: () {
                    _syncSelectedControllers();
                    setState(() => _dirty = false);
                    _gapSnack('Draft');
                  },
                  onPublish: () {
                    _syncSelectedControllers();
                    setState(() {
                      _dirty = false;
                      _version += 1;
                    });
                    _gapSnack('Publish');
                  },
                ),
                const SizedBox(height: 26),
                _StateBanner(dirty: _dirty, name: _nameCtrl.text),
                const SizedBox(height: 26),
                if (narrow)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PaletteOutline(
                        fields: _fields,
                        selectedId: _selectedId,
                        onSelect: _selectField,
                        onAdd: _addField,
                        onReorder: _reorderInSection,
                      ),
                      const SizedBox(height: 18),
                      _EditingColumn(
                        nameCtrl: _nameCtrl,
                        descCtrl: _descCtrl,
                        labelCtrl: _labelCtrl,
                        helpCtrl: _helpCtrl,
                        placeholderCtrl: _placeholderCtrl,
                        selected: sel,
                        version: _version,
                        practitionerStream: db.watchPractitionerName(),
                        onFieldChanged: () {
                          _syncSelectedControllers();
                          setState(() => _dirty = true);
                        },
                        onTypeChanged: (t) {
                          if (sel == null) return;
                          setState(() {
                            sel.type = t;
                            _dirty = true;
                          });
                        },
                        onSectionChanged: (s) {
                          if (sel == null) return;
                          setState(() {
                            sel.section = s;
                            _dirty = true;
                          });
                        },
                        onRequiredChanged: (v) {
                          if (sel == null) return;
                          setState(() {
                            sel.required = v;
                            _dirty = true;
                          });
                        },
                        onDuplicate: _duplicateSelected,
                        onDelete: _deleteSelected,
                      ),
                      const SizedBox(height: 18),
                      _LivePreview(
                        name: _nameCtrl.text,
                        description: _descCtrl.text,
                        fields: _fields,
                      ),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 220,
                        child: _PaletteOutline(
                          fields: _fields,
                          selectedId: _selectedId,
                          onSelect: _selectField,
                          onAdd: _addField,
                          onReorder: _reorderInSection,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: _EditingColumn(
                          nameCtrl: _nameCtrl,
                          descCtrl: _descCtrl,
                          labelCtrl: _labelCtrl,
                          helpCtrl: _helpCtrl,
                          placeholderCtrl: _placeholderCtrl,
                          selected: sel,
                          version: _version,
                          practitionerStream: db.watchPractitionerName(),
                          onFieldChanged: () {
                            _syncSelectedControllers();
                            setState(() => _dirty = true);
                          },
                          onTypeChanged: (t) {
                            if (sel == null) return;
                            setState(() {
                              sel.type = t;
                              _dirty = true;
                            });
                          },
                          onSectionChanged: (s) {
                            if (sel == null) return;
                            setState(() {
                              sel.section = s;
                              _dirty = true;
                            });
                          },
                          onRequiredChanged: (v) {
                            if (sel == null) return;
                            setState(() {
                              sel.required = v;
                              _dirty = true;
                            });
                          },
                          onDuplicate: _duplicateSelected,
                          onDelete: _deleteSelected,
                        ),
                      ),
                      const SizedBox(width: 18),
                      SizedBox(
                        width: 334,
                        child: _LivePreview(
                          name: _nameCtrl.text,
                          description: _descCtrl.text,
                          fields: _fields,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.subtitle,
    required this.onNew,
    required this.onSaveDraft,
    required this.onPublish,
    this.onBack,
  });

  final String subtitle;
  final VoidCallback onNew;
  final VoidCallback onSaveDraft;
  final VoidCallback onPublish;
  final VoidCallback? onBack;

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
              if (onBack != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: InkWell(
                    onTap: onBack,
                    child: Text(
                      '← Templates',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: c.inkMuted,
                      ),
                    ),
                  ),
                ),
              Text(
                'Template builder',
                style: TextStyle(
                  fontSize: 29,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
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
        const SizedBox(width: 20),
        OutlinedButton.icon(
          onPressed: onNew,
          icon: Icon(Icons.add, size: 16, color: c.ink),
          label: Text(
            'New template',
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
        const SizedBox(width: 10),
        OutlinedButton(
          onPressed: onSaveDraft,
          style: OutlinedButton.styleFrom(
            backgroundColor: c.surface,
            side: BorderSide(color: c.border),
            minimumSize: const Size(0, 38),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PelviRadius.sm),
            ),
          ),
          child: Text(
            'Save draft',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.ink,
            ),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton(
          onPressed: onPublish,
          style: FilledButton.styleFrom(
            backgroundColor: c.pink700,
            foregroundColor: c.inkInverse,
            minimumSize: const Size(0, 38),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PelviRadius.sm),
            ),
          ),
          child: const Text(
            'Publish',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _StateBanner extends StatelessWidget {
  const _StateBanner({required this.dirty, required this.name});

  final bool dirty;
  final String name;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final title = name.trim().isEmpty ? 'Untitled template' : name.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: c.purple50,
        borderRadius: BorderRadius.circular(PelviRadius.sm),
      ),
      child: Row(
        children: [
          Icon(Icons.account_tree_outlined, size: 16, color: c.purple700),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Editing a draft of $title. Published version 1 stays available until you publish version 2.',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: c.purple700,
              ),
            ),
          ),
          if (dirty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: c.purple50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Unpublished changes',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                  color: c.purple700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PaletteOutline extends StatelessWidget {
  const _PaletteOutline({
    required this.fields,
    required this.selectedId,
    required this.onSelect,
    required this.onAdd,
    required this.onReorder,
  });

  final List<_DraftField> fields;
  final String? selectedId;
  final ValueChanged<_DraftField> onSelect;
  final ValueChanged<FieldType> onAdd;
  final void Function(SoapSection, int, int) onReorder;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add a field',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose a type to add to a SOAP section.',
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: c.inkMuted,
            ),
          ),
          const SizedBox(height: 18),
          for (final type in FieldType.values) ...[
            _FieldTypeChip(type: type, onTap: () => onAdd(type)),
            const SizedBox(height: 7),
          ],
          Divider(height: 36, color: c.border),
          Row(
            children: [
              Expanded(
                child: Text(
                  'SOAP outline',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${fields.length} fields',
                style: TextStyle(
                  fontSize: 10,
                  height: 1.5,
                  color: c.inkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final section in SoapSection.values) ...[
            _OutlineSection(
              section: section,
              fields: fields.where((f) => f.section == section).toList(),
              selectedId: selectedId,
              onSelect: onSelect,
              onReorder: (oldI, newI) => onReorder(section, oldI, newI),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            'Drag fields within or between sections to reorder.',
            style: TextStyle(
              fontSize: 10,
              height: 1.5,
              color: c.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldTypeChip extends StatelessWidget {
  const _FieldTypeChip({required this.type, required this.onTap});

  final FieldType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Material(
      color: c.canvas,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(type.icon, size: 15, color: c.ink),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  type.label,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    color: c.ink,
                  ),
                ),
              ),
              Icon(Icons.add, size: 12, color: c.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutlineSection extends StatelessWidget {
  const _OutlineSection({
    required this.section,
    required this.fields,
    required this.selectedId,
    required this.onSelect,
    required this.onReorder,
  });

  final SoapSection section;
  final List<_DraftField> fields;
  final String? selectedId;
  final ValueChanged<_DraftField> onSelect;
  final ReorderCallback onReorder;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              section.letter,
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: c.purple700,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              section.label,
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (fields.isEmpty)
          Text(
            'No fields',
            style: TextStyle(fontSize: 10, color: c.inkMuted),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: fields.length,
            onReorderItem: onReorder,
            itemBuilder: (context, index) {
              final field = fields[index];
              final selected = field.id == selectedId;
              return Padding(
                key: ValueKey(field.id),
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: selected ? c.pink50 : Colors.transparent,
                  borderRadius: BorderRadius.circular(5),
                  child: InkWell(
                    onTap: () => onSelect(field),
                    borderRadius: BorderRadius.circular(5),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 5,
                      ),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: Icon(
                              Icons.drag_indicator,
                              size: 12,
                              color: c.inkMuted,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              field.label,
                              style: TextStyle(
                                fontSize: 10,
                                height: 1.5,
                                color: selected ? _selectedPink : c.inkMuted,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _EditingColumn extends StatelessWidget {
  const _EditingColumn({
    required this.nameCtrl,
    required this.descCtrl,
    required this.labelCtrl,
    required this.helpCtrl,
    required this.placeholderCtrl,
    required this.selected,
    required this.version,
    required this.practitionerStream,
    required this.onFieldChanged,
    required this.onTypeChanged,
    required this.onSectionChanged,
    required this.onRequiredChanged,
    required this.onDuplicate,
    required this.onDelete,
  });

  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final TextEditingController labelCtrl;
  final TextEditingController helpCtrl;
  final TextEditingController placeholderCtrl;
  final _DraftField? selected;
  final int version;
  final Stream<String?> practitionerStream;
  final VoidCallback onFieldChanged;
  final ValueChanged<FieldType> onTypeChanged;
  final ValueChanged<SoapSection> onSectionChanged;
  final ValueChanged<bool> onRequiredChanged;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Template details',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 15),
              _LabeledField(
                label: 'Template name',
                child: _TextBox(controller: nameCtrl, onChanged: (_) => onFieldChanged()),
              ),
              const SizedBox(height: 15),
              _LabeledField(
                label: 'Description',
                child: _TextBox(controller: descCtrl, onChanged: (_) => onFieldChanged()),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
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
                      'Version $version · Draft',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        color: c.purple700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  StreamBuilder<String?>(
                    stream: practitionerStream,
                    builder: (context, snap) {
                      final name = (snap.data ?? '').trim();
                      return Text(
                        name.isEmpty ? 'Practitioner' : name,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.5,
                          color: c.inkMuted,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (selected != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: _focusPink),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      'Field settings',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: onDuplicate,
                      icon: Icon(Icons.copy_outlined, size: 15, color: c.inkMuted),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      tooltip: 'Duplicate field',
                    ),
                    IconButton(
                      onPressed: onDelete,
                      icon: Icon(Icons.delete_outline, size: 15, color: c.inkMuted),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      tooltip: 'Delete field',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: labelCtrl,
                  builder: (context, value, _) {
                    return Text(
                      '${selected!.section.label} / ${value.text}',
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: _selectedPink,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 17),
                Row(
                  children: [
                    Expanded(
                      child: _LabeledField(
                        label: 'Field type',
                        child: _DropdownBox<FieldType>(
                          value: selected!.type,
                          items: FieldType.values,
                          labelOf: (t) => t.label,
                          onChanged: onTypeChanged,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LabeledField(
                        label: 'SOAP section',
                        child: _DropdownBox<SoapSection>(
                          value: selected!.section,
                          items: SoapSection.values,
                          labelOf: (s) => s.label,
                          onChanged: onSectionChanged,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 17),
                _LabeledField(
                  label: 'Field label',
                  child: _TextBox(
                    controller: labelCtrl,
                    borderColor: _focusPink,
                    onChanged: (_) => onFieldChanged(),
                  ),
                ),
                const SizedBox(height: 17),
                _LabeledField(
                  label: 'Help text',
                  child: _TextBox(
                    controller: helpCtrl,
                    minLines: 3,
                    onChanged: (_) => onFieldChanged(),
                  ),
                ),
                const SizedBox(height: 17),
                _LabeledField(
                  label: 'Placeholder',
                  child: _TextBox(
                    controller: placeholderCtrl,
                    hintStyle: true,
                    onChanged: (_) => onFieldChanged(),
                  ),
                ),
                const SizedBox(height: 17),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Required field',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                              color: c.ink,
                            ),
                          ),
                          Text(
                            'Response needed before completing a note.',
                            style: TextStyle(
                              fontSize: 10,
                              height: 1.5,
                              color: c.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: selected!.required,
                      onChanged: onRequiredChanged,
                      activeThumbColor: c.inkInverse,
                      activeTrackColor: c.purple700,
                    ),
                  ],
                ),
                Divider(height: 34, color: c.border),
                Text(
                  'Field settings change the template structure, not any existing client note.',
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

class _LivePreview extends StatelessWidget {
  const _LivePreview({
    required this.name,
    required this.description,
    required this.fields,
  });

  final String name;
  final String description;
  final List<_DraftField> fields;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final bySection = {
      for (final s in SoapSection.values)
        s: fields.where((f) => f.section == s).toList(),
    };

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Live preview',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: c.purple50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Preview',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                    color: c.purple700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Empty fields · no client information',
            style: TextStyle(fontSize: 11, height: 1.5, color: c.inkMuted),
          ),
          Divider(height: 34, color: c.border),
          Text(
            name.trim().isEmpty ? 'Untitled template' : name,
            style: TextStyle(
              fontSize: 20,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: c.ink,
            ),
          ),
          if (description.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(fontSize: 11, height: 1.5, color: c.inkMuted),
            ),
          ],
          const SizedBox(height: 18),
          for (final section in [
            SoapSection.subjective,
            SoapSection.objective,
          ]) ...[
            Text(
              section.heading,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: c.purple700,
              ),
            ),
            const SizedBox(height: 12),
            for (final field in bySection[section]!) ...[
              _PreviewField(field: field),
              const SizedBox(height: 18),
            ],
            Divider(height: 1, color: c.border),
            const SizedBox(height: 18),
          ],
          for (final section in [
            SoapSection.assessment,
            SoapSection.plan,
          ]) ...[
            Row(
              children: [
                Text(
                  section.heading,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: c.purple700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${bySection[section]!.length} field${bySection[section]!.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.5,
                    color: c.inkMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Divider(height: 1, color: c.border),
          const SizedBox(height: 18),
          Text(
            '* Required. Preview responses are not saved as clinical notes.',
            style: TextStyle(fontSize: 10, height: 1.5, color: c.inkMuted),
          ),
        ],
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
            fontSize: 12,
            height: 1.5,
            fontWeight: FontWeight.w500,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 7),
        Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: field.type.isMultiline ? 72 : 40),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(PelviRadius.sm),
          ),
          child: Text(
            field.placeholder.isEmpty ? ' ' : field.placeholder,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: c.inkMuted,
            ),
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
            height: 1.5,
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
    this.borderColor,
    this.hintStyle = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final int minLines;
  final Color? borderColor;
  final bool hintStyle;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: minLines > 1 ? null : 1,
      onChanged: onChanged,
      style: TextStyle(
        fontSize: 13,
        height: 1.5,
        color: hintStyle ? c.inkMuted : c.ink,
      ),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.all(12),
        filled: true,
        fillColor: c.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PelviRadius.sm),
          borderSide: BorderSide(color: borderColor ?? c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PelviRadius.sm),
          borderSide: BorderSide(color: borderColor ?? c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PelviRadius.sm),
          borderSide: BorderSide(color: borderColor ?? c.pink700),
        ),
      ),
    );
  }
}

class _DropdownBox<T> extends StatelessWidget {
  const _DropdownBox({
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(PelviRadius.sm),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.expand_more, size: 18, color: c.inkMuted),
          style: TextStyle(fontSize: 13, height: 1.5, color: c.ink),
          items: [
            for (final item in items)
              DropdownMenuItem(value: item, child: Text(labelOf(item))),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
