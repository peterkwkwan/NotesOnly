import 'package:flutter/material.dart';

import '../../data/auth.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/theme.dart';
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

enum _LibraryTab { all, published, drafts }

class _WebSoapTemplatesLibraryState extends State<WebSoapTemplatesLibrary> {
  _LibraryTab _tab = _LibraryTab.all;
  String _query = '';
  String? _selectedId = 'postnatal_check';
  bool _showNewPanel = true;
  bool _mineOnly = false;
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

  List<_LibraryEntry> _entriesFor(List<Template> org, String? viewerUid) => [
    ..._builtinEntries,
    for (final row in org) _orgEntry(row, viewerUid),
  ];

  List<_LibraryEntry> _scopedFor(List<Template> org, String? viewerUid) {
    final entries = _entriesFor(org, viewerUid);
    if (!_mineOnly) return entries;
    return [
      for (final entry in entries)
        if (templateMatchesMine(
          createdBy: entry.createdBy,
          viewerUid: viewerUid,
        ))
          entry,
    ];
  }

  _LibraryEntry _orgEntry(Template row, String? viewerUid) {
    final creator = templateCreatorLabel(
      createdByName: row.createdByName,
      createdBy: row.createdBy,
      viewerUid: viewerUid,
      viewerName: NotesAuth.currentUser?.displayName,
    );
    final count = decodeTemplateFields(row.fieldsJson).length;
    final questions = count == 1 ? '1 question' : '$count questions';
    return _LibraryEntry(
      template: SoapTemplate(
        id: orgTemplateChoiceId(row.remoteId),
        label: row.name,
      ),
      description: row.description,
      versionLine: 'Shared with the clinic',
      metaLine: creator == null
          ? questions
          : '$questions · Created by $creator',
      isPublished: true,
      inDraftsTab: false,
      editDraftLabel: false,
      createdBy: row.createdBy,
      remoteId: row.remoteId,
      fieldsJson: row.fieldsJson,
    );
  }

  List<_LibraryEntry> _visibleFor(List<Template> org, String? viewerUid) {
    final q = _query.trim().toLowerCase();
    return _scopedFor(org, viewerUid).where((e) {
      final tabOk = switch (_tab) {
        _LibraryTab.all => true,
        _LibraryTab.published => e.isPublished,
        _LibraryTab.drafts => e.inDraftsTab,
      };
      if (!tabOk) return false;
      if (q.isEmpty) return true;
      return e.template.label.toLowerCase().contains(q) ||
          e.description.toLowerCase().contains(q) ||
          e.metaLine.toLowerCase().contains(q);
    }).toList();
  }

  void _stubAction(String label) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('$label — not available yet'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openBuilder({
    required String name,
    String description = '',
    bool seedPostnatal = true,
    String? remoteId,
    String? fieldsJson,
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
    final scoped = _scopedFor(org, viewerUid);
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
                _SearchRow(
                  mine: _mineOnly,
                  onQuery: (v) => setState(() => _query = v),
                  onToggleMine: () => setState(() => _mineOnly = !_mineOnly),
                ),
                const SizedBox(height: 26),
                _ViewTabs(
                  tab: _tab,
                  allCount: scoped.length,
                  publishedCount: scoped.where((e) => e.isPublished).length,
                  draftCount: scoped.where((e) => e.inDraftsTab).length,
                  onSelect: (t) => setState(() => _tab = t),
                ),
                const SizedBox(height: 26),
                if (sideBySide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildList(c, visible)),
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
                  _buildList(c, visible),
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

  Widget _buildList(PelviPalette c, List<_LibraryEntry> items) {
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
            onSelect: () => setState(() => _selectedId = items[i].template.id),
            onDuplicate: () => _stubAction('Duplicate'),
            onEdit: () {
              final e = items[i];
              _openBuilder(
                name: e.template.label,
                description: e.description,
                seedPostnatal:
                    e.remoteId == null && e.template.id == 'postnatal_check',
                remoteId: e.remoteId,
                fieldsJson: e.fieldsJson,
              );
            },
          ),
        ],
      ],
    );
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
              Text(
                'A familiar structure, shaped around the way you write',
                style: TextStyle(fontSize: 13, height: 1.5, color: c.inkMuted),
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
  const _SearchRow({
    required this.onQuery,
    required this.mine,
    required this.onToggleMine,
  });

  final ValueChanged<String> onQuery;
  final bool mine;
  final VoidCallback onToggleMine;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Row(
      children: [
        Expanded(
          child: SizedBox(
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
          ),
        ),
        const SizedBox(width: 18),
        OutlinedButton(
          onPressed: onToggleMine,
          style: OutlinedButton.styleFrom(
            backgroundColor: mine ? c.pink50 : c.surface,
            foregroundColor: mine ? c.pink700 : c.ink,
            side: BorderSide(color: mine ? c.pink700 : c.border),
            minimumSize: const Size(0, 38),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PelviRadius.sm),
            ),
          ),
          child: Text(
            mine ? 'Mine' : 'Created by',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: mine ? c.pink700 : c.ink,
            ),
          ),
        ),
      ],
    );
  }
}

class _ViewTabs extends StatelessWidget {
  const _ViewTabs({
    required this.tab,
    required this.allCount,
    required this.publishedCount,
    required this.draftCount,
    required this.onSelect,
  });

  final _LibraryTab tab;
  final int allCount;
  final int publishedCount;
  final int draftCount;
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
          tabItem(_LibraryTab.all, 'All templates ($allCount)'),
          const SizedBox(width: 26),
          tabItem(_LibraryTab.published, 'Published ($publishedCount)'),
          const SizedBox(width: 26),
          tabItem(_LibraryTab.drafts, 'Drafts ($draftCount)'),
        ],
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.entry,
    required this.selected,
    required this.onSelect,
    required this.onDuplicate,
    required this.onEdit,
  });

  final _LibraryEntry entry;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onDuplicate;
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
            'Give your template a name to create a draft. Add field types and preview your layout in the builder.',
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
    required this.inDraftsTab,
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
  final bool inDraftsTab;
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
    inDraftsTab: false,
    editDraftLabel: false,
  ),
  _LibraryEntry(
    template: soapTemplatePostnatal,
    description: 'Guided prompts for a postnatal review.',
    versionLine: 'Version 1 · Version 2 draft',
    metaLine: '4 SOAP sections · 8 fields',
    isPublished: true,
    inDraftsTab: true,
    editDraftLabel: true,
  ),
  _LibraryEntry(
    template: soapTemplatePelvicFloor,
    description: 'Structured prompts for a pelvic floor review.',
    versionLine: 'Version 1',
    metaLine: '4 SOAP sections · 8 fields',
    isPublished: true,
    inDraftsTab: false,
    editDraftLabel: false,
  ),
  _LibraryEntry(
    template: soapTemplateDram,
    description: 'A draft structure for a focused review.',
    versionLine: 'Version 1 draft',
    metaLine: '4 SOAP sections · 6 fields',
    isPublished: false,
    inDraftsTab: true,
    editDraftLabel: false,
    draftOnly: true,
  ),
];
