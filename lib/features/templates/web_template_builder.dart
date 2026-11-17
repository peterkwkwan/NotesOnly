import 'package:flutter/material.dart';

import '../../data/auth.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/show_snack.dart';
import '../notes/soap_dictation.dart';
import '../shell/desktop_chrome.dart';
import 'template_answer_control.dart';
import 'template_body.dart';

extension on SoapSection {
  String get letter => switch (this) {
    SoapSection.subjective => 'S',
    SoapSection.objective => 'O',
    SoapSection.assessment => 'A',
    SoapSection.plan => 'P',
  };

  String get blurb => switch (this) {
    SoapSection.subjective => 'What the client reports',
    SoapSection.objective => 'What you observe',
    SoapSection.assessment => 'Your clinical read',
    SoapSection.plan => 'What happens next',
  };
}

/// Desktop template editor for the content pane. The app sidebar and top bar
/// stay outside this widget.
class WebTemplateBuilder extends StatefulWidget {
  const WebTemplateBuilder({
    super.key,
    this.initialName = 'Postnatal Check',
    this.initialDescription = 'Guided prompts for a postnatal review.',
    this.seedPostnatal = true,
    this.remoteId,
    this.fieldsJson,
    this.initialPublished = false,
    this.initialHasPendingDraft = false,
    this.onBackToLibrary,
  });

  final String initialName;
  final String initialDescription;
  final bool seedPostnatal;

  /// Set when editing an org template. Null starts a new org record on save.
  final String? remoteId;

  /// Saved builder fields. Null uses the postnatal or blank starter.
  final String? fieldsJson;

  /// Live published flag on the org row (teammates still see published body).
  final bool initialPublished;

  /// True when opening a published row that already has a draft overlay.
  final bool initialHasPendingDraft;
  final VoidCallback? onBackToLibrary;

  @override
  State<WebTemplateBuilder> createState() => _WebTemplateBuilderState();
}

class _WebTemplateBuilderState extends State<WebTemplateBuilder> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final Map<SoapSection, TextEditingController> _sectionCtrls;

  late SoapSection _section;
  String? _remoteId;
  bool _published = false;
  bool _hasPendingDraft = false;
  bool _saving = false;

  bool get _chipPublished => _published && !_hasPendingDraft;

  @override
  void initState() {
    super.initState();
    _remoteId = widget.remoteId;
    _published = widget.initialPublished;
    _hasPendingDraft = widget.initialHasPendingDraft;
    final seedFields = widget.fieldsJson != null
        ? decodeTemplateFields(widget.fieldsJson!)
        : widget.seedPostnatal
        ? _seedPostnatalFields()
        : <TemplateField>[];
    final bodies = sectionBodiesFromFields(seedFields);
    _sectionCtrls = {
      for (final section in SoapSection.values)
        section: TextEditingController(text: bodies[section] ?? ''),
    };
    _section = SoapSection.subjective;
    _nameCtrl = TextEditingController(text: widget.initialName);
    _descCtrl = TextEditingController(text: widget.initialDescription);
    _nameCtrl.addListener(() => setState(() {}));
  }

  List<TemplateField> _seedPostnatalFields() {
    return [
      TemplateField(
        id: 'f1',
        section: SoapSection.subjective,
        label: 'Presenting concerns\n\nClient goals',
      ),
      TemplateField(
        id: 'f2',
        section: SoapSection.objective,
        label: 'Observations\n\nMeasurements',
      ),
      TemplateField(
        id: 'f3',
        section: SoapSection.assessment,
        label: 'Clinical interpretation',
      ),
      TemplateField(
        id: 'f4',
        section: SoapSection.plan,
        label: 'Agreed next steps\n\nFollow-up interval\n\nReview notes',
      ),
    ];
  }

  void _selectSection(SoapSection section) {
    if (section == _section) return;
    setState(() => _section = section);
  }

  List<TemplateField> _fieldsForSave() => fieldsFromSectionBodies({
    for (final section in SoapSection.values)
      section: _sectionCtrls[section]!.text,
  });

  Future<void> _persist({required bool published}) async {
    if (_saving) return;
    final db = AppDatabaseProvider.maybeOf(context);
    if (db == null) return;
    setState(() => _saving = true);
    final authUser = NotesAuth.currentUser;
    final bound = await db.getSetting(AppDatabase.syncBoundUidKey);
    if (!mounted) return;
    final authUid = authUser?.uid ?? '';
    final uid = authUid.isNotEmpty ? authUid : (bound ?? '');
    final liveName = authUser?.displayName?.trim() ?? '';
    try {
      final saved = await db.saveOrgTemplate(
        remoteId: _remoteId,
        name: _nameCtrl.text,
        description: _descCtrl.text.trim(),
        fieldsJson: encodeTemplateFields(_fieldsForSave()),
        createdBy: uid,
        createdByName: liveName,
        published: published,
      );
      if (!mounted) return;
      setState(() {
        _remoteId = saved.remoteId;
        _published = saved.published;
        _hasPendingDraft = templateHasPendingDraft(saved);
      });
      showPelviSnackBar(
        context,
        published ? 'Published for the clinic.' : 'Draft saved.',
      );
    } catch (e) {
      if (!mounted) return;
      showPelviSnackBar(context, 'Could not save template: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    for (final ctrl in _sectionCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  String get _crumbName {
    final name = _nameCtrl.text.trim();
    return name.isEmpty ? 'Untitled template' : name;
  }

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Scaffold(
      backgroundColor: c.canvas,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 640;
          return Padding(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _pageHeader(context),
                const SizedBox(height: 20),
                Expanded(
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _outline(context),
                            const SizedBox(width: 20),
                            Expanded(child: _editor(context, scroll: true)),
                          ],
                        )
                      : SingleChildScrollView(
                          child: Column(
                            children: [
                              _outline(context, pinFooter: false),
                              const SizedBox(height: 20),
                              _editor(context, scroll: false),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _pageHeader(BuildContext context) {
    final c = PelviColors.of(context);
    final back = widget.onBackToLibrary;
    return DesktopPageHeader(
      title: 'Template builder',
      breadcrumb: 'Templates / $_crumbName',
      onBreadcrumbAncestor: back == null ? null : (_) => back(),
      actions: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: _chipPublished ? c.pink50 : c.purple50,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            _chipPublished ? 'Published' : 'Draft',
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: _chipPublished ? c.pink700 : c.purple700,
            ),
          ),
        ),
        DesktopOutlineAction(
          label: _saving ? 'Saving…' : 'Save draft',
          onPressed: _saving ? null : () => _persist(published: false),
        ),
        DesktopFilledAction(
          label: 'Publish',
          onPressed: _saving ? null : () => _persist(published: true),
        ),
      ],
    );
  }

  BoxDecoration _card(PelviPalette c) => BoxDecoration(
    color: c.surface,
    borderRadius: BorderRadius.circular(PelviRadius.button),
    border: Border.all(color: c.border),
  );

  Widget _outline(BuildContext context, {bool pinFooter = true}) {
    final c = PelviColors.of(context);
    return SizedBox(
      width: 280,
      child: DecoratedBox(
        decoration: _card(c),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _nameRow(context),
              const SizedBox(height: 12),
              Text(
                'Sections',
                style: TextStyle(
                  fontSize: 11,
                  height: 16 / 11,
                  color: c.inkMuted,
                ),
              ),
              const SizedBox(height: 4),
              for (final section in SoapSection.values)
                _sectionTile(context, section),
              if (pinFooter) const Spacer() else const SizedBox(height: 24),
              Text(
                'One prompt per SOAP section.',
                style: TextStyle(
                  fontSize: 11,
                  height: 15 / 11,
                  color: c.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nameRow(BuildContext context) {
    final c = PelviColors.of(context);
    return TextField(
      controller: _nameCtrl,
      maxLines: 1,
      style: TextStyle(
        fontSize: 15,
        height: 20 / 15,
        fontWeight: FontWeight.w600,
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
          fontSize: 15,
          height: 20 / 15,
          fontWeight: FontWeight.w600,
          color: c.inkMuted,
        ),
      ),
    );
  }

  Widget _sectionTile(BuildContext context, SoapSection section) {
    final c = PelviColors.of(context);
    final selected = section == _section;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? c.pink50 : Colors.transparent,
        borderRadius: BorderRadius.circular(PelviRadius.sm),
        child: InkWell(
          onTap: () => _selectSection(section),
          borderRadius: BorderRadius.circular(PelviRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  child: Text(
                    section.letter,
                    style: TextStyle(
                      fontSize: 12,
                      height: 16 / 12,
                      fontWeight: FontWeight.w600,
                      color: c.pink700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    section.label,
                    style: TextStyle(
                      fontSize: 13,
                      height: 18 / 13,
                      color: c.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _editor(BuildContext context, {required bool scroll}) {
    final c = PelviColors.of(context);
    final header = _sectionHeader(context);
    final body = _sectionBody(context);
    return DecoratedBox(
      decoration: _card(c),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        child: scroll
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  const SizedBox(height: 14),
                  Expanded(child: body),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [header, const SizedBox(height: 14), body],
              ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context) {
    final c = PelviColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _section.label,
          style: TextStyle(
            fontSize: 18,
            height: 24 / 18,
            fontWeight: FontWeight.w600,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _section.blurb,
          style: TextStyle(
            fontSize: 12,
            height: 16 / 12,
            color: c.inkMuted,
          ),
        ),
      ],
    );
  }

  Widget _sectionBody(BuildContext context) {
    final c = PelviColors.of(context);
    final ctrl = _sectionCtrls[_section]!;
    // maxLines 20: ~20-line viewport; longer content scrolls inside the field.
    return TextField(
      controller: ctrl,
      minLines: 12,
      maxLines: 20,
      keyboardType: TextInputType.multiline,
      style: TextStyle(fontSize: 13, height: 1.5, color: c.ink),
      decoration: templateFieldDecoration(
        c,
        hint: 'Write the ${_section.label.toLowerCase()} prompt…',
        dense: false,
      ),
    );
  }
}
