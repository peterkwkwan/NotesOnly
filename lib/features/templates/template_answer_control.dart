import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/theme.dart';
import 'template_fields.dart';

/// Type-appropriate answer control for template builder preview and SOAP fill.
class TemplateAnswerControl extends StatelessWidget {
  const TemplateAnswerControl({
    super.key,
    required this.field,
    this.value = '',
    this.onChanged,
    this.editingOptions = false,
    this.onOptionsChanged,
    this.enabled = true,
  });

  final TemplateField field;
  final String value;
  final ValueChanged<String>? onChanged;

  /// When true, choice options are editable (builder).
  final bool editingOptions;
  final VoidCallback? onOptionsChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return switch (field.type) {
      FieldType.longText => _TextAnswer(
        field: field,
        value: value,
        onChanged: onChanged,
        enabled: enabled,
        maxLines: 5,
        minLines: 3,
      ),
      FieldType.shortText => _TextAnswer(
        field: field,
        value: value,
        onChanged: onChanged,
        enabled: enabled,
        maxLines: 1,
      ),
      FieldType.numeric => _TextAnswer(
        field: field,
        value: value,
        onChanged: onChanged,
        enabled: enabled,
        maxLines: 1,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
      ),
      FieldType.yesNo => _YesNoAnswer(
        value: value,
        onChanged: onChanged,
        enabled: enabled,
      ),
      FieldType.singleChoice => _ChoiceAnswer(
        field: field,
        value: value,
        onChanged: onChanged,
        enabled: enabled,
        multiple: false,
        editingOptions: editingOptions,
        onOptionsChanged: onOptionsChanged,
      ),
      FieldType.multipleChoice => _ChoiceAnswer(
        field: field,
        value: value,
        onChanged: onChanged,
        enabled: enabled,
        multiple: true,
        editingOptions: editingOptions,
        onOptionsChanged: onOptionsChanged,
      ),
    };
  }
}

InputDecoration templateFieldDecoration(
  PelviPalette c, {
  String? hint,
  bool dense = true,
}) {
  OutlineInputBorder edge(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(PelviRadius.sm),
    borderSide: BorderSide(color: color),
  );
  return InputDecoration(
    isDense: dense,
    filled: true,
    fillColor: c.surface,
    contentPadding: EdgeInsets.symmetric(
      horizontal: 10,
      vertical: dense ? 9 : 12,
    ),
    hintText: hint,
    hintStyle: TextStyle(fontSize: 13, height: 1.5, color: c.inkMuted),
    border: edge(c.border),
    enabledBorder: edge(c.border),
    focusedBorder: edge(c.pink700),
    disabledBorder: edge(c.border),
  );
}

class _TextAnswer extends StatefulWidget {
  const _TextAnswer({
    required this.field,
    required this.value,
    required this.onChanged,
    required this.enabled,
    required this.maxLines,
    this.minLines,
    this.keyboardType,
    this.inputFormatters,
  });

  final TemplateField field;
  final String value;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final int maxLines;
  final int? minLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<_TextAnswer> createState() => _TextAnswerState();
}

class _TextAnswerState extends State<_TextAnswer> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_TextAnswer old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _ctrl.text != widget.value) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final hint = widget.field.placeholder.isEmpty
        ? null
        : widget.field.placeholder;
    return TextField(
      controller: _ctrl,
      enabled: widget.enabled && widget.onChanged != null,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      onChanged: widget.onChanged,
      style: TextStyle(fontSize: 13, height: 1.5, color: c.ink),
      decoration: templateFieldDecoration(c, hint: hint, dense: widget.maxLines == 1),
    );
  }
}

class _YesNoAnswer extends StatelessWidget {
  const _YesNoAnswer({
    required this.value,
    required this.onChanged,
    required this.enabled,
  });

  final String value;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final selected = value == 'Yes'
        ? true
        : value == 'No'
        ? false
        : null;
    return Row(
      children: [
        _YesNoChip(
          label: 'Yes',
          selected: selected == true,
          enabled: enabled && onChanged != null,
          onTap: () => onChanged?.call(selected == true ? '' : 'Yes'),
          colors: c,
        ),
        const SizedBox(width: 8),
        _YesNoChip(
          label: 'No',
          selected: selected == false,
          enabled: enabled && onChanged != null,
          onTap: () => onChanged?.call(selected == false ? '' : 'No'),
          colors: c,
        ),
      ],
    );
  }
}

class _YesNoChip extends StatelessWidget {
  const _YesNoChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final PelviPalette colors;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? colors.pink50 : colors.surface,
      borderRadius: BorderRadius.circular(PelviRadius.sm),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(PelviRadius.sm),
        child: Container(
          constraints: const BoxConstraints(minWidth: 72, minHeight: 36),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PelviRadius.sm),
            border: Border.all(color: selected ? colors.pink700 : colors.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: selected ? colors.pink700 : colors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChoiceAnswer extends StatelessWidget {
  const _ChoiceAnswer({
    required this.field,
    required this.value,
    required this.onChanged,
    required this.enabled,
    required this.multiple,
    required this.editingOptions,
    required this.onOptionsChanged,
  });

  final TemplateField field;
  final String value;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool multiple;
  final bool editingOptions;
  final VoidCallback? onOptionsChanged;

  List<String> get _selected {
    if (value.isEmpty) return const [];
    if (!multiple) return [value];
    return value.split('\n').where((s) => s.isNotEmpty).toList();
  }

  void _toggle(String option) {
    if (onChanged == null) return;
    if (!multiple) {
      onChanged!(value == option ? '' : option);
      return;
    }
    final next = [..._selected];
    if (next.contains(option)) {
      next.remove(option);
    } else {
      next.add(option);
    }
    onChanged!(next.join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final options = field.options.isEmpty
        ? defaultChoiceOptions
        : field.options;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          if (editingOptions)
            _EditableOptionRow(
              index: i,
              text: options[i],
              multiple: multiple,
              selected: _selected.contains(options[i]),
              colors: c,
              onChanged: (text) {
                field.options[i] = text;
                onOptionsChanged?.call();
              },
              onRemove: options.length <= 1
                  ? null
                  : () {
                      field.options.removeAt(i);
                      onOptionsChanged?.call();
                    },
            )
          else
            _OptionRow(
              label: options[i],
              multiple: multiple,
              selected: _selected.contains(options[i]),
              enabled: enabled && onChanged != null,
              onTap: () => _toggle(options[i]),
              colors: c,
            ),
        ],
        if (editingOptions) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                field.options = [...field.options, 'Option ${field.options.length + 1}'];
                onOptionsChanged?.call();
              },
              icon: Icon(Icons.add, size: 16, color: c.pink700),
              label: const Text('Add option'),
              style: TextButton.styleFrom(
                foregroundColor: c.pink700,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.multiple,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final bool multiple;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final PelviPalette colors;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(PelviRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              multiple
                  ? (selected
                        ? Icons.check_box
                        : Icons.check_box_outline_blank)
                  : (selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off),
              size: 20,
              color: selected ? colors.pink700 : colors.inkMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 13, height: 1.4, color: colors.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableOptionRow extends StatefulWidget {
  const _EditableOptionRow({
    required this.index,
    required this.text,
    required this.multiple,
    required this.selected,
    required this.colors,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final String text;
  final bool multiple;
  final bool selected;
  final PelviPalette colors;
  final ValueChanged<String> onChanged;
  final VoidCallback? onRemove;

  @override
  State<_EditableOptionRow> createState() => _EditableOptionRowState();
}

class _EditableOptionRowState extends State<_EditableOptionRow> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.text);
  }

  @override
  void didUpdateWidget(_EditableOptionRow old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text && _ctrl.text != widget.text) {
      _ctrl.text = widget.text;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Row(
      children: [
        Icon(
          widget.multiple
              ? Icons.check_box_outline_blank
              : Icons.radio_button_off,
          size: 20,
          color: c.inkMuted,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _ctrl,
            onChanged: widget.onChanged,
            style: TextStyle(fontSize: 13, height: 1.2, color: c.ink),
            decoration: templateFieldDecoration(c, hint: 'Option'),
          ),
        ),
        if (widget.onRemove != null)
          IconButton(
            tooltip: 'Remove option',
            onPressed: widget.onRemove,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, size: 16, color: c.inkMuted),
          ),
      ],
    );
  }
}
