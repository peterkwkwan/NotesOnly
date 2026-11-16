import 'dart:convert';

import '../notes/soap_dictation.dart';

/// One prompt in an org SOAP template (plain textarea answer).
class TemplateField {
  TemplateField({
    required this.id,
    required this.section,
    required this.label,
    this.helpText = '',
    this.placeholder = '',
    this.required = false,
  });

  final String id;
  SoapSection section;
  String label;
  String helpText;
  String placeholder;
  bool required;
}

SoapSection soapSectionFromName(String raw) {
  for (final section in SoapSection.values) {
    if (section.name == raw) return section;
  }
  return SoapSection.subjective;
}

String encodeTemplateFields(List<TemplateField> fields) {
  return jsonEncode([
    for (final field in fields)
      {
        'id': field.id,
        'section': field.section.name,
        'label': field.label,
        'helpText': field.helpText,
        'placeholder': field.placeholder,
        'required': field.required,
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
      // Ignore legacy type/options; every field is a textarea.
      out.add(
        TemplateField(
          id: id,
          section: soapSectionFromName(item['section']?.toString() ?? ''),
          label: item['label']?.toString() ?? '',
          helpText: item['helpText']?.toString() ?? '',
          placeholder: item['placeholder']?.toString() ?? '',
          required: item['required'] == true,
        ),
      );
    }
    return out;
  } catch (_) {
    return [];
  }
}

/// Collapse multi-question rows into one body per SOAP section.
/// Uses label, else placeholder; joins with a blank line.
Map<SoapSection, String> sectionBodiesFromFields(List<TemplateField> fields) {
  final out = <SoapSection, String>{
    for (final section in SoapSection.values) section: '',
  };
  for (final section in SoapSection.values) {
    final parts = <String>[];
    for (final field in fields) {
      if (field.section != section) continue;
      final label = field.label.trim();
      final text = label.isNotEmpty ? label : field.placeholder.trim();
      if (text.isNotEmpty) parts.add(text);
    }
    out[section] = parts.join('\n\n');
  }
  return out;
}

/// Persist one long-text field per non-empty SOAP section.
List<TemplateField> fieldsFromSectionBodies(Map<SoapSection, String> bodies) {
  final out = <TemplateField>[];
  var i = 0;
  for (final section in SoapSection.values) {
    final text = (bodies[section] ?? '').trim();
    if (text.isEmpty) continue;
    i += 1;
    out.add(TemplateField(id: 'f$i', section: section, label: text));
  }
  return out;
}

/// Free-text S/O/A/P dump from builder fields (legacy multi-question → joined).
({String subjective, String objective, String assessment, String plan})
soapFillFromFields(List<TemplateField> fields) {
  final bodies = sectionBodiesFromFields(fields);
  return (
    subjective: bodies[SoapSection.subjective] ?? '',
    objective: bodies[SoapSection.objective] ?? '',
    assessment: bodies[SoapSection.assessment] ?? '',
    plan: bodies[SoapSection.plan] ?? '',
  );
}

/// Human-readable S/O/A/P from per-question answers (Label: value).
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

/// Note payload stored in [Note.addendum] (syncs; legacy column).
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
