import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/local_notifications.dart';
import '../../theme/theme.dart';
import '../calendar/calendar_screen.dart';
import '../clients/clients_screen.dart';
import '../more/more_screen.dart';
import '../today/today_screen.dart';
import 'desktop_chrome.dart';
import 'quick_add_sheet.dart';

/// Root chrome: mobile bottom bar · desktop sidebar + top bar.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  StreamSubscription<List<RecallDueEntry>>? _recallSub;
  StreamSubscription<bool>? _recallNotifSub;
  int _dueCount = 0;
  bool _recallNotifsOn = true;

  /// Mobile IA: Today · Calendar · Clients · More.
  static const _mobilePages = <Widget>[
    TodayScreen(),
    CalendarScreen(),
    ClientsScreen(),
    MoreScreen(),
  ];

  /// Desktop IA matches Figma sidebar (SOAP notes / Templates stubbed for later).
  static const _desktopPages = <Widget>[
    TodayScreen(),
    CalendarScreen(),
    ClientsScreen(),
    DesktopPlaceholderPage(title: 'SOAP notes'),
    DesktopPlaceholderPage(title: 'Templates'),
    MoreScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bindRecallPush());
  }

  void _bindRecallPush() {
    if (!mounted) return;
    final db = AppDatabaseProvider.of(context);
    _recallSub?.cancel();
    _recallNotifSub?.cancel();
    _recallSub = db.watchRecallInboxClients().listen((due) {
      _dueCount = due.length;
      LocalNotifications.syncRecallDueCount(
        _dueCount,
        enabled: _recallNotifsOn,
      );
    });
    _recallNotifSub = db.watchRecallNotificationsEnabled().listen((on) {
      _recallNotifsOn = on;
      LocalNotifications.syncRecallDueCount(
        _dueCount,
        enabled: _recallNotifsOn,
      );
    });
  }

  @override
  void dispose() {
    _recallSub?.cancel();
    _recallNotifSub?.cancel();
    super.dispose();
  }

  /// [_index] always uses desktop destination ids; mobile remaps More ↔ settings.
  int _mobileIndex(int desktopIndex) {
    if (desktopIndex <= 2) return desktopIndex;
    if (desktopIndex == DesktopDest.practiceSettings) return 3;
    return 0;
  }

  int _desktopIndexFromMobile(int mobileIndex) {
    if (mobileIndex <= 2) return mobileIndex;
    return DesktopDest.practiceSettings;
  }

  void _goTo(int desktopIndex) {
    final next = desktopIndex.clamp(0, _desktopPages.length - 1);
    if (next == _index) return;
    setState(() => _index = next);
  }

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktopShell(context);

    if (desktop) {
      final breadcrumb = DesktopDest.breadcrumbFor(_index);
      return ShellNavigation(
        index: _index,
        goTo: _goTo,
        breadcrumb: breadcrumb,
        child: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DesktopSidebar(
                index: _index,
                onSelect: _goTo,
              ),
              Expanded(
                child: Column(
                  children: [
                    DesktopTopBar(breadcrumb: breadcrumb),
                    Expanded(
                      child: IndexedStack(
                        index: _index,
                        children: _desktopPages,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final mobileIndex = _mobileIndex(_index);
    return Scaffold(
      body: IndexedStack(
        index: mobileIndex,
        children: _mobilePages,
      ),
      // FAB lives in the bottom bar middle slot (Figma), not floating above it.
      bottomNavigationBar: _PelviBottomBar(
        index: mobileIndex,
        onChanged: (i) => _goTo(_desktopIndexFromMobile(i)),
        onFab: () => showQuickAddSheet(context),
      ),
    );
  }
}

class _CenterFab extends StatefulWidget {
  const _CenterFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_CenterFab> createState() => _CenterFabState();
}

class _CenterFabState extends State<_CenterFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    final curve = CurvedAnimation(parent: _pulse, curve: Curves.easeInOut);
    _scale = Tween(begin: 1.0, end: 1.04).animate(curve);
    _opacity = Tween(begin: 1.0, end: 0.88).animate(curve);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.of(context);
    if (reduce) {
      _pulse.stop();
      _pulse.value = 0;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fab = SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: PelviColors.of(context).pink700,
        borderRadius: BorderRadius.circular(PelviRadius.fab),
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(PelviRadius.fab),
          child: Center(
            child: Icon(Icons.add, size: 25, color: PelviColors.of(context).inkInverse),
          ),
        ),
      ),
    );

    if (MediaQuery.disableAnimationsOf(context)) return fab;

    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(scale: _scale, child: fab),
    );
  }
}

class _PelviBottomBar extends StatelessWidget {
  const _PelviBottomBar({
    required this.index,
    required this.onChanged,
    required this.onFab,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final VoidCallback onFab;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PelviColors.of(context).surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: PelviColors.of(context).chromeBorder, width: 1),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 9, 16, 0),
            child: SizedBox(
              height: 64,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _TabItem(
                    icon: Icons.today_outlined,
                    selectedIcon: Icons.today,
                    label: 'Today',
                    selected: index == 0,
                    onTap: () => onChanged(0),
                  ),
                  _TabItem(
                    icon: Icons.calendar_month_outlined,
                    selectedIcon: Icons.calendar_month,
                    label: 'Calendar',
                    selected: index == 1,
                    onTap: () => onChanged(1),
                  ),
                  _CenterFab(onPressed: onFab),
                  _TabItem(
                    icon: Icons.people_outline,
                    selectedIcon: Icons.people,
                    label: 'Clients',
                    selected: index == 2,
                    onTap: () => onChanged(2),
                  ),
                  _TabItem(
                    icon: Icons.more_horiz,
                    selectedIcon: Icons.more_horiz,
                    label: 'More',
                    selected: index == 3,
                    onTap: () => onChanged(3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? PelviColors.of(context).pink700 : PelviColors.of(context).inkMuted;
    return SizedBox(
      width: 61,
      child: InkWell(
        onTap: onTap,
        splashColor: PelviColors.of(context).surfaceMuted,
        highlightColor: PelviColors.of(context).surfaceMuted,
        borderRadius: BorderRadius.circular(PelviRadius.sm),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? PelviColors.of(context).pink50 : Colors.transparent,
                borderRadius: BorderRadius.circular(PelviRadius.full),
              ),
              child: Icon(
                selected ? selectedIcon : icon,
                size: 21,
                color: color,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                height: 14 / 11,
                letterSpacing: 0.2,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
