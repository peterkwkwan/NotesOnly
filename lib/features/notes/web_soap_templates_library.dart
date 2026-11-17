import 'package:flutter/material.dart';

import '../../data/auth.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/show_snack.dart';
import '../shell/desktop_chrome.dart';
import '../templates/template_body.dart';
import 'note_format.dart';
import 'soap_dictation.dart';
import 'soap_templates.dart';

/// Opens the template builder from the library (Edit / Create draft).
typedef OpenTemplateBuilder =
    void Function({
      required String name,
      String description,
      bool seedPostnatal,
      String? remoteId,
      String? fieldsJson,
      bool published,
      bool hasPendingDraft,
    });

/// Desktop SOAP template library (Figma `NotesOnly · SOAP template library`).
///
/// Built-in starters ship in the list until deleted. Saved templates are org records.
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
  Stream<List<Template>>? _orgStream;
  Stream<String?>? _uidStream;
  Stream<Set<String>>? _hiddenBuiltinsStream;
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

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

  List<_LibraryEntry> _entriesFor(
    List<Template> org,
    Set<String> hiddenBuiltins,
  ) => [
    for (final e in _builtinEntries)
      if (!hiddenBuiltins.contains(e.template.id)) e,
    for (final row in org) _orgEntry(row),
  ];

  List<_LibraryEntry> _ownFor(
    List<Template> org,
    String? viewerUid,
    Set<String> hiddenBuiltins,
  ) => [
    for (final entry in _entriesFor(org, hiddenBuiltins))
      if (_inOwnLibrary(entry, viewerUid)) entry,
  ];

  List<_LibraryEntry> _teamFor(
    List<Template> org,
    String? viewerUid,
    Set<String> hiddenBuiltins,
  ) => [
    for (final entry in _entriesFor(org, hiddenBuiltins))
      if (_inTeamLibrary(entry, viewerUid)) entry,
  ];

  List<_LibraryEntry> _tabBase(
    List<Template> org,
    String? viewerUid,
    Set<String> hiddenBuiltins,
  ) {
    if (_tab == _LibraryTab.team) {
      return _teamFor(org, viewerUid, hiddenBuiltins);
    }
    return _ownFor(org, viewerUid, hiddenBuiltins);
  }

  _LibraryEntry _orgEntry(Template row) {
    final pending = templateHasPendingDraft(row);
    final working = templateWorkingCopy(row);
    return _LibraryEntry(
      template: SoapTemplate(
        id: orgTemplateChoiceId(row.remoteId),
        label: row.name,
      ),
      description: row.description,
      updatedAt: row.updatedAt,
      isPublished: row.published,
      draftOnly: !row.published,
      hasPendingDraft: pending,
      createdBy: row.createdBy,
      remoteId: row.remoteId,
      fieldsJson: working.fieldsJson,
      workingName: working.name,
      workingDescription: working.description,
    );
  }

  List<_LibraryEntry> _visibleFor(
    List<Template> org,
    String? viewerUid,
    Set<String> hiddenBuiltins,
  ) {
    final q = _query.trim().toLowerCase();
    return _tabBase(org, viewerUid, hiddenBuiltins).where((e) {
      final tabOk = switch (_tab) {
        _LibraryTab.all => true,
        _LibraryTab.published => e.isPublished,
        _LibraryTab.drafts => !e.isPublished,
        _LibraryTab.team => true,
      };
      if (!tabOk) return false;
      if (q.isEmpty) return true;
      return e.template.label.toLowerCase().contains(q) ||
          e.description.toLowerCase().contains(q);
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
    bool hasPendingDraft = false,
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
      hasPendingDraft: hasPendingDraft,
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = AppDatabaseProvider.maybeOf(context);
    if (db == null) return _page(const [], null, const {});
    // New stream instances make StreamBuilder resubscribe every rebuild.
    _orgStream ??= db.watchOrgTemplates();
    _uidStream ??= db.watchSetting(AppDatabase.syncBoundUidKey);
    _hiddenBuiltinsStream ??= db.watchHiddenBuiltinTemplateIds();
    return StreamBuilder<List<Template>>(
      stream: _orgStream,
      builder: (context, orgSnap) {
        return StreamBuilder<String?>(
          stream: _uidStream,
          builder: (context, uidSnap) {
            return StreamBuilder<Set<String>>(
              stream: _hiddenBuiltinsStream,
              builder: (context, hiddenSnap) {
                return _page(
                  orgSnap.data ?? const [],
                  uidSnap.data,
                  hiddenSnap.data ?? const {},
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _page(
    List<Template> org,
    String? boundUid,
    Set<String> hiddenBuiltins,
  ) {
    final viewerUid = _viewerUid(boundUid);
    final own = _ownFor(org, viewerUid, hiddenBuiltins);
    final team = _teamFor(org, viewerUid, hiddenBuiltins);
    final visible = _visibleFor(org, viewerUid, hiddenBuiltins);
    final c = PelviColors.of(context);
    return ColoredBox(
      color: c.canvas,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Heading(onNewTemplate: _openNewTemplateDialog),
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
            _buildList(c, visible, viewerUid),
          ],
        ),
      ),
    );
  }

  Future<void> _openNewTemplateDialog() async {
    final c = PelviColors.of(context);
    await showDialog<void>(
      context: context,
      barrierColor: c.overlay,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: SingleChildScrollView(
                  child: _NewTemplatePanel(
                    nameCtrl: _nameCtrl,
                    descCtrl: _descCtrl,
                    onClose: () => Navigator.of(ctx).pop(),
                    onCreateDraft: () {
                      final name = _nameCtrl.text.trim();
                      if (name.isEmpty) return;
                      final description = _descCtrl.text.trim();
                      Navigator.of(ctx).pop();
                      _openBuilder(
                        name: name,
                        description: description,
                        seedPostnatal: false,
                      );
                    },
                    onNameChanged: () => setDialogState(() {}),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    _nameCtrl.clear();
    _descCtrl.clear();
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
            onDelete: !_canEdit(items[i], viewerUid)
                ? null
                : () => _confirmDelete(items[i], viewerUid),
            onRename: items[i].remoteId == null || !_canEdit(items[i], viewerUid)
                ? null
                : (name) => _rename(items[i], name, viewerUid),
            onAdd: () => _addCopy(items[i], viewerUid),
            onEdit: () {
              final e = items[i];
              if (!_canEdit(e, viewerUid)) return;
              _openBuilder(
                name: e.workingName ?? e.template.label,
                description: e.workingDescription ?? e.description,
                seedPostnatal:
                    e.remoteId == null && e.template.id == 'postnatal_check',
                remoteId: e.remoteId,
                fieldsJson: e.fieldsJson,
                published: e.isPublished,
                hasPendingDraft: e.hasPendingDraft,
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
        fieldsJson: entry.fieldsJson ?? _fieldsJsonForBuiltin(entry.template),
        createdBy: uid,
        createdByName: liveName,
        published: true,
      );
      if (!mounted) return;
      showPelviSnackBar(context, 'Added to your templates.');
    } catch (e) {
      if (!mounted) return;
      showPelviSnackBar(context, 'Could not add template: $e');
    }
  }

  Future<void> _rename(
    _LibraryEntry entry,
    String name,
    String? viewerUid,
  ) async {
    final remoteId = entry.remoteId;
    if (remoteId == null || remoteId.isEmpty) return;
    if (!_canEdit(entry, viewerUid)) return;
    final trimmed = name.trim().isEmpty ? 'Untitled template' : name.trim();
    if (trimmed == entry.template.label) return;
    final db = AppDatabaseProvider.maybeOf(context);
    if (db == null) return;
    final uid = viewerUid?.trim() ?? '';
    if (uid.isEmpty) {
      _stubAction('Rename');
      return;
    }
    try {
      await db.renameOrgTemplate(
        remoteId: remoteId,
        name: trimmed,
        renamedBy: uid,
      );
    } catch (e) {
      if (!mounted) return;
      showPelviSnackBar(context, 'Could not rename: $e');
    }
  }

  Future<void> _confirmDelete(
    _LibraryEntry entry,
    String? viewerUid,
  ) async {
    if (!_canEdit(entry, viewerUid)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this template?'),
        content: Text('Delete “${entry.template.label}”? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: PelviColors.of(context).danger,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final db = AppDatabaseProvider.maybeOf(context);
    if (db == null) return;
    final uid = viewerUid?.trim() ?? '';
    if (uid.isEmpty) {
      _stubAction('Delete');
      return;
    }
    final remoteId = entry.remoteId;
    try {
      if (remoteId == null || remoteId.isEmpty) {
        await db.hideBuiltinTemplate(entry.template.id);
      } else {
        await db.deleteOrgTemplate(remoteId: remoteId, deletedBy: uid);
      }
      if (!mounted) return;
      showPelviSnackBar(context, 'Template deleted.');
    } catch (e) {
      if (!mounted) return;
      showPelviSnackBar(context, 'Could not delete: $e');
    }
  }

}

String _fieldsJsonForBuiltin(SoapTemplate template) {
  if (template.fields.isNotEmpty) {
    return encodeTemplateFields(template.fields);
  }
  return encodeTemplateFields(
    fieldsFromSectionBodies({
      SoapSection.subjective: template.subjective,
      SoapSection.objective: template.objective,
      SoapSection.assessment: template.assessment,
      SoapSection.plan: template.plan,
    }),
  );
}

class _Heading extends StatelessWidget {
  const _Heading({required this.onNewTemplate});

  final VoidCallback onNewTemplate;

  @override
  Widget build(BuildContext context) {
    return DesktopPageHeader(
      title: 'SOAP templates',
      actions: [
        DesktopFilledAction(
          icon: Icons.add,
          label: 'New template',
          onPressed: onNewTemplate,
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

class _TemplateCard extends StatefulWidget {
  const _TemplateCard({
    required this.entry,
    required this.selected,
    required this.canEdit,
    required this.onSelect,
    required this.onAdd,
    required this.onEdit,
    this.onDelete,
    this.onRename,
  });

  final _LibraryEntry entry;
  final bool selected;
  final bool canEdit;
  final VoidCallback onSelect;
  final VoidCallback? onDelete;
  final ValueChanged<String>? onRename;
  final VoidCallback onAdd;
  final VoidCallback onEdit;

  @override
  State<_TemplateCard> createState() => _TemplateCardState();
}

class _TemplateCardState extends State<_TemplateCard> {
  bool _renaming = false;
  late final TextEditingController _renameCtrl;
  late final FocusNode _renameFocus;
  bool _committing = false;

  @override
  void initState() {
    super.initState();
    _renameCtrl = TextEditingController(text: widget.entry.template.label);
    _renameFocus = FocusNode()..addListener(_onRenameFocus);
  }

  @override
  void didUpdateWidget(covariant _TemplateCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_renaming &&
        oldWidget.entry.template.label != widget.entry.template.label) {
      _renameCtrl.text = widget.entry.template.label;
    }
  }

  @override
  void dispose() {
    _renameFocus.removeListener(_onRenameFocus);
    _renameFocus.dispose();
    _renameCtrl.dispose();
    super.dispose();
  }

  void _onRenameFocus() {
    if (!_renameFocus.hasFocus && _renaming) {
      _commitRename();
    }
  }

  void _startRename() {
    _renameCtrl.text = widget.entry.template.label;
    _renameCtrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _renameCtrl.text.length,
    );
    setState(() => _renaming = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _renameFocus.requestFocus();
    });
  }

  void _commitRename() {
    if (_committing || !_renaming) return;
    _committing = true;
    final next = _renameCtrl.text;
    setState(() => _renaming = false);
    widget.onRename?.call(next);
    _committing = false;
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final selected = widget.selected;
    final canEdit = widget.canEdit;
    final c = PelviColors.of(context);
    final glyphBg = selected ? c.pink50 : c.purple50;
    final glyphColor = selected ? c.pink700 : c.purple700;
    final titleStyle = TextStyle(
      fontSize: 17,
      height: 1.5,
      fontWeight: FontWeight.w500,
      color: c.ink,
    );

    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _renaming ? null : widget.onSelect,
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
                        if (_renaming)
                          TextField(
                            controller: _renameCtrl,
                            focusNode: _renameFocus,
                            style: titleStyle,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _commitRename(),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(color: c.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(color: c.pink700),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(color: c.pink700),
                              ),
                            ),
                          )
                        else
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  entry.template.label,
                                  style: titleStyle,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (widget.onRename != null)
                                IconButton(
                                  key: ValueKey(
                                    'rename-${entry.template.id}',
                                  ),
                                  onPressed: _startRename,
                                  tooltip: 'Rename',
                                  icon: Icon(
                                    Icons.edit_outlined,
                                    size: 16,
                                    color: c.inkMuted,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(
                                    minWidth: 28,
                                    minHeight: 28,
                                  ),
                                ),
                            ],
                          ),
                        if (entry.updatedAt != null)
                          Text(
                            'Last updated: ${formatNoteDate(entry.updatedAt!.toLocal())}',
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
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (canEdit) ...[
                    if (widget.onDelete != null) ...[
                      TextButton(
                        onPressed: widget.onDelete,
                        style: TextButton.styleFrom(
                          foregroundColor: c.danger,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Delete',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    OutlinedButton.icon(
                      onPressed: widget.onEdit,
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
                      onPressed: widget.onAdd,
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
    required this.onClose,
    required this.onCreateDraft,
    required this.onNameChanged,
  });

  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final VoidCallback onClose;
  final VoidCallback onCreateDraft;
  final VoidCallback onNameChanged;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final canCreate = nameCtrl.text.trim().isNotEmpty;

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
    required this.isPublished,
    this.updatedAt,
    this.draftOnly = false,
    this.hasPendingDraft = false,
    this.createdBy,
    this.remoteId,
    this.fieldsJson,
    this.workingName,
    this.workingDescription,
  });

  final SoapTemplate template;
  final String description;
  final DateTime? updatedAt;
  final bool isPublished;
  final bool draftOnly;
  final bool hasPendingDraft;
  final String? createdBy;
  final String? remoteId;
  final String? fieldsJson;
  final String? workingName;
  final String? workingDescription;

  String get statusLabel => draftOnly ? 'Draft' : 'Published';
}

final _builtinEntries = <_LibraryEntry>[
  _LibraryEntry(
    template: soapTemplateBlank,
    description: 'Four open SOAP sections for free-form documentation.',
    isPublished: true,
  ),
  _LibraryEntry(
    template: soapTemplatePostnatal,
    description: 'Guided prompts for a postnatal review.',
    isPublished: true,
  ),
  _LibraryEntry(
    template: soapTemplatePelvicFloor,
    description: 'Structured prompts for a pelvic floor review.',
    isPublished: true,
  ),
  _LibraryEntry(
    template: soapTemplateDram,
    description: 'A draft structure for a focused review.',
    isPublished: !draftBuiltinTemplateIds.contains(soapTemplateDram.id),
    draftOnly: draftBuiltinTemplateIds.contains(soapTemplateDram.id),
  ),
];
