import 'dart:convert';

import '../../data/database.dart';
import '../notes/soap_dictation.dart';
import '../notes/soap_templates.dart';

enum FieldType { longText, shortText, singleChoice, multipleChoice, numeric }

extension FieldTypeLabel on FieldType {
  String get label => switch (this) {
    FieldType.longText => 'Long text',
    FieldType.shortText => 'Short text',
    FieldType.singleChoice => 'Single choice',
    FieldType.multipleChoice => 'Multiple choice',
    FieldType.numeric => 'Numeric',
  };

  bool get isMultiline => this == FieldType.longText;
}

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
  });

  final String id;
  FieldType type;
  SoapSection section;
  String label;
  String helpText;
  String placeholder;
  bool required;
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
      out.add(
        TemplateField(
          id: id,
          type: fieldTypeFromName(item['type']?.toString() ?? ''),
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

/// Note fill: field labels, grouped into S/O/A/P. Placeholders stay in the builder.
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

const orgTemplateIdPrefix = 'org:';

String orgTemplateChoiceId(String remoteId) => '$orgTemplateIdPrefix$remoteId';

SoapTemplate soapTemplateFromOrgRow(Template row) {
  final fill = soapFillFromFields(decodeTemplateFields(row.fieldsJson));
  return SoapTemplate(
    id: orgTemplateChoiceId(row.remoteId),
    label: row.name,
    subjective: fill.subjective,
    objective: fill.objective,
    assessment: fill.assessment,
    plan: fill.plan,
  );
}

/// Built-in starters, then org records (newest first).
Future<List<SoapTemplate>> soapTemplateChoices(AppDatabase db) async {
  final org = await db.listOrgTemplates();
  return [...soapTemplates, for (final row in org) soapTemplateFromOrgRow(row)];
}

/// Creator name when we have one stored, or the viewer's live name for their own row.
String? templateCreatorLabel({
  required String createdByName,
  required String createdBy,
  required String? viewerUid,
  String? viewerName,
}) {
  final stored = createdByName.trim();
  if (stored.isNotEmpty) return stored;
  final uid = viewerUid?.trim() ?? '';
  final live = viewerName?.trim() ?? '';
  if (uid.isNotEmpty && createdBy == uid && live.isNotEmpty) return live;
  return null;
}

/// True when [createdBy] is the signed-in member. Built-ins (null) are not mine.
bool templateMatchesMine({
  required String? createdBy,
  required String? viewerUid,
}) {
  final uid = viewerUid?.trim() ?? '';
  if (uid.isEmpty) return false;
  return createdBy != null && createdBy == uid;
}
