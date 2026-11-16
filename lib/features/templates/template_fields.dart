import 'dart:convert';

import '../notes/soap_dictation.dart';

enum FieldType {
  longText,
  shortText,
  singleChoice,
  multipleChoice,
  numeric,
  yesNo,
}

extension FieldTypeLabel on FieldType {
  String get label => switch (this) {
    FieldType.longText => 'Long text',
    FieldType.shortText => 'Short text',
    FieldType.singleChoice => 'Single choice',
    FieldType.multipleChoice => 'Multiple choice',
    FieldType.numeric => 'Numeric',
    FieldType.yesNo => 'Yes/No',
  };

  bool get isMultiline => this == FieldType.longText;

  bool get usesOptions =>
      this == FieldType.singleChoice || this == FieldType.multipleChoice;
}

const defaultChoiceOptions = ['Option 1', 'Option 2'];

/// One prompt in an org SOAP template.
class TemplateField {
  TemplateField({
    required this.id,
    required this.type,
    required this.section,
    required this.label,
    this.helpText = '',
    this.placeholder = '',
    this.required = false,
    List<String>? options,
  }) : options = options ?? <String>[];

  final String id;
  FieldType type;
  SoapSection section;
  String label;
  String helpText;
  String placeholder;
  bool required;

  /// Choice labels for single/multiple choice. Ignored for other types.
  List<String> options;
}

FieldType fieldTypeFromName(String raw) {
  for (final type in FieldType.values) {
    if (type.name == raw) return type;
  }
  return FieldType.longText;
}

SoapSection soapSectionFromName(String raw) {
  for (final section in SoapSection.values) {
    if (section.name == raw) return section;
  }
  return SoapSection.subjective;
}

List<String> _decodeOptions(Object? raw) {
  if (raw is! List) return [];
  return [
    for (final item in raw)
      if (item != null && item.toString().trim().isNotEmpty) item.toString(),
  ];
}

String encodeTemplateFields(List<TemplateField> fields) {
  return jsonEncode([
    for (final field in fields)
      {
        'id': field.id,
        'type': field.type.name,
        'section': field.section.name,
        'label': field.label,
        'helpText': field.helpText,
        'placeholder': field.placeholder,
        'required': field.required,
        if (field.options.isNotEmpty) 'options': field.options,
      },
  ]);
}

List<TemplateField> decodeTemplateFields(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    final out = <TemplateField>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final id = item['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final type = fieldTypeFromName(item['type']?.toString() ?? '');
      var options = _decodeOptions(item['options']);
      if (type.usesOptions && options.isEmpty) {
        options = List<String>.from(defaultChoiceOptions);
      }
      out.add(
        TemplateField(
          id: id,
          type: type,
          section: soapSectionFromName(item['section']?.toString() ?? ''),
          label: item['label']?.toString() ?? '',
          helpText: item['helpText']?.toString() ?? '',
          placeholder: item['placeholder']?.toString() ?? '',
          required: item['required'] == true,
          options: options,
        ),
      );
    }
    return out;
  } catch (_) {
    return [];
  }
}

/// Legacy prompt dump (built-in free-text templates). Prefer [soapTextFromAnswers].
({String subjective, String objective, String assessment, String plan})
soapFillFromFields(List<TemplateField> fields) {
  String join(SoapSection section) {
    return [
      for (final field in fields)
        if (field.section == section && field.label.trim().isNotEmpty)
          field.label.trim(),
    ].join('\n');
  }

  return (
    subjective: join(SoapSection.subjective),
    objective: join(SoapSection.objective),
    assessment: join(SoapSection.assessment),
    plan: join(SoapSection.plan),
  );
}

/// Human-readable S/O/A/P from typed answers (Label: value).
({String subjective, String objective, String assessment, String plan})
soapTextFromAnswers(List<TemplateField> fields, Map<String, String> answers) {
  String join(SoapSection section) {
    final lines = <String>[];
    for (final field in fields) {
      if (field.section != section) continue;
      final label = field.label.trim();
      if (label.isEmpty) continue;
      final value = (answers[field.id] ?? '').trim();
      lines.add(value.isEmpty ? label : '$label: $value');
    }
    return lines.join('\n');
  }

  return (
    subjective: join(SoapSection.subjective),
    objective: join(SoapSection.objective),
    assessment: join(SoapSection.assessment),
    plan: join(SoapSection.plan),
  );
}

/// Typed note payload stored in [Note.addendum] (syncs; legacy column).
String encodeFieldAnswersEnvelope({
  required List<TemplateField> fields,
  required Map<String, String> answers,
}) {
  return jsonEncode({
    'v': 1,
    'fields': jsonDecode(encodeTemplateFields(fields)),
    'answers': answers,
  });
}

({List<TemplateField> fields, Map<String, String> answers})?
tryDecodeFieldAnswersEnvelope(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return null;
    if (decoded['v'] != 1) return null;
    final fields = decodeTemplateFields(jsonEncode(decoded['fields'] ?? []));
    if (fields.isEmpty) return null;
    final answersRaw = decoded['answers'];
    final answers = <String, String>{};
    if (answersRaw is Map) {
      for (final e in answersRaw.entries) {
        answers[e.key.toString()] = e.value?.toString() ?? '';
      }
    }
    return (fields: fields, answers: answers);
  } catch (_) {
    return null;
  }
}
