import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../templates/template_answer_control.dart';
import '../templates/template_fields.dart';
import 'soap_dictation.dart';

/// One SOAP letter section rendered as typed template questions.
class SoapTypedSection extends StatelessWidget {
  const SoapTypedSection({
    super.key,
    required this.letter,
    required this.label,
    required this.section,
    required this.fields,
    required this.answers,
    required this.onAnswerChanged,
  });

  final String letter;
  final String label;
  final SoapSection section;
  final List<TemplateField> fields;
  final Map<String, String> answers;
  final void Function(String fieldId, String value) onAnswerChanged;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final prompts = [
      for (final f in fields)
        if (f.section == section) f,
    ];
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
        const SizedBox(height: 12),
        if (prompts.isEmpty)
          Text(
            'No questions in this section.',
            style: TextStyle(fontSize: 13, color: c.inkMuted),
          )
        else
          for (var i = 0; i < prompts.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            _TypedPrompt(
              field: prompts[i],
              value: answers[prompts[i].id] ?? '',
              onChanged: (v) => onAnswerChanged(prompts[i].id, v),
            ),
          ],
      ],
    );
  }
}

class _TypedPrompt extends StatelessWidget {
  const _TypedPrompt({
    required this.field,
    required this.value,
    required this.onChanged,
  });

  final TemplateField field;
  final String value;
  final ValueChanged<String> onChanged;

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
        TemplateAnswerControl(
          field: field,
          value: value,
          onChanged: onChanged,
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
