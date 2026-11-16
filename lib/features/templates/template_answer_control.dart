import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'template_fields.dart';

/// Plain textarea for template builder preview and SOAP fill (~10 lines tall).
class TemplateAnswerControl extends StatelessWidget {
  const TemplateAnswerControl({
    super.key,
    required this.field,
    this.value = '',
    this.onChanged,
    this.enabled = true,
  });

  final TemplateField field;
  final String value;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _TextAnswer(
      field: field,
      value: value,
      onChanged: onChanged,
      enabled: enabled,
    );
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
  });

  final TemplateField field;
  final String value;
  final ValueChanged<String>? onChanged;
  final bool enabled;

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
    // maxLines 10: ~10-line viewport; longer content scrolls inside the field.
    return TextField(
      controller: _ctrl,
      enabled: widget.enabled && widget.onChanged != null,
      minLines: 10,
      maxLines: 10,
      keyboardType: TextInputType.multiline,
      onChanged: widget.onChanged,
      style: TextStyle(fontSize: 13, height: 1.5, color: c.ink),
      decoration: templateFieldDecoration(c, hint: hint, dense: false),
    );
  }
}
