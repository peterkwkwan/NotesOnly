import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/auth.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/org.dart';
import '../../theme/theme.dart';
import '../../widgets/show_snack.dart';
import '../clients/client_format.dart';
import '../notifications/notifications_sheet.dart';

/// Wide-viewport breakpoint for NotesOnly web desktop shell (Figma 1440).
const kDesktopShellMinWidth = 960.0;

bool isDesktopShell(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kDesktopShellMinWidth;

/// Cmd+K on Apple platforms; Ctrl+K elsewhere.
bool desktopSearchUsesMetaModifier([TargetPlatform? platform]) {
  final p = platform ?? defaultTargetPlatform;
  return p == TargetPlatform.macOS || p == TargetPlatform.iOS;
}

String desktopSearchShortcutLabel([TargetPlatform? platform]) =>
    desktopSearchUsesMetaModifier(platform) ? '⌘ K' : 'Ctrl+K';

/// Lets page bodies switch shell tabs (e.g. Today → Calendar).
class ShellNavigation extends InheritedWidget {
  const ShellNavigation({
    super.key,
    required this.index,
    required this.goTo,
    required this.breadcrumb,
    this.soapNoteId,
    this.openSoapNote,
    this.restoreClientsFromSoap,
    this.clientsDueEpoch = 0,
    this.openClientsDue,
    this.openClientProfile,
    required super.child,
  });

  final int index;
  final ValueChanged<int> goTo;
  final String breadcrumb;

  /// Open note on the SOAP notes desktop tab (null = hub / empty).
  final int? soapNoteId;

  /// Switch to SOAP notes and show [noteId] in the desktop workspace.
  final ValueChanged<int>? openSoapNote;

  /// Leave SOAP back to the Clients profile stack when SOAP was opened from
  /// Clients. Returns true if that restore happened.
  final bool Function()? restoreClientsFromSoap;

  /// Bumps when Today asks Clients to land on the Due tab.
  final int clientsDueEpoch;

  /// Switch to Clients and select the Due tab.
  final VoidCallback? openClientsDue;

  /// Switch to Clients and open that client's profile.
  final ValueChanged<int>? openClientProfile;

  static ShellNavigation of(BuildContext context) {
    final nav = context.dependOnInheritedWidgetOfExactType<ShellNavigation>();
    assert(nav != null, 'ShellNavigation not found');
    return nav!;
  }

  static ShellNavigation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellNavigation>();

  @override
  bool updateShouldNotify(ShellNavigation old) =>
      index != old.index ||
      breadcrumb != old.breadcrumb ||
      soapNoteId != old.soapNoteId ||
      clientsDueEpoch != old.clientsDueEpoch;
}

/// Desktop destinations — indices match [AppShell] IndexedStack on wide layout.
abstract final class DesktopDest {
  static const today = 0;
  static const calendar = 1;
  static const clients = 2;
  static const soapNotes = 3;
  static const templates = 4;
  static const practiceSettings = 5;
  static const accountSettings = 6;

  /// First-layer tabs have no crumb; deeper pages supply their own
  /// (e.g. Clients profile → `Clients / Name`, SOAP note → `SOAP notes / …`).
  static String breadcrumbFor(int index) => switch (index) { _ => '' };
}

/// Figma sidebar fill (`#f8f4f3`) — slightly warmer than [PelviColors.surfaceMuted].
const _sidebarBg = Color(0xFFF8F4F3);

String practitionerInitials(String? name) {
  final parts =
      (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  final list = parts.toList();
  if (list.length == 1) return list[0][0].toUpperCase();
  return '${list.first[0]}${list.last[0]}'.toUpperCase();
}

String practiceCardTitle(String? clinicName) {
  final n = (clinicName ?? '').trim();
  if (n.isEmpty) return 'Your practice';
  return n;
}

class DesktopSidebar extends StatelessWidget {
  const DesktopSidebar({
    super.key,
    required this.index,
    required this.onSelect,
  });

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final db = AppDatabaseProvider.of(context);

    return Material(
      color: _sidebarBg,
      child: SizedBox(
        width: 220,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: c.chromeBorder)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 28, 18, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/brand/notesonly-monogram.png',
                        width: 28,
                        height: 31,
                        filterQuality: FilterQuality.high,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'NotesOnly',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.8,
                            color: c.ink,
                            height: 1.1,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                StreamBuilder<String?>(
                  stream: db.watchClinicName(),
                  builder: (context, snap) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(PelviRadius.sm),
                        border: Border.all(color: c.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            practiceCardTitle(snap.data),
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              fontWeight: FontWeight.w600,
                              color: c.ink,
                            ),
                          ),
                          Text(
                            'Clinic workspace',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.5,
                              fontWeight: FontWeight.w400,
                              color: c.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 30),
                _NavItem(
                  icon: Icons.event_available_outlined,
                  label: 'Today',
                  selected: index == DesktopDest.today,
                  onTap: () => onSelect(DesktopDest.today),
                ),
                const SizedBox(height: 6),
                _NavItem(
                  icon: Icons.calendar_month_outlined,
                  label: 'Calendar',
                  selected: index == DesktopDest.calendar,
                  onTap: () => onSelect(DesktopDest.calendar),
                ),
                const SizedBox(height: 6),
                _NavItem(
                  icon: Icons.people_outline,
                  label: 'Clients',
                  selected: index == DesktopDest.clients,
                  onTap: () => onSelect(DesktopDest.clients),
                ),
                const SizedBox(height: 6),
                _NavItem(
                  icon: Icons.dashboard_outlined,
                  label: 'Templates',
                  selected: index == DesktopDest.templates,
                  onTap: () => onSelect(DesktopDest.templates),
                ),
                StreamBuilder<String?>(
                  stream: db.watchSetting(AppDatabase.activeOrgRolesKey),
                  builder: (context, snap) {
                    final roles = parseOrgRoles(snap.data);
                    if (!canManagePracticeSettings(roles)) {
                      return const SizedBox.shrink();
                    }
                    return Column(
                      children: [
                        const SizedBox(height: 6),
                        _NavItem(
                          icon: Icons.tune_outlined,
                          label: 'Practice settings',
                          selected: index == DesktopDest.practiceSettings,
                          onTap: () => onSelect(DesktopDest.practiceSettings),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 6),
                _NavItem(
                  icon: Icons.person_outline,
                  label: 'Account settings',
                  selected: index == DesktopDest.accountSettings,
                  onTap: () => onSelect(DesktopDest.accountSettings),
                ),
                const Spacer(),
                Divider(height: 1, color: c.border),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Icon(Icons.help_outline, size: 18, color: c.inkMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Help & resources',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: c.inkMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'YOUR PRACTICE, SIMPLIFIED',
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.5,
                    letterSpacing: 0.2,
                    color: c.inkMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final fg = selected ? c.pink700 : c.ink;
    return Material(
      color: selected ? c.pink50 : _sidebarBg,
      borderRadius: BorderRadius.circular(PelviRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PelviRadius.sm),
        splashColor: c.surfaceMuted,
        highlightColor: c.surfaceMuted,
        child: SizedBox(
          height: 43,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: fg,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Crumb line for desktop page headers (above the title), not the top bar.
class DesktopBreadcrumb extends StatelessWidget {
  const DesktopBreadcrumb({
    super.key,
    this.text,
    this.onAncestorTap,
    this.onLeafTap,
  });

  /// Override when [ShellNavigation] is absent or a page needs a local crumb.
  final String? text;

  /// Called for every segment except the last (`Clients / Name` → index 0).
  final ValueChanged<int>? onAncestorTap;

  /// When set, the last segment is a link (e.g. SOAP workspace → client profile).
  final VoidCallback? onLeafTap;

  @override
  Widget build(BuildContext context) {
    final label =
        text ?? ShellNavigation.maybeOf(context)?.breadcrumb ?? '';
    if (label.isEmpty) return const SizedBox.shrink();
    final c = PelviColors.of(context);
    const style = TextStyle(fontSize: 12, height: 1.5);
    final parts = label.split(' / ');
    final interactive =
        (onAncestorTap != null && parts.length > 1) || onLeafTap != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: interactive
          ? Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var i = 0; i < parts.length; i++) ...[
                  if (i > 0)
                    Text(
                      ' / ',
                      style: style.copyWith(color: c.inkMuted),
                    ),
                  if (i < parts.length - 1 && onAncestorTap != null)
                    _DesktopBreadcrumbLink(
                      label: parts[i],
                      onTap: () => onAncestorTap!(i),
                    )
                  else if (i == parts.length - 1 && onLeafTap != null)
                    _DesktopBreadcrumbLink(
                      label: parts[i],
                      onTap: onLeafTap!,
                    )
                  else
                    Text(
                      parts[i],
                      style: style.copyWith(color: c.inkMuted),
                    ),
                ],
              ],
            )
          : Text(
              label,
              style: style.copyWith(color: c.inkMuted),
            ),
    );
  }
}

class _DesktopBreadcrumbLink extends StatefulWidget {
  const _DesktopBreadcrumbLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_DesktopBreadcrumbLink> createState() => _DesktopBreadcrumbLinkState();
}

class _DesktopBreadcrumbLinkState extends State<_DesktopBreadcrumbLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: _hover ? c.ink : c.inkMuted,
            decoration:
                _hover ? TextDecoration.underline : TextDecoration.none,
            decorationColor: c.ink,
          ),
        ),
      ),
    );
  }
}

class DesktopTopBar extends StatefulWidget {
  const DesktopTopBar({super.key});

  @override
  State<DesktopTopBar> createState() => _DesktopTopBarState();
}

class _DesktopTopBarState extends State<DesktopTopBar> {
  final _searchFocus = FocusNode();
  final _searchController = TextEditingController();
  final _searchLink = LayerLink();
  final _portal = OverlayPortalController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocus);
    HardwareKeyboard.instance.addHandler(_onGlobalKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onGlobalKey);
    _searchFocus.removeListener(_onSearchFocus);
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool _onGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyK) return false;
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final meta = keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
    final control = keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
    final wantMeta = desktopSearchUsesMetaModifier();
    if (wantMeta ? !meta : !control) return false;
    _searchFocus.requestFocus();
    return true;
  }

  void _onSearchFocus() {
    if (_searchFocus.hasFocus) {
      _syncOverlay();
    } else {
      _portal.hide();
      if (_query.isNotEmpty) {
        _searchController.clear();
        setState(() => _query = '');
      }
    }
  }

  void _syncOverlay() {
    if (_searchFocus.hasFocus && _query.trim().isNotEmpty) {
      if (!_portal.isShowing) _portal.show();
    } else if (_portal.isShowing) {
      _portal.hide();
    }
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _syncOverlay();
  }

  void _openClient(Client client) {
    _searchController.clear();
    setState(() => _query = '');
    _portal.hide();
    _searchFocus.unfocus();
    ShellNavigation.maybeOf(context)?.openClientProfile?.call(client.id);
  }

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final db = AppDatabaseProvider.of(context);
    final shortcut = desktopSearchShortcutLabel();

    return Material(
      color: c.surface,
      child: SizedBox(
        height: 76,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.chromeBorder)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              children: [
                const Spacer(),
                CompositedTransformTarget(
                  link: _searchLink,
                  child: OverlayPortal(
                    controller: _portal,
                    overlayChildBuilder: (context) {
                      return UnconstrainedBox(
                        alignment: Alignment.topLeft,
                        child: CompositedTransformFollower(
                          link: _searchLink,
                          showWhenUnlinked: false,
                          targetAnchor: Alignment.bottomLeft,
                          followerAnchor: Alignment.topLeft,
                          offset: const Offset(0, 6),
                          // Keep field focused so the row tap is not torn down.
                          child: TextFieldTapRegion(
                            child: _DesktopClientSearchResults(
                              query: _query,
                              width: 352,
                              searchFocus: _searchFocus,
                              onSelect: _openClient,
                            ),
                          ),
                        ),
                      );
                    },
                    child: Container(
                      width: 352,
                      height: 36,
                      // Intrinsic row + align: true mid of icon/hint/shortcut.
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: c.canvas,
                        borderRadius: BorderRadius.circular(PelviRadius.sm),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, size: 16, color: c.inkMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              focusNode: _searchFocus,
                              controller: _searchController,
                              onChanged: _onQueryChanged,
                              textInputAction: TextInputAction.search,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.2,
                                color: c.ink,
                              ),
                              decoration: InputDecoration(
                                // Collapsed = intrinsic height; Row centers in 36.
                                isCollapsed: true,
                                filled: false,
                                contentPadding: EdgeInsets.zero,
                                // Outer chrome owns the border; kill theme outline.
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                errorBorder: InputBorder.none,
                                focusedErrorBorder: InputBorder.none,
                                hintText: 'Search clients',
                                hintStyle: TextStyle(
                                  fontSize: 12,
                                  height: 1.2,
                                  color: c.inkMuted,
                                ),
                              ),
                            ),
                          ),
                          Text(
                            shortcut,
                            style: TextStyle(
                              fontSize: 10,
                              height: 1.2,
                              color: c.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                StreamBuilder(
                  stream: db.watchRecallInboxClients(),
                  builder: (context, snap) {
                    final count = snap.data?.length ?? 0;
                    return IconButton(
                      tooltip: 'Notifications',
                      onPressed: () => showNotificationsSheet(context),
                      icon: Badge(
                        isLabelVisible: count > 0,
                        smallSize: 7,
                        backgroundColor: c.purple700,
                        child: Icon(
                          Icons.notifications_none_outlined,
                          size: 18,
                          color: c.ink,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                StreamBuilder<String?>(
                  stream: db.watchPractitionerName(),
                  builder: (context, snap) {
                    final name = (snap.data ?? '').trim();
                    final display =
                        name.isEmpty ? 'Practitioner' : name;
                    final initials = practitionerInitials(name);
                    return StreamBuilder<String?>(
                      stream: db.watchSetting(AppDatabase.activeOrgRolesKey),
                      builder: (context, roleSnap) {
                        final roles = parseOrgRoles(roleSnap.data);
                        return _DesktopAccountMenuChip(
                          displayName: display,
                          initials: initials,
                          roles: roles,
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Desktop top-bar account chip: no hover wash/tooltip; chevron flips while open.
class _DesktopAccountMenuChip extends StatefulWidget {
  const _DesktopAccountMenuChip({
    required this.displayName,
    required this.initials,
    required this.roles,
  });

  final String displayName;
  final String initials;
  final List<OrgRole> roles;

  @override
  State<_DesktopAccountMenuChip> createState() =>
      _DesktopAccountMenuChipState();
}

class _DesktopAccountMenuChipState extends State<_DesktopAccountMenuChip> {
  bool _open = false;

  void _setOpen(bool open) {
    if (_open == open) return;
    setState(() => _open = open);
  }

  ButtonStyle _itemStyle(PelviPalette c) {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused) ||
            states.contains(WidgetState.pressed)) {
          return c.surfaceMuted;
        }
        return Colors.transparent;
      }),
      foregroundColor: WidgetStatePropertyAll(c.ink),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(220, 40)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PelviRadius.sm),
        ),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 13, fontWeight: FontWeight.w500, height: 1.3),
      ),
      visualDensity: VisualDensity.standard,
    );
  }

  /// Paint icons in [child] with an explicit color — MenuItemButton
  /// [leadingIcon] + ButtonStyle.iconColor IconTheme was not visible on web.
  Widget _itemLabel(PelviPalette c, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: c.inkMuted),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final itemStyle = _itemStyle(c);
    // MenuAnchor + GestureDetector: PopupMenuButton's InkWell always paints
    // an M3 hover overlay; Theme.hoverColor does not suppress it.
    return MenuAnchor(
      alignmentOffset: const Offset(0, 8),
      onOpen: () => _setOpen(true),
      onClose: () => _setOpen(false),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(c.ink.withValues(alpha: 0.14)),
        elevation: const WidgetStatePropertyAll(10),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PelviRadius.lg),
            side: BorderSide(color: c.border),
          ),
        ),
      ),
      menuChildren: [
        MenuItemButton(
          style: itemStyle,
          onPressed: () => ShellNavigation.maybeOf(context)
              ?.goTo(DesktopDest.accountSettings),
          child: _itemLabel(c, Icons.settings_outlined, 'Account settings'),
        ),
        if (canManagePracticeSettings(widget.roles))
          MenuItemButton(
            style: itemStyle,
            onPressed: () => ShellNavigation.maybeOf(context)
                ?.goTo(DesktopDest.practiceSettings),
            child: _itemLabel(c, Icons.apartment_outlined, 'Practice settings'),
          ),
        MenuItemButton(
          style: itemStyle,
          onPressed: () => _signOutFromDesktop(context),
          child: _itemLabel(c, Icons.logout, 'Sign out'),
        ),
      ],
      builder: (context, controller, child) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.pink50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    widget.initials,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: c.pink700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  widget.displayName,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  child: Icon(Icons.expand_more, size: 14, color: c.inkMuted),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DesktopClientSearchResults extends StatefulWidget {
  const _DesktopClientSearchResults({
    required this.query,
    required this.width,
    required this.searchFocus,
    required this.onSelect,
  });

  final String query;
  final double width;
  final FocusNode searchFocus;
  final ValueChanged<Client> onSelect;

  @override
  State<_DesktopClientSearchResults> createState() =>
      _DesktopClientSearchResultsState();
}

class _DesktopClientSearchResultsState
    extends State<_DesktopClientSearchResults> {
  int _highlightIndex = 0;
  List<Client> _matches = const [];

  @override
  void initState() {
    super.initState();
    widget.searchFocus.onKeyEvent = _onSearchKey;
  }

  @override
  void didUpdateWidget(covariant _DesktopClientSearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchFocus != widget.searchFocus) {
      if (oldWidget.searchFocus.onKeyEvent == _onSearchKey) {
        oldWidget.searchFocus.onKeyEvent = null;
      }
      widget.searchFocus.onKeyEvent = _onSearchKey;
    }
    if (oldWidget.query != widget.query) {
      _highlightIndex = 0;
    }
  }

  @override
  void dispose() {
    if (widget.searchFocus.onKeyEvent == _onSearchKey) {
      widget.searchFocus.onKeyEvent = null;
    }
    super.dispose();
  }

  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_matches.isEmpty) return KeyEventResult.handled;
      setState(() {
        _highlightIndex =
            (_highlightIndex + 1).clamp(0, _matches.length - 1);
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (_matches.isEmpty) return KeyEventResult.handled;
      setState(() {
        _highlightIndex =
            (_highlightIndex - 1).clamp(0, _matches.length - 1);
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_matches.isEmpty) return KeyEventResult.ignored;
      final i = _highlightIndex.clamp(0, _matches.length - 1);
      widget.onSelect(_matches[i]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final db = AppDatabaseProvider.of(context);

    return Material(
      elevation: 2,
      color: c.surface,
      borderRadius: BorderRadius.circular(PelviRadius.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(PelviRadius.sm),
          border: Border.all(color: c.border),
        ),
        child: SizedBox(
          width: widget.width,
          child: StreamBuilder<List<Client>>(
            stream: db.watchClients(),
            builder: (context, snap) {
              final clients = snap.data;
              if (clients == null) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              final matches =
                  filterClients(clients, widget.query).take(8).toList();
              _matches = matches;
              if (matches.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 16,
                  ),
                  child: Text(
                    'No clients match',
                    style: TextStyle(fontSize: 12, color: c.inkMuted),
                  ),
                );
              }
              final highlight =
                  _highlightIndex.clamp(0, matches.length - 1);
              return ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: matches.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: c.border),
                itemBuilder: (context, i) {
                  final client = matches[i];
                  final phone = (client.phone ?? '').trim();
                  final selected = i == highlight;
                  return InkWell(
                    onTap: () => widget.onSelect(client),
                    child: ColoredBox(
                      color: selected ? c.surfaceMuted : Colors.transparent,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              clientDisplayName(client),
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                                color: c.ink,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (phone.isNotEmpty)
                              Text(
                                phone,
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.4,
                                  color: c.inkMuted,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

Future<void> _signOutFromDesktop(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sign out?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await AppDatabaseProvider.of(context).clearLocalClinicForAccountSwitch();
    await NotesAuth.signOut();
  } catch (e) {
    if (context.mounted) {
      showPelviSnackBar(context, 'Sign out failed: $e');
    }
  }
}

/// Desktop page header actions — matches Account “Save changes”
/// (38 tall, 14h pad, radius 8, 13/w600; not pill, no M3 tap-target bloat).
abstract final class DesktopChromeButtons {
  static const height = 38.0;
  static const horizontalPadding = 14.0;
  static const gap = 10.0;
  static const radius = PelviRadius.sm;

  static const labelStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.5,
  );

  static const titleStyle = TextStyle(
    fontSize: 29,
    height: 1.5,
    fontWeight: FontWeight.w600,
  );

  static ButtonStyle filled(PelviPalette c) => FilledButton.styleFrom(
        backgroundColor: c.pink700,
        foregroundColor: c.inkInverse,
        disabledBackgroundColor: c.pink200,
        disabledForegroundColor: c.inkInverse,
        elevation: 0,
        minimumSize: const Size(0, height),
        maximumSize: const Size(double.infinity, height),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: horizontalPadding),
        textStyle: labelStyle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      );

  static ButtonStyle outlined(PelviPalette c) => OutlinedButton.styleFrom(
        backgroundColor: c.surface,
        foregroundColor: c.ink,
        disabledForegroundColor: c.inkMuted,
        side: BorderSide(color: c.border),
        minimumSize: const Size(0, height),
        maximumSize: const Size(double.infinity, height),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: horizontalPadding),
        textStyle: labelStyle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

/// Title row + right actions on one baseline; optional subtitle below.
class DesktopPageHeader extends StatelessWidget {
  const DesktopPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.breadcrumb,
    this.onBreadcrumbAncestor,
    this.onBreadcrumbLeaf,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;

  /// Override [DesktopBreadcrumb]; null uses [ShellNavigation].
  final String? breadcrumb;
  final ValueChanged<int>? onBreadcrumbAncestor;
  final VoidCallback? onBreadcrumbLeaf;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopBreadcrumb(
          text: breadcrumb,
          onAncestorTap: onBreadcrumbAncestor,
          onLeafTap: onBreadcrumbLeaf,
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                title,
                style: DesktopChromeButtons.titleStyle.copyWith(color: c.ink),
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 20),
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: DesktopChromeButtons.gap),
                actions[i],
              ],
            ],
          ],
        ),
        if (subtitle != null && subtitle!.isNotEmpty)
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: c.inkMuted,
            ),
          ),
      ],
    );
  }
}

/// Primary desktop chrome action (Account “Save changes”).
class DesktopFilledAction extends StatelessWidget {
  const DesktopFilledAction({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final enabled = onPressed != null;
    return Material(
      color: enabled ? c.pink700 : c.pink200,
      borderRadius: BorderRadius.circular(DesktopChromeButtons.radius),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(DesktopChromeButtons.radius),
        child: Container(
          height: DesktopChromeButtons.height,
          padding: const EdgeInsets.symmetric(
            horizontal: DesktopChromeButtons.horizontalPadding,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: c.inkInverse),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: DesktopChromeButtons.labelStyle.copyWith(
                  color: c.inkInverse,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Secondary desktop chrome action (Account “Discard changes”).
class DesktopOutlineAction extends StatelessWidget {
  const DesktopOutlineAction({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final enabled = onPressed != null;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(DesktopChromeButtons.radius),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(DesktopChromeButtons.radius),
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Container(
            height: DesktopChromeButtons.height,
            padding: const EdgeInsets.symmetric(
              horizontal: DesktopChromeButtons.horizontalPadding,
            ),
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(DesktopChromeButtons.radius),
              border: Border.all(color: c.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: c.ink),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: DesktopChromeButtons.labelStyle.copyWith(color: c.ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Stub body for desktop destinations owned by follow-on agents.
class DesktopPlaceholderPage extends StatelessWidget {
  const DesktopPlaceholderPage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return ColoredBox(
      color: c.canvas,
      child: Center(
        child: Text(
          '$title — web layout coming next',
          style: TextStyle(fontSize: 15, color: c.inkMuted),
        ),
      ),
    );
  }
}
