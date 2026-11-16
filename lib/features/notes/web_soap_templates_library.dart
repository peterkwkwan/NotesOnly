import 'package:flutter/material.dart';

import '../../data/auth.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/show_snack.dart';
import '../shell/desktop_chrome.dart';
import '../templates/template_body.dart';
import 'soap_templates.dart';

/// Opens the template builder from the library (Edit draft / Create draft).
typedef OpenTemplateBuilder =
    void Function({
      required String name,
      String description,
      bool seedPostnatal,
      String? remoteId,
      String? fieldsJson,
      bool published,
    });

/// Desktop SOAP template library (Figma `NotesOnly · SOAP template library`).
///
/// Built-in starters stay in the list. Saved templates are org records.
class WebSoapTemplatesLibrary extends StatefulWidget {
  const WebSoapTemplatesLibrary({super.key, this.onOpenBuilder});

  final OpenTemplateBuilder? onOpenBuilder;

  @override
  State<WebSoapTemplatesLibrary> createState() =>
      _WebSoapTemplatesLibraryState();
}

enum _LibraryTab { all, published, drafts, team }

class _WebSoapTemplatesLibraryState extends State<WebSoapTemplatesLibrary> {
  _LibraryTab _tab = _LibraryTab.all;
  String _query = '';
  String? _selectedId = 'postnatal_check';
  bool _showNewPanel = true;
  Stream<List<Template>>? _orgStream;
  Stream<String?>? _uidStream;
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _startFromId = blankId;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String? _viewerUid(String? boundUid) {
    final authUid = NotesAuth.currentUser?.uid ?? '';
    if (authUid.isNotEmpty) return authUid;
    final bound = boundUid?.trim() ?? '';
    if (bound.isNotEmpty) return bound;
    return null;
  }

  /// Built-ins live in the owner's All/Published/Drafts tabs; org rows use creator.
  bool _inOwnLibrary(_LibraryEntry e, String? viewerUid) {
    if (e.createdBy == null) return true;
    return templateMatchesMine(createdBy: e.createdBy, viewerUid: viewerUid);
  }

  bool _inTeamLibrary(_LibraryEntry e, String? viewerUid) {
    if (e.createdBy == null) return false;
    if (!e.isPublished) return false;
    return !templateMatchesMine(createdBy: e.createdBy, viewerUid: viewerUid);
  }

  bool _canEdit(_LibraryEntry e, String? viewerUid) {
    if (e.createdBy == null) return true;
    return templateMatchesMine(createdBy: e.createdBy, viewerUid: viewerUid);
  }

  List<_LibraryEntry> _entriesFor(List<Template> org, String? viewerUid) => [
    ..._builtinEntries,
    for (final row in org) _orgEntry(row, viewerUid),
  ];

  List<_LibraryEntry> _ownFor(List<Template> org, String? viewerUid) => [
    for (final entry in _entriesFor(org, viewerUid))
      if (_inOwnLibrary(entry, viewerUid)) entry,
  ];

  List<_LibraryEntry> _teamFor(List<Template> org, String? viewerUid) => [
    for (final entry in _entriesFor(org, viewerUid))
      if (_inTeamLibrary(entry, viewerUid)) entry,
  ];

  List<_LibraryEntry> _tabBase(List<Template> org, String? viewerUid) {
    if (_tab == _LibraryTab.team) return _teamFor(org, viewerUid);
    return _ownFor(org, viewerUid);
  }

  _LibraryEntry _orgEntry(Template row, String? viewerUid) {
    final creator = templateCreatorLabel(
      createdByName: row.createdByName,
      createdBy: row.createdBy,
      viewerUid: viewerUid,
      viewerName: NotesAuth.currentUser?.displayName,
    );
    final filled = sectionBodiesFromFields(
      decodeTemplateFields(row.fieldsJson),
    ).values.where((t) => t.trim().isNotEmpty).length;
    final sections = filled == 1 ? '1 section' : '$filled sections';
    return _LibraryEntry(
      template: SoapTemplate(
        id: orgTemplateChoiceId(row.remoteId),
        label: row.name,
      ),
      description: row.description,
      versionLine: row.published
          ? 'Shared with the clinic'
          : 'Draft · only you',
      metaLine: creator == null
          ? sections
          : '$sections · Created by $creator',
      isPublished: row.published,
      editDraftLabel: !row.published,
      draftOnly: !row.published,
      createdBy: row.createdBy,
      remoteId: row.remoteId,
      fieldsJson: row.fieldsJson,
    );
  }

  List<_LibraryEntry> _visibleFor(List<Template> org, String? viewerUid) {
    final q = _query.trim().toLowerCase();
    return _tabBase(org, viewerUid).where((e) {
      final tabOk = switch (_tab) {
        _LibraryTab.all => true,
        _LibraryTab.published => e.isPublished,
        _LibraryTab.drafts => !e.isPublished,
        _LibraryTab.team => true,
      };
      if (!tabOk) return false;
      if (q.isEmpty) return true;
      return e.template.label.toLowerCase().contains(q) ||
          e.description.toLowerCase().contains(q) ||
          e.metaLine.toLowerCase().contains(q);
    }).toList();
  }

  void _stubAction(String label) {
    showPelviSnackBar(context, '$label — not available yet');
  }

  void _openBuilder({
    required String name,
    String description = '',
    bool seedPostnatal = true,
    String? remoteId,
    String? fieldsJson,
    bool published = false,
  }) {
    final open = widget.onOpenBuilder;
    if (open == null) {
      _stubAction('Open builder');
      return;
    }
    open(
      name: name,
      description: description,
      seedPostnatal: seedPostnatal,
      remoteId: remoteId,
      fieldsJson: fieldsJson,
      published: published,
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = AppDatabaseProvider.maybeOf(context);
    if (db == null) return _page(const [], null);
    // New stream instances make StreamBuilder resubscribe every rebuild.
    _orgStream ??= db.watchOrgTemplates();
    _uidStream ??= db.watchSetting(AppDatabase.syncBoundUidKey);
    return StreamBuilder<List<Template>>(
      stream: _orgStream,
      builder: (context, orgSnap) {
        return StreamBuilder<String?>(
          stream: _uidStream,
          builder: (context, uidSnap) {
            return _page(orgSnap.data ?? const [], uidSnap.data);
          },
        );
      },
    );
  }

  Widget _page(List<Template> org, String? boundUid) {
    final viewerUid = _viewerUid(boundUid);
    final own = _ownFor(org, viewerUid);
    final team = _teamFor(org, viewerUid);
    final visible = _visibleFor(org, viewerUid);
    final c = PelviColors.of(context);
    return ColoredBox(
      color: c.canvas,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sideBySide = constraints.maxWidth >= 980 && _showNewPanel;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Heading(
                  onNewTemplate: () => setState(() => _showNewPanel = true),
                ),
                const SizedBox(height: 26),
                _SearchRow(onQuery: (v) => setState(() => _query = v)),
                const SizedBox(height: 26),
                _ViewTabs(
                  tab: _tab,
                  allCount: own.length,
                  publishedCount: own.where((e) => e.isPublished).length,
                  draftCount: own.where((e) => !e.isPublished).length,
                  teamCount: team.length,
                  onSelect: (t) => setState(() => _tab = t),
                ),
                const SizedBox(height: 26),
                if (sideBySide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildList(c, visible, viewerUid)),
                      const SizedBox(width: 24),
                      SizedBox(
                        width: 378,
                        child: _NewTemplatePanel(
                          nameCtrl: _nameCtrl,
                          descCtrl: _descCtrl,
                          startFromId: _startFromId,
                          onStartFrom: (id) =>
                              setState(() => _startFromId = id),
                          onClose: () => setState(() => _showNewPanel = false),
                          onCreateDraft: _createDraft,
                          onNameChanged: () => setState(() {}),
                        ),
                      ),
                    ],
                  )
                else ...[
                  _buildList(c, visible, viewerUid),
                  if (_showNewPanel) ...[
                    const SizedBox(height: 24),
                    _NewTemplatePanel(
                      nameCtrl: _nameCtrl,
                      descCtrl: _descCtrl,
                      startFromId: _startFromId,
                      onStartFrom: (id) => setState(() => _startFromId = id),
                      onClose: () => setState(() => _showNewPanel = false),
                      onCreateDraft: _createDraft,
                      onNameChanged: () => setState(() {}),
                    ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildList(
    PelviPalette c,
    List<_LibraryEntry> items,
    String? viewerUid,
  ) {
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Text(
          'No templates match.',
          style: TextStyle(fontSize: 13, color: c.inkMuted),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          _TemplateCard(
            entry: items[i],
            selected: items[i].template.id == _selectedId,
            canEdit: _canEdit(items[i], viewerUid),
            onSelect: () => setState(() => _selectedId = items[i].template.id),
            onDuplicate: () => _stubAction('Duplicate'),
            onAdd: () => _addCopy(items[i], viewerUid),
            onEdit: () {
              final e = items[i];
              if (!_canEdit(e, viewerUid)) return;
              _openBuilder(
                name: e.template.label,
                description: e.description,
                seedPostnatal:
                    e.remoteId == null && e.template.id == 'postnatal_check',
                remoteId: e.remoteId,
                fieldsJson: e.fieldsJson,
                published: e.isPublished && !e.draftOnly,
              );
            },
          ),
        ],
      ],
    );
  }

  Future<void> _addCopy(_LibraryEntry entry, String? viewerUid) async {
    final db = AppDatabaseProvider.maybeOf(context);
    if (db == null) return;
    final uid = viewerUid?.trim() ?? '';
    if (uid.isEmpty) {
      _stubAction('Add template');
      return;
    }
    final liveName = NotesAuth.currentUser?.displayName?.trim() ?? '';
    try {
      await db.saveOrgTemplate(
        name: entry.template.label,
        description: entry.description,
        fieldsJson: entry.fieldsJson ?? '[]',
        createdBy: uid,
        createdByName: liveName,
        published: false,
      );
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Added to your templates.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Could not add template: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _createDraft() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    _openBuilder(
      name: name,
      description: _descCtrl.text.trim(),
      seedPostnatal: _startFromId == 'postnatal_check',
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.onNewTemplate});

  final VoidCallback onNewTemplate;

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
              const DesktopBreadcrumb(),
              Text(
                'SOAP templates',
                style: TextStyle(
                  fontSize: 29,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        FilledButton.icon(
          onPressed: onNewTemplate,
          icon: const Icon(Icons.add, size: 16),
          label: const Text(
            'New template',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: c.pink700,
            foregroundColor: c.inkInverse,
            minimumSize: const Size(0, 38),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PelviRadius.sm),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.onQuery});

  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return SizedBox(
      height: 44,
      child: TextField(
        onChanged: onQuery,
        style: TextStyle(fontSize: 13, color: c.ink),
        decoration: InputDecoration(
          hintText: 'Search templates by name or description',
          hintStyle: TextStyle(fontSize: 13, color: c.inkMuted),
          prefixIcon: Icon(Icons.search, size: 18, color: c.inkMuted),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 40,
            minHeight: 44,
          ),
          filled: true,
          fillColor: c.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(PelviRadius.sm),
            borderSide: BorderSide(color: c.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(PelviRadius.sm),
            borderSide: BorderSide(color: c.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(PelviRadius.sm),
            borderSide: BorderSide(color: c.pink700),
          ),
        ),
      ),
    );
  }
}

class _ViewTabs extends StatelessWidget {
  const _ViewTabs({
    required this.tab,
    required this.allCount,
    required this.publishedCount,
    required this.draftCount,
    required this.teamCount,
    required this.onSelect,
  });

  final _LibraryTab tab;
  final int allCount;
  final int publishedCount;
  final int draftCount;
  final int teamCount;
  final ValueChanged<_LibraryTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    Widget tabItem(_LibraryTab value, String label) {
      final selected = tab == value;
      return InkWell(
        onTap: () => onSelect(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? c.pink700 : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? c.pink700 : c.inkMuted,
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          tabItem(_LibraryTab.all, 'All ($allCount)'),
          const SizedBox(width: 26),
          tabItem(_LibraryTab.published, 'Published ($publishedCount)'),
          const SizedBox(width: 26),
          tabItem(_LibraryTab.drafts, 'Drafts ($draftCount)'),
          const SizedBox(width: 26),
          tabItem(
            _LibraryTab.team,
            "Your team's templates ($teamCount)",
          ),
        ],
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.entry,
    required this.selected,
    required this.canEdit,
    required this.onSelect,
    required this.onDuplicate,
    required this.onAdd,
    required this.onEdit,
  });

  final _LibraryEntry entry;
  final bool selected;
  final bool canEdit;
  final VoidCallback onSelect;
  final VoidCallback onDuplicate;
  final VoidCallback onAdd;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final glyphBg = selected ? c.pink50 : c.purple50;
    final glyphColor = selected ? c.pink700 : c.purple700;

    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? c.pink700 : c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: glyphBg,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      Icons.description_outlined,
                      size: 21,
                      color: glyphColor,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.template.label,
                          style: TextStyle(
                            fontSize: 17,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                            color: c.ink,
                          ),
                        ),
                        Text(
                          entry.versionLine,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.5,
                            color: c.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusChip(
                    label: entry.statusLabel,
                    published: entry.isPublished && !entry.draftOnly,
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Text(
                entry.description.trim().isEmpty
                    ? 'Shared with the clinic.'
                    : entry.description,
                style: TextStyle(fontSize: 12, height: 1.5, color: c.inkMuted),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.metaLine,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: c.inkMuted,
                      ),
                    ),
                  ),
                  if (canEdit) ...[
                    TextButton(
                      onPressed: onDuplicate,
                      style: TextButton.styleFrom(
                        foregroundColor: c.pink700,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Duplicate',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (entry.editDraftLabel)
                      FilledButton.icon(
                        onPressed: onEdit,
                        icon: Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: c.pink700,
                        ),
                        label: Text(
                          'Edit draft',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: c.pink700,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: c.pink50,
                          foregroundColor: c.pink700,
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(PelviRadius.sm),
                          ),
                        ),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: onEdit,
                        icon: Icon(Icons.edit_outlined, size: 16, color: c.ink),
                        label: Text(
                          'Edit',
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
                  ] else
                    FilledButton.icon(
                      onPressed: onAdd,
                      icon: Icon(Icons.add, size: 16, color: c.inkInverse),
                      label: const Text(
                        'Add',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: c.pink700,
                        foregroundColor: c.inkInverse,
                        minimumSize: const Size(0, 38),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(PelviRadius.sm),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.published});

  final String label;
  final bool published;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: published ? c.pink50 : c.purple50,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          height: 1.5,
          fontWeight: FontWeight.w500,
          color: published ? c.pink700 : c.purple700,
        ),
      ),
    );
  }
}

class _NewTemplatePanel extends StatelessWidget {
  const _NewTemplatePanel({
    required this.nameCtrl,
    required this.descCtrl,
    required this.startFromId,
    required this.onStartFrom,
    required this.onClose,
    required this.onCreateDraft,
    required this.onNameChanged,
  });

  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final String startFromId;
  final ValueChanged<String> onStartFrom;
  final VoidCallback onClose;
  final VoidCallback onCreateDraft;
  final VoidCallback onNameChanged;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final canCreate = nameCtrl.text.trim().isNotEmpty;
    final startLabel = soapTemplateById(startFromId).label;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'New template',
                  style: TextStyle(
                    fontSize: 17,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
              ),
              InkWell(
                onTap: onClose,
                child: Text(
                  '×',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: c.pink700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: c.purple50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Create a new draft',
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                fontWeight: FontWeight.w500,
                color: c.purple700,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Start with the SOAP structure, then shape your prompts in the template builder.',
            style: TextStyle(fontSize: 12, height: 1.5, color: c.inkMuted),
          ),
          const SizedBox(height: 18),
          Divider(height: 1, color: c.border),
          const SizedBox(height: 18),
          Text(
            'Template name *',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 7),
          TextField(
            controller: nameCtrl,
            onChanged: (_) => onNameChanged(),
            style: TextStyle(fontSize: 13, color: c.ink),
            decoration: InputDecoration(
              hintText: 'Enter a template name…',
              hintStyle: TextStyle(fontSize: 13, color: c.inkMuted),
              filled: true,
              fillColor: c.surface,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(PelviRadius.sm),
                borderSide: BorderSide(color: c.pink700),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(PelviRadius.sm),
                borderSide: BorderSide(color: c.pink700),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(PelviRadius.sm),
                borderSide: BorderSide(color: c.pink700, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Description',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 7),
          TextField(
            controller: descCtrl,
            minLines: 2,
            maxLines: 3,
            style: TextStyle(fontSize: 13, color: c.ink),
            decoration: InputDecoration(
              hintText: 'Enter a short description…',
              hintStyle: TextStyle(fontSize: 13, color: c.inkMuted),
              filled: true,
              fillColor: c.surface,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(PelviRadius.sm),
                borderSide: BorderSide(color: c.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(PelviRadius.sm),
                borderSide: BorderSide(color: c.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(PelviRadius.sm),
                borderSide: BorderSide(color: c.pink700),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Start from',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 7),
          PopupMenuButton<String>(
            onSelected: onStartFrom,
            itemBuilder: (context) => [
              for (final t in soapTemplates)
                PopupMenuItem(value: t.id, child: Text(t.label)),
            ],
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(PelviRadius.sm),
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      startLabel,
                      style: TextStyle(fontSize: 13, color: c.ink),
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_down, size: 18, color: c.inkMuted),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.canvas,
              borderRadius: BorderRadius.circular(PelviRadius.sm),
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'INCLUDED SECTIONS',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: c.inkMuted,
                  ),
                ),
                const SizedBox(height: 10),
                for (final section in const [
                  'Subjective',
                  'Objective',
                  'Assessment',
                  'Plan',
                ]) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.format_align_left,
                        size: 14,
                        color: c.inkMuted,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        section,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: c.ink,
                        ),
                      ),
                    ],
                  ),
                  if (section != 'Plan') const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Give your template a name to create a draft. Shape each SOAP section in the builder, then publish when teammates should see it.',
            style: TextStyle(fontSize: 11, height: 1.5, color: c.inkMuted),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: canCreate ? onCreateDraft : null,
            icon: Icon(
              Icons.add,
              size: 16,
              color: canCreate ? c.inkInverse : c.inkMuted,
            ),
            label: Text(
              'Create draft',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: canCreate ? c.inkInverse : c.inkMuted,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: canCreate ? c.pink700 : c.surfaceMuted,
              disabledBackgroundColor: c.surfaceMuted,
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(PelviRadius.sm),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Library row: real [SoapTemplate] + Figma presentation stubs.
class _LibraryEntry {
  const _LibraryEntry({
    required this.template,
    required this.description,
    required this.versionLine,
    required this.metaLine,
    required this.isPublished,
    required this.editDraftLabel,
    this.draftOnly = false,
    this.createdBy,
    this.remoteId,
    this.fieldsJson,
  });

  final SoapTemplate template;
  final String description;
  final String versionLine;
  final String metaLine;
  final bool isPublished;
  final bool editDraftLabel;
  final bool draftOnly;
  final String? createdBy;
  final String? remoteId;
  final String? fieldsJson;

  String get statusLabel => draftOnly ? 'Draft' : 'Published';
}

/// shortcut: version/publish/field counts are Figma stubs, upgrade when template model persists them
final _builtinEntries = <_LibraryEntry>[
  _LibraryEntry(
    template: soapTemplateBlank,
    description: 'Four open SOAP sections for free-form documentation.',
    versionLine: 'Version 1',
    metaLine: '4 SOAP sections · 4 fields',
    isPublished: true,
    editDraftLabel: false,
  ),
  _LibraryEntry(
    template: soapTemplatePostnatal,
    description: 'Guided prompts for a postnatal review.',
    versionLine: 'Version 1 · Version 2 draft',
    metaLine: '4 SOAP sections · 8 fields',
    isPublished: true,
    editDraftLabel: true,
  ),
  _LibraryEntry(
    template: soapTemplatePelvicFloor,
    description: 'Structured prompts for a pelvic floor review.',
    versionLine: 'Version 1',
    metaLine: '4 SOAP sections · 8 fields',
    isPublished: true,
    editDraftLabel: false,
  ),
  _LibraryEntry(
    template: soapTemplateDram,
    description: 'A draft structure for a focused review.',
    versionLine: 'Version 1 draft',
    metaLine: '4 SOAP sections · 6 fields',
    isPublished: false,
    editDraftLabel: false,
    draftOnly: true,
  ),
];
