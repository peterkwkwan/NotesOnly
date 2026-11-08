import 'package:flutter/material.dart';

import '../../data/database_provider.dart';
import '../../theme/theme.dart';
import '../notifications/notifications_sheet.dart';

/// Wide-viewport breakpoint for NotesOnly web desktop shell (Figma 1440).
const kDesktopShellMinWidth = 960.0;

bool isDesktopShell(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kDesktopShellMinWidth;

/// Lets page bodies switch shell tabs (e.g. Today → Calendar).
class ShellNavigation extends InheritedWidget {
  const ShellNavigation({
    super.key,
    required this.index,
    required this.goTo,
    required this.breadcrumb,
    required super.child,
  });

  final int index;
  final ValueChanged<int> goTo;
  final String breadcrumb;

  static ShellNavigation of(BuildContext context) {
    final nav = context.dependOnInheritedWidgetOfExactType<ShellNavigation>();
    assert(nav != null, 'ShellNavigation not found');
    return nav!;
  }

  static ShellNavigation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellNavigation>();

  @override
  bool updateShouldNotify(ShellNavigation old) =>
      index != old.index || breadcrumb != old.breadcrumb;
}

/// Desktop destinations — indices match [AppShell] IndexedStack on wide layout.
abstract final class DesktopDest {
  static const today = 0;
  static const calendar = 1;
  static const clients = 2;
  static const soapNotes = 3;
  static const templates = 4;
  static const practiceSettings = 5;

  static String breadcrumbFor(int index) => switch (index) {
        today => 'Practice / Today',
        calendar => 'Practice / Calendar',
        clients => 'Practice / Clients',
        soapNotes => 'Practice / SOAP notes',
        templates => 'Practice / Templates',
        practiceSettings => 'Practice / Settings',
        _ => 'Practice',
      };
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

String practiceCardTitle(String? name) {
  final n = (name ?? '').trim();
  if (n.isEmpty) return 'Your practice';
  return n.endsWith('s') ? "$n' practice" : "$n's practice";
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
                  stream: db.watchPractitionerName(),
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
                            'Practitioner workspace',
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
                  icon: Icons.edit_note_outlined,
                  label: 'SOAP notes',
                  selected: index == DesktopDest.soapNotes,
                  onTap: () => onSelect(DesktopDest.soapNotes),
                ),
                const SizedBox(height: 6),
                _NavItem(
                  icon: Icons.dashboard_outlined,
                  label: 'Templates',
                  selected: index == DesktopDest.templates,
                  onTap: () => onSelect(DesktopDest.templates),
                ),
                const SizedBox(height: 6),
                _NavItem(
                  icon: Icons.tune_outlined,
                  label: 'Practice settings',
                  selected: index == DesktopDest.practiceSettings,
                  onTap: () => onSelect(DesktopDest.practiceSettings),
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

class DesktopTopBar extends StatelessWidget {
  const DesktopTopBar({super.key, required this.breadcrumb});

  final String breadcrumb;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final db = AppDatabaseProvider.of(context);

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
                Text(
                  breadcrumb,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: c.inkMuted,
                  ),
                ),
                const Spacer(),
                Container(
                  width: 352,
                  height: 36,
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
                        child: Text(
                          'Search clients, notes, templates',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: c.inkMuted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '⌘ K',
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.5,
                          color: c.inkMuted,
                        ),
                      ),
                    ],
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
                    return Row(
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
                            initials,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: c.pink700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              display,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                fontWeight: FontWeight.w600,
                                color: c.ink,
                              ),
                            ),
                            Text(
                              'Practitioner',
                              style: TextStyle(
                                fontSize: 10,
                                height: 1.5,
                                color: c.inkMuted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.expand_more, size: 14, color: c.inkMuted),
                      ],
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
