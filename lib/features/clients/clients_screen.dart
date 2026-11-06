import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/empty_state.dart';
import 'client_form_screen.dart';
import 'client_format.dart';
import 'client_profile_screen.dart';

enum _ClientsFilter { all, due }

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  String _query = '';
  _ClientsFilter _filter = _ClientsFilter.all;
  bool _selecting = false;
  final Set<int> _selected = {};

  void _openNew() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ClientFormScreen(),
      ),
    );
  }

  void _openProfile(int clientId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClientProfileScreen(clientId: clientId),
      ),
    );
  }

  void _exitSelect() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _enterSelect(int id) {
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..add(id);
    });
  }

  void _toggleSelected(int id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  Future<void> _confirmDeleteSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          ids.length == 1
              ? 'Delete client?'
              : 'Delete ${ids.length} clients?',
        ),
        content: const Text(
          'Appointments and SOAP notes for these clients will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: PelviColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final db = AppDatabaseProvider.of(context);
    for (final id in ids) {
      await db.deleteClient(id);
    }
    if (!mounted) return;
    _exitSelect();
  }

  Future<void> _togglePinSelected(Set<int> pinnedIds) async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final allPinned = ids.every(pinnedIds.contains);
    await AppDatabaseProvider.of(context).setClientsPinned(ids, !allPinned);
    if (!mounted) return;
    _exitSelect();
  }

  @override
  Widget build(BuildContext context) {
    final db = AppDatabaseProvider.of(context);
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final n = _selected.length;

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) _exitSelect();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_selecting ? '$n selected' : 'Clients'),
          actions: [
            if (_selecting) ...[
              TextButton(
                onPressed: _exitSelect,
                child: const Text('Cancel'),
              ),
              StreamBuilder<List<int>>(
                stream: db.watchPinnedClientIds(),
                builder: (context, pinSnap) {
                  final pinned = (pinSnap.data ?? const []).toSet();
                  final allPinned =
                      n > 0 && _selected.every(pinned.contains);
                  return TextButton(
                    onPressed: n == 0
                        ? null
                        : () => _togglePinSelected(pinned),
                    style: TextButton.styleFrom(
                      foregroundColor: PelviColors.purple700,
                    ),
                    child: Text(allPinned ? 'Unpin' : 'Pin'),
                  );
                },
              ),
              TextButton(
                onPressed: n == 0 ? null : _confirmDeleteSelected,
                style: TextButton.styleFrom(
                  foregroundColor: PelviColors.danger,
                ),
                child: const Text('Delete'),
              ),
            ] else ...[
              IconButton(
                tooltip: 'Add client',
                onPressed: _openNew,
                style: IconButton.styleFrom(
                  foregroundColor: PelviColors.pink700,
                ),
                icon: const Icon(Icons.person_add_outlined),
              ),
              const SizedBox(width: PelviSpace.sm),
            ],
          ],
        ),
        body: StreamBuilder<List<Client>>(
          stream: db.watchClients(),
          builder: (context, snap) {
            final clients = snap.data;
            if (clients == null) {
              return const Center(
                child: CircularProgressIndicator(color: PelviColors.pink700),
              );
            }
            if (clients.isEmpty) {
              return Column(
                children: [
                  const Expanded(
                    child: QuietEmptyState(
                      title: 'No clients yet',
                      body:
                          'Add your first patient to start booking visits and writing SOAP notes.',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      PelviSpace.md,
                      0,
                      PelviSpace.md,
                      PelviSpace.lg,
                    ),
                    child: DashedEmptyWell(
                      message: 'Your client list will appear here.',
                      ctaLabel: 'Add client',
                      onCta: _openNew,
                    ),
                  ),
                ],
              );
            }

            return StreamBuilder<List<RecallDueEntry>>(
              stream: db.watchRecallDueClients(),
              builder: (context, dueSnap) {
                final due = dueSnap.data ?? const <RecallDueEntry>[];
                final dueById = {for (final e in due) e.client.id: e};
                final searching = _query.trim().isNotEmpty;

                var listed = filterClients(clients, _query);
                final dueMode = _filter == _ClientsFilter.due;
                if (dueMode) {
                  listed = [
                    for (final c in listed)
                      if (dueById.containsKey(c.id)) c,
                  ];
                  // Oldest last-seen first when showing due.
                  listed.sort(
                    (a, b) => dueById[a.id]!
                        .lastSeen
                        .compareTo(dueById[b.id]!.lastSeen),
                  );
                }

                final showStrips =
                    !searching && !dueMode && !_selecting;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        PelviSpace.md,
                        PelviSpace.md,
                        PelviSpace.md,
                        PelviSpace.sm,
                      ),
                      child: TextField(
                        onChanged: (v) => setState(() => _query = v),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search name, phone, or email',
                          prefixIcon: const Icon(
                            Icons.search,
                            color: PelviColors.inkMuted,
                          ),
                          filled: true,
                          fillColor: PelviColors.surfaceMuted,
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(PelviRadius.md),
                            borderSide: const BorderSide(
                              color: PelviColors.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(PelviRadius.md),
                            borderSide: const BorderSide(
                              color: PelviColors.border,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(PelviRadius.md),
                            borderSide: const BorderSide(
                              color: PelviColors.pink700,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        PelviSpace.md,
                        0,
                        PelviSpace.md,
                        PelviSpace.sm,
                      ),
                      child: Row(
                        children: [
                          _FilterChip(
                            label: 'All',
                            selected: _filter == _ClientsFilter.all,
                            onTap: () => setState(
                              () => _filter = _ClientsFilter.all,
                            ),
                          ),
                          const SizedBox(width: PelviSpace.sm),
                          _FilterChip(
                            label: due.isEmpty
                                ? 'Due'
                                : 'Due (${due.length})',
                            selected: dueMode,
                            onTap: () => setState(
                              () => _filter = _ClientsFilter.due,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (showStrips)
                      StreamBuilder<List<int>>(
                        stream: db.watchRecentClientIds(),
                        builder: (context, recentSnap) {
                          final recent = clientsInIdOrder(
                            clients,
                            recentSnap.data ?? const [],
                          );
                          if (recent.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return _ChipStrip(
                            caption: 'RECENT',
                            clients: recent,
                            onTap: _openProfile,
                          );
                        },
                      ),
                    if (showStrips)
                      StreamBuilder<List<int>>(
                        stream: db.watchPinnedClientIds(),
                        builder: (context, pinSnap) {
                          final pinned = clientsInIdOrder(
                            clients,
                            pinSnap.data ?? const [],
                          );
                          if (pinned.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return _ChipStrip(
                            caption: 'PINNED',
                            captionIcon: Icons.push_pin,
                            clients: pinned,
                            onTap: _openProfile,
                          );
                        },
                      ),
                    const Divider(height: 1, color: PelviColors.chromeBorder),
                    if (listed.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text(
                            dueMode && !searching
                                ? 'No recalls due.'
                                : 'No matches.',
                            style: text.bodyMedium?.copyWith(
                              color: PelviColors.inkMuted,
                            ),
                          ),
                        ),
                      )
                    else if (dueMode)
                      Expanded(
                        child: ListView.separated(
                          itemCount: listed.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final c = listed[index];
                            final dueEntry = dueById[c.id];
                            final caption = dueEntry == null
                                ? null
                                : formatLastSeenCaption(
                                    dueEntry.lastSeen,
                                    now,
                                  );
                            return _ClientRow(
                              client: c,
                              dueCaption: caption,
                              selecting: _selecting,
                              selected: _selected.contains(c.id),
                              onTap: () => _selecting
                                  ? _toggleSelected(c.id)
                                  : _openProfile(c.id),
                              onLongPress: () => _selecting
                                  ? _toggleSelected(c.id)
                                  : _enterSelect(c.id),
                            );
                          },
                        ),
                      )
                    else
                      Expanded(
                        child: _AlphaClientList(
                          clients: listed,
                          selecting: _selecting,
                          selected: _selected,
                          onOpen: _openProfile,
                          onEnterSelect: _enterSelect,
                          onToggle: _toggleSelected,
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _AlphaClientList extends StatefulWidget {
  const _AlphaClientList({
    required this.clients,
    required this.selecting,
    required this.selected,
    required this.onOpen,
    required this.onEnterSelect,
    required this.onToggle,
  });

  final List<Client> clients;
  final bool selecting;
  final Set<int> selected;
  final ValueChanged<int> onOpen;
  final ValueChanged<int> onEnterSelect;
  final ValueChanged<int> onToggle;

  @override
  State<_AlphaClientList> createState() => _AlphaClientListState();
}

class _AlphaClientListState extends State<_AlphaClientList> {
  final _scroll = ScrollController();
  late List<({String letter, List<Client> clients})> _groups;
  late List<({String letter, int count})> _sections;
  String _sticky = '';

  @override
  void initState() {
    super.initState();
    _rebuildGroups();
    _scroll.addListener(_syncSticky);
  }

  @override
  void didUpdateWidget(covariant _AlphaClientList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.clients, widget.clients)) {
      _rebuildGroups();
      _syncSticky();
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_syncSticky);
    _scroll.dispose();
    super.dispose();
  }

  void _rebuildGroups() {
    _groups = groupClientsByLetter(widget.clients);
    _sections = [
      for (final g in _groups) (letter: g.letter, count: g.clients.length),
    ];
    _sticky = '';
  }

  void _syncSticky() {
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    // At rest the in-list letter is enough; overlay only while scrolled.
    final next = offset <= 0
        ? ''
        : stickyLetterAtOffset(_sections, offset);
    if (next != _sticky) setState(() => _sticky = next);
  }

  @override
  Widget build(BuildContext context) {
    // One overlay letter from scroll index — N× pinned headers stack (B/C/J).
    return Stack(
      children: [
        ListView.builder(
          controller: _scroll,
          itemCount: _groups.fold<int>(
            0,
            (n, g) => n + 1 + g.clients.length,
          ),
          itemBuilder: (context, index) {
            var i = index;
            for (final g in _groups) {
              if (i == 0) return _LetterBar(g.letter);
              i--;
              if (i < g.clients.length) {
                final c = g.clients[i];
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (i > 0) const Divider(height: 1),
                    SizedBox(
                      height: kAlphaClientRowHeight,
                      child: _ClientRow(
                        client: c,
                        selecting: widget.selecting,
                        selected: widget.selected.contains(c.id),
                        onTap: () => widget.selecting
                            ? widget.onToggle(c.id)
                            : widget.onOpen(c.id),
                        onLongPress: () => widget.selecting
                            ? widget.onToggle(c.id)
                            : widget.onEnterSelect(c.id),
                      ),
                    ),
                  ],
                );
              }
              i -= g.clients.length;
            }
            return const SizedBox.shrink();
          },
        ),
        if (_sticky.isNotEmpty)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _LetterBar(_sticky),
          ),
      ],
    );
  }
}

class _LetterBar extends StatelessWidget {
  const _LetterBar(this.letter);

  final String letter;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PelviColors.surfaceMuted,
      child: SizedBox(
        height: kAlphaLetterHeaderHeight,
        width: double.infinity,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: PelviSpace.md),
            child: Text(
              letter,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: PelviColors.purple700,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? PelviColors.pink700 : PelviColors.ink,
        side: BorderSide(
          color: selected ? PelviColors.pink700 : PelviColors.border,
        ),
        backgroundColor: selected ? PelviColors.pink50 : PelviColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: PelviSpace.md),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PelviRadius.md),
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected ? PelviColors.pink700 : PelviColors.ink,
            ),
      ),
    );
  }
}

class _ChipStrip extends StatelessWidget {
  const _ChipStrip({
    required this.caption,
    required this.clients,
    required this.onTap,
    this.captionIcon,
  });

  final String caption;
  final IconData? captionIcon;
  final List<Client> clients;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PelviSpace.md,
            PelviSpace.sm,
            PelviSpace.md,
            PelviSpace.sm,
          ),
          child: Row(
            children: [
              if (captionIcon != null) ...[
                Icon(
                  captionIcon,
                  size: 14,
                  color: PelviColors.purple700,
                ),
                const SizedBox(width: PelviSpace.xs),
              ],
              Text(caption, style: text.labelMedium),
            ],
          ),
        ),
        // Cap at two chip rows; height follows 1–2 runs (no empty 2nd-row gap).
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: PelviSpace.md),
          child: ClipRect(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: 36 * 2 + PelviSpace.sm,
              ),
              child: SizedBox(
                width: double.infinity,
                child: Wrap(
                  spacing: PelviSpace.sm,
                  runSpacing: PelviSpace.sm,
                  children: [
                    for (final c in clients)
                      OutlinedButton(
                        onPressed: () => onTap(c.id),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: PelviColors.ink,
                          side: BorderSide(
                            color: captionIcon != null
                                ? PelviColors.purple400
                                : PelviColors.border,
                          ),
                          backgroundColor: captionIcon != null
                              ? PelviColors.purple50
                              : PelviColors.surface,
                          padding: const EdgeInsets.symmetric(
                            horizontal: PelviSpace.md,
                          ),
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(PelviRadius.md),
                          ),
                        ),
                        child: Text(
                          clientDisplayName(c),
                          style: text.labelLarge,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: PelviSpace.sm),
      ],
    );
  }
}

class _ClientRow extends StatelessWidget {
  const _ClientRow({
    required this.client,
    required this.onTap,
    required this.onLongPress,
    required this.selecting,
    required this.selected,
    this.dueCaption,
  });

  final Client client;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selecting;
  final bool selected;
  final String? dueCaption;

  @override
  Widget build(BuildContext context) {
    final meta = dueCaption ??
        [
          if (client.phone != null && client.phone!.isNotEmpty) client.phone!,
          if (client.email != null && client.email!.isNotEmpty) client.email!,
        ].join(' · ');
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      splashColor: PelviColors.surfaceMuted,
      highlightColor: PelviColors.surfaceMuted,
      child: ColoredBox(
        color: selected ? PelviColors.surfaceMuted : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PelviSpace.md,
            vertical: PelviSpace.sm + 4,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        clientDisplayName(client),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      if (meta.isNotEmpty)
                        Text(
                          meta,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                    ],
                  ),
                ),
                if (selecting)
                  Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected
                        ? PelviColors.pink700
                        : PelviColors.inkMuted,
                    size: 22,
                  )
                else
                  const Icon(
                    Icons.chevron_right,
                    color: PelviColors.inkMuted,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
