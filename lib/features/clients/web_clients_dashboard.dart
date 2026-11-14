import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/show_snack.dart';
import '../shell/desktop_chrome.dart';
import 'client_form_screen.dart';
import 'client_format.dart';
import 'client_profile_screen.dart';

/// Figma `NotesOnly · Clients` page body (desktop shell supplies chrome).
class WebClientsDashboard extends StatefulWidget {
  const WebClientsDashboard({super.key});

  @override
  State<WebClientsDashboard> createState() => _WebClientsDashboardState();
}

enum _ScopeFilter { all, pinned }
enum _SortMode { nameAz, nameZa }
enum _ViewTab { all, due }

class _WebClientsDashboardState extends State<WebClientsDashboard> {
  String _query = '';
  _ScopeFilter _scope = _ScopeFilter.all;
  _SortMode _sort = _SortMode.nameAz;
  _ViewTab _tab = _ViewTab.all;
  final Set<int> _selected = {};

  void _openNew() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ClientFormScreen()),
    );
  }

  void _openProfile(int clientId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClientProfileScreen(clientId: clientId),
      ),
    );
  }

  void _clearSelection() => setState(() => _selected.clear());

  void _toggleSelected(int id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _setSelectedAll(Iterable<int> ids, bool select) {
    setState(() {
      if (select) {
        _selected
          ..clear()
          ..addAll(ids);
      } else {
        _selected.clear();
      }
    });
  }

  Future<void> _muteSelected(bool muted) async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final db = AppDatabaseProvider.of(context);
    for (final id in ids) {
      await db.setRecallMuted(id, muted);
    }
  }

  Future<void> _exportSelected(List<Client> listed) async {
    final chosen = [
      for (final c in listed)
        if (_selected.contains(c.id)) c,
    ];
    if (chosen.isEmpty) {
      showPelviSnackBar(context, 'Select clients to export');
      return;
    }
    final buf = StringBuffer()
      ..writeln('id,firstName,lastName,phone,email');
    for (final c in chosen) {
      buf.writeln(
        [
          c.id,
          _csv(c.firstName),
          _csv(c.lastName),
          _csv(c.phone ?? ''),
          _csv(c.email ?? ''),
        ].join(','),
      );
    }
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(buf.toString())),
              mimeType: 'text/csv',
              name: 'notesonly-clients-$stamp.csv',
            ),
          ],
          subject: 'NotesOnly clients export',
          text: 'Selected clients (CSV)',
        ),
      );
    } catch (e) {
      if (mounted) showPelviSnackBar(context, 'Export failed: $e');
    }
  }

  static String _csv(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  List<Client> _applyList(
    List<Client> clients, {
    required Set<int> pinnedIds,
    required Set<int> dueIds,
  }) {
    var listed = filterClients(clients, _query);
    if (_scope == _ScopeFilter.pinned) {
      listed = [for (final c in listed) if (pinnedIds.contains(c.id)) c];
    }
    if (_tab == _ViewTab.due) {
      listed = [for (final c in listed) if (dueIds.contains(c.id)) c];
    }
    listed = List<Client>.of(listed);
    listed.sort((a, b) {
      final byLast = a.lastName.toLowerCase().compareTo(b.lastName.toLowerCase());
      final byFirst =
          a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
      final cmp = byLast != 0 ? byLast : byFirst;
      return _sort == _SortMode.nameAz ? cmp : -cmp;
    });
    return listed;
  }

  @override
  Widget build(BuildContext context) {
    final db = AppDatabaseProvider.of(context);
    final c = PelviColors.of(context);

    return ColoredBox(
      color: c.canvas,
      child: StreamBuilder<List<Client>>(
        stream: db.watchClients(),
        builder: (context, clientSnap) {
          return StreamBuilder<List<int>>(
            stream: db.watchPinnedClientIds(),
            builder: (context, pinSnap) {
              return StreamBuilder<List<int>>(
                stream: db.watchRecentClientIds(),
                builder: (context, recentSnap) {
                  return StreamBuilder<List<RecallDueEntry>>(
                    stream: db.watchRecallDueClients(),
                    builder: (context, dueSnap) {
                      return StreamBuilder<Set<int>>(
                        stream: db.watchRecallMutedIds(),
                        builder: (context, muteSnap) {
                          return StreamBuilder<int>(
                            stream: db.watchRecallDays(),
                            builder: (context, daysSnap) {
                              final clients = clientSnap.data ?? const [];
                              final pinnedIds =
                                  (pinSnap.data ?? const []).toSet();
                              final recentIds = recentSnap.data ?? const [];
                              final due = dueSnap.data ?? const [];
                              final dueIds = {for (final e in due) e.client.id};
                              final muted =
                                  muteSnap.data ?? const <int>{};
                              final recallDays = daysSnap.data ?? 14;
                              final listed = _applyList(
                                clients,
                                pinnedIds: pinnedIds,
                                dueIds: dueIds,
                              );
                              final pinnedClients = clientsInIdOrder(
                                clients,
                                pinSnap.data ?? const [],
                              );
                              final recentClients = clientsInIdOrder(
                                clients,
                                recentIds,
                              );
                              final liveIds = {for (final cl in clients) cl.id};
                              final selectedClients = [
                                for (final client in clients)
                                  if (_selected.contains(client.id)) client,
                              ];
                              // Drop stale selection after this frame.
                              if (_selected.any((id) => !liveIds.contains(id))) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (!mounted) return;
                                  setState(
                                    () => _selected.removeWhere(
                                      (id) => !liveIds.contains(id),
                                    ),
                                  );
                                });
                              }

                              return Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _HeadingRow(
                                      onExport: () =>
                                          _exportSelected(listed),
                                      onAdd: _openNew,
                                    ),
                                    const SizedBox(height: 26),
                                    _SearchFiltersRow(
                                      query: _query,
                                      onQuery: (v) =>
                                          setState(() => _query = v),
                                      scope: _scope,
                                      onScope: (v) =>
                                          setState(() => _scope = v),
                                      sort: _sort,
                                      onSort: (v) =>
                                          setState(() => _sort = v),
                                    ),
                                    const SizedBox(height: 26),
                                    _PinnedRecentRow(
                                      pinned: pinnedClients,
                                      recent: recentClients,
                                      onOpen: _openProfile,
                                    ),
                                    const SizedBox(height: 26),
                                    _ViewTabs(
                                      tab: _tab,
                                      dueCount: due.length,
                                      onTab: (v) =>
                                          setState(() => _tab = v),
                                    ),
                                    const SizedBox(height: 26),
                                    Expanded(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            child: _ClientTable(
                                              listed: listed,
                                              pinnedIds: pinnedIds,
                                              mutedIds: muted,
                                              selected: _selected,
                                              onToggle: _toggleSelected,
                                              onOpen: _openProfile,
                                              onSelectAll: (all) =>
                                                  _setSelectedAll(
                                                listed.map((e) => e.id),
                                                all,
                                              ),
                                              onClear: _clearSelection,
                                              selectedClients:
                                                  selectedClients,
                                            ),
                                          ),
                                          const SizedBox(width: 24),
                                          SizedBox(
                                            width: 296,
                                            child: SingleChildScrollView(
                                              child: _RecallSidePanels(
                                                selected: selectedClients,
                                                recallDays: recallDays,
                                                onRemove: (id) => setState(
                                                  () => _selected.remove(id),
                                                ),
                                                onMute: () =>
                                                    _muteSelected(true),
                                                onUnmute: () =>
                                                    _muteSelected(false),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _HeadingRow extends StatelessWidget {
  const _HeadingRow({required this.onExport, required this.onAdd});

  final VoidCallback onExport;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Clients',
                style: TextStyle(
                  fontSize: 29,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              Text(
                'Keep people, contact details and recalls in one place',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: c.inkMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        OutlinedButton.icon(
          onPressed: onExport,
          icon: Icon(Icons.download_outlined, size: 16, color: c.ink),
          label: Text(
            'Export selection',
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
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 16),
          label: const Text(
            'Add client',
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

class _SearchFiltersRow extends StatelessWidget {
  const _SearchFiltersRow({
    required this.query,
    required this.onQuery,
    required this.scope,
    required this.onScope,
    required this.sort,
    required this.onSort,
  });

  final String query;
  final ValueChanged<String> onQuery;
  final _ScopeFilter scope;
  final ValueChanged<_ScopeFilter> onScope;
  final _SortMode sort;
  final ValueChanged<_SortMode> onSort;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 42,
            child: TextField(
              onChanged: onQuery,
              textInputAction: TextInputAction.search,
              style: TextStyle(fontSize: 13, color: c.ink),
              decoration: InputDecoration(
                hintText: 'Search name, phone, or email',
                hintStyle: TextStyle(fontSize: 13, color: c.inkMuted),
                prefixIcon: Icon(Icons.search, size: 18, color: c.inkMuted),
                filled: true,
                fillColor: c.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
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
                  borderSide: BorderSide(color: c.pink700, width: 1.5),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 20),
        _MenuChip(
          icon: Icons.expand_more,
          label: scope == _ScopeFilter.all ? 'All clients' : 'Pinned only',
          items: const [
            PopupMenuItem(value: _ScopeFilter.all, child: Text('All clients')),
            PopupMenuItem(
              value: _ScopeFilter.pinned,
              child: Text('Pinned only'),
            ),
          ],
          onSelected: onScope,
        ),
        const SizedBox(width: 10),
        _MenuChip(
          icon: Icons.sort,
          label: sort == _SortMode.nameAz ? 'Name A–Z' : 'Name Z–A',
          items: const [
            PopupMenuItem(value: _SortMode.nameAz, child: Text('Name A–Z')),
            PopupMenuItem(value: _SortMode.nameZa, child: Text('Name Z–A')),
          ],
          onSelected: onSort,
        ),
      ],
    );
  }
}

class _MenuChip<T> extends StatelessWidget {
  const _MenuChip({
    required this.icon,
    required this.label,
    required this.items,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final List<PopupMenuEntry<T>> items;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return PopupMenuButton<T>(
      onSelected: onSelected,
      itemBuilder: (_) => items,
      offset: const Offset(0, 40),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(PelviRadius.sm),
          border: Border.all(color: c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: c.ink),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinnedRecentRow extends StatelessWidget {
  const _PinnedRecentRow({
    required this.pinned,
    required this.recent,
    required this.onOpen,
  });

  final List<Client> pinned;
  final List<Client> recent;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    if (pinned.isEmpty && recent.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (pinned.isNotEmpty) ...[
            Icon(Icons.push_pin, size: 14, color: c.purple700),
            const SizedBox(width: 12),
            Text(
              'PINNED',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: c.purple700,
              ),
            ),
            const SizedBox(width: 12),
            for (final client in pinned) ...[
              OutlinedButton(
                onPressed: () => onOpen(client.id),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.ink,
                  backgroundColor: c.surface,
                  side: BorderSide(color: c.border),
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(PelviRadius.sm),
                  ),
                ),
                child: Text(
                  clientDisplayName(client),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ],
          if (recent.isNotEmpty) ...[
            if (pinned.isNotEmpty) const SizedBox(width: 4),
            Text(
              'Recently opened:',
              style: TextStyle(fontSize: 11, color: c.inkMuted),
            ),
            const SizedBox(width: 12),
            for (final client in recent.take(6)) ...[
              InkWell(
                onTap: () => onOpen(client.id),
                child: Text(
                  clientDisplayName(client),
                  style: TextStyle(fontSize: 12, color: c.inkMuted),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ],
        ],
      ),
    );
  }
}

class _ViewTabs extends StatelessWidget {
  const _ViewTabs({
    required this.tab,
    required this.dueCount,
    required this.onTab,
  });

  final _ViewTab tab;
  final int dueCount;
  final ValueChanged<_ViewTab> onTab;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          _Tab(
            label: 'All',
            selected: tab == _ViewTab.all,
            onTap: () => onTab(_ViewTab.all),
          ),
          const SizedBox(width: 26),
          _Tab(
            label: dueCount == 0 ? 'Due' : 'Due ($dueCount)',
            selected: tab == _ViewTab.due,
            onTap: () => onTab(_ViewTab.due),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return InkWell(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? c.pink700 : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? c.pink700 : c.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _ClientTable extends StatelessWidget {
  const _ClientTable({
    required this.listed,
    required this.pinnedIds,
    required this.mutedIds,
    required this.selected,
    required this.selectedClients,
    required this.onToggle,
    required this.onOpen,
    required this.onSelectAll,
    required this.onClear,
  });

  final List<Client> listed;
  final Set<int> pinnedIds;
  final Set<int> mutedIds;
  final Set<int> selected;
  final List<Client> selectedClients;
  final ValueChanged<int> onToggle;
  final ValueChanged<int> onOpen;
  final ValueChanged<bool> onSelectAll;
  final VoidCallback onClear;

  static const _rowSelected = Color(0xFFFCF5F8);
  /// Checkbox + trailing gap; whole area toggles select (not open profile).
  static const double _checkColWidth = 48;
  /// Wider than contact so longer names ellipsis later.
  static const double _clientColWidth = 280;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final allSelected =
        listed.isNotEmpty && listed.every((e) => selected.contains(e.id));
    final n = selected.length;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(PelviRadius.button),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          if (n > 0)
            Container(
              height: 56,
              width: double.infinity,
              color: c.pink50,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  SizedBox(
                    width: _checkColWidth,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _CheckBox(checked: true, onTap: onClear),
                    ),
                  ),
                  Text(
                    '$n selected',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: c.pink700,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      selectedClients.map(clientDisplayName).join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: c.pink700),
                    ),
                  ),
                  TextButton(
                    onPressed: onClear,
                    style: TextButton.styleFrom(
                      foregroundColor: c.pink700,
                      minimumSize: Size.zero,
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Clear',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            width: double.infinity,
            color: c.canvas,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Row(
              children: [
                SizedBox(
                  width: _checkColWidth,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _CheckBox(
                      checked: allSelected,
                      onTap: () => onSelectAll(!allSelected),
                    ),
                  ),
                ),
                SizedBox(
                  width: _clientColWidth,
                  child: Text(
                    'CLIENT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: c.inkMuted,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'CONTACT DETAILS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: c.inkMuted,
                    ),
                  ),
                ),
                SizedBox(
                  width: 92,
                  child: Text(
                    'RECALL',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: c.inkMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
          Expanded(
            child: listed.isEmpty
                ? Center(
                    child: Text(
                      'No matches.',
                      style: TextStyle(fontSize: 13, color: c.inkMuted),
                    ),
                  )
                : ListView.builder(
                    itemCount: listed.length,
                    itemBuilder: (context, index) {
                      final client = listed[index];
                      final isSelected = selected.contains(client.id);
                      final phone = client.phone?.trim() ?? '';
                      final email = client.email?.trim() ?? '';
                      final avatar = clientAvatarColors(client, c);
                      return Material(
                        color: isSelected ? _rowSelected : c.surface,
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 81),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: c.border),
                            ),
                          ),
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => onToggle(client.id),
                                    child: SizedBox(
                                      width: 18 + _checkColWidth,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          left: 18,
                                        ),
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: _CheckBox(
                                            checked: isSelected,
                                            onTap: () =>
                                                onToggle(client.id),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: InkWell(
                                    onTap: () => onOpen(client.id),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        0,
                                        14,
                                        18,
                                        14,
                                      ),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: _clientColWidth,
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 36,
                                                  height: 36,
                                                  alignment:
                                                      Alignment.center,
                                                  decoration: BoxDecoration(
                                                    color: avatar.wash,
                                                    borderRadius:
                                                        BorderRadius
                                                            .circular(
                                                      PelviRadius.md,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    clientInitials(client),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: avatar.ink,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        clientDisplayName(
                                                          client,
                                                        ),
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow
                                                                .ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight
                                                                  .w500,
                                                          color: c.ink,
                                                        ),
                                                      ),
                                                      if (pinnedIds
                                                          .contains(
                                                        client.id,
                                                      ))
                                                        Text(
                                                          'Pinned client',
                                                          style:
                                                              TextStyle(
                                                            fontSize: 10,
                                                            color: c
                                                                .purple700,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize:
                                                  MainAxisSize.min,
                                              children: [
                                                Text(
                                                  phone.isEmpty
                                                      ? '—'
                                                      : phone,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: c.ink,
                                                  ),
                                                ),
                                                Text(
                                                  email.isEmpty
                                                      ? '—'
                                                      : email,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: c.inkMuted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(
                                            width: 92,
                                            child: Text(
                                              mutedIds.contains(client.id)
                                                  ? 'Muted'
                                                  : 'Not muted',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: c.inkMuted,
                                              ),
                                            ),
                                          ),
                                          Icon(
                                            Icons.chevron_right,
                                            size: 16,
                                            color: c.inkMuted,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                Text(
                  '${listed.length} client record${listed.length == 1 ? '' : 's'} shown',
                  style: TextStyle(fontSize: 11, color: c.inkMuted),
                ),
                const Spacer(),
                Text(
                  '— Contact not provided',
                  style: TextStyle(fontSize: 11, color: c.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.checked, required this.onTap});

  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 17,
        height: 17,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: checked ? c.pink700 : c.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: checked ? c.pink700 : c.border),
        ),
        child: checked
            ? Icon(Icons.check, size: 12, color: c.inkInverse)
            : null,
      ),
    );
  }
}

class _RecallSidePanels extends StatelessWidget {
  const _RecallSidePanels({
    required this.selected,
    required this.recallDays,
    required this.onRemove,
    required this.onMute,
    required this.onUnmute,
  });

  final List<Client> selected;
  final int recallDays;
  final ValueChanged<int> onRemove;
  final VoidCallback onMute;
  final VoidCallback onUnmute;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final n = selected.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(PelviRadius.button),
            border: Border.all(color: c.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Recall review',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: c.pink50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      n == 0
                          ? 'No clients selected'
                          : '$n client${n == 1 ? '' : 's'} selected',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: c.pink700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Review recall preferences for the selected clients together. Selection does not mean a client is due.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: c.inkMuted,
                  ),
                ),
                const SizedBox(height: 18),
                Divider(height: 1, color: c.border),
                const SizedBox(height: 18),
                Text(
                  'Selected clients',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 12),
                if (selected.isEmpty)
                  Text(
                    'Select clients in the table to review recalls.',
                    style: TextStyle(fontSize: 12, color: c.inkMuted),
                  )
                else
                  for (final client in selected) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            clientDisplayName(client),
                            style: TextStyle(fontSize: 12, color: c.ink),
                          ),
                        ),
                        InkWell(
                          onTap: () => onRemove(client.id),
                          child: Icon(
                            Icons.close,
                            size: 13,
                            color: c.inkMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                if (n > 0) ...[
                  Divider(height: 1, color: c.border),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: onMute,
                    icon: Icon(
                      Icons.notifications_off_outlined,
                      size: 16,
                      color: c.pink700,
                    ),
                    label: Text(
                      'Mute recalls ($n)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.pink700,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: c.pink50,
                      foregroundColor: c.pink700,
                      elevation: 0,
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(PelviRadius.sm),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: onUnmute,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.ink,
                      side: BorderSide(color: c.border),
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(PelviRadius.sm),
                      ),
                    ),
                    child: Text(
                      'Unmute recalls ($n)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Review before applying. No messages are sent by changing recall preferences.',
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.5,
                      color: c.inkMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(PelviRadius.button),
            border: Border.all(color: c.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your recall window',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  recallDays <= 0 ? 'Off' : '$recallDays days',
                  style: TextStyle(
                    fontSize: 26,
                    height: 1.5,
                    color: c.pink700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Clients with no visit in the window appear in Due, unless recalls are muted.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: c.inkMuted,
                  ),
                ),
                const SizedBox(height: 18),
                InkWell(
                  onTap: () => ShellNavigation.maybeOf(context)
                      ?.goTo(DesktopDest.practiceSettings),
                  child: Text(
                    'Manage preferences →',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: c.pink700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
