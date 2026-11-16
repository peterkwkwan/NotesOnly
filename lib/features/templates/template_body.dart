import '../../data/database.dart';
import '../notes/soap_templates.dart';
import 'template_fields.dart';

export 'template_fields.dart';

const orgTemplateIdPrefix = 'org:';

String orgTemplateChoiceId(String remoteId) => '$orgTemplateIdPrefix$remoteId';

SoapTemplate soapTemplateFromOrgRow(Template row) {
  final fields = decodeTemplateFields(row.fieldsJson);
  // Org builder templates drive typed controls; do not dump labels into textareas.
  return SoapTemplate(
    id: orgTemplateChoiceId(row.remoteId),
    label: row.name,
    fields: fields,
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
