import '../../data/database.dart';
import '../notes/soap_templates.dart';
import 'template_fields.dart';

export 'template_fields.dart';

const orgTemplateIdPrefix = 'org:';

String orgTemplateChoiceId(String remoteId) => '$orgTemplateIdPrefix$remoteId';

SoapTemplate soapTemplateFromOrgRow(Template row) {
  final fill = soapFillFromFields(decodeTemplateFields(row.fieldsJson));
  // One textarea per SOAP section: dump joined prompts into free-text fill.
  return SoapTemplate(
    id: orgTemplateChoiceId(row.remoteId),
    label: row.name,
    subjective: fill.subjective,
    objective: fill.objective,
    assessment: fill.assessment,
    plan: fill.plan,
  );
}

/// Built-in starters, then org records the viewer may use (own + published team).
Future<List<SoapTemplate>> soapTemplateChoices(
  AppDatabase db, {
  String? viewerUid,
}) async {
  final org = await db.listOrgTemplates();
  final hidden = await db.getHiddenBuiltinTemplateIds();
  final uid = (viewerUid ?? await db.getSetting(AppDatabase.syncBoundUidKey) ?? '')
      .trim();
  return [
    for (final t in soapTemplates)
      if (!hidden.contains(t.id)) t,
    for (final row in org)
      if (row.published ||
          row.createdBy.isEmpty ||
          (uid.isNotEmpty && row.createdBy == uid))
        soapTemplateFromOrgRow(row),
  ];
}

/// Same set as Templates → Published, plus published Team templates.
/// Excludes draft builtins (e.g. DRAM) and unpublished org rows.
Future<List<SoapTemplate>> publishedSoapTemplateChoices(AppDatabase db) async {
  final org = await db.listOrgTemplates();
  final hidden = await db.getHiddenBuiltinTemplateIds();
  return [
    for (final t in soapTemplates)
      if (!hidden.contains(t.id) && !draftBuiltinTemplateIds.contains(t.id)) t,
    for (final row in org)
      if (row.published) soapTemplateFromOrgRow(row),
  ];
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
