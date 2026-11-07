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
import 'quick_add_sheet.dart';

/// Root chrome: Today · Calendar · Clients · More + center-docked FAB.
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

  static const _pages = <Widget>[
    TodayScreen(),
    CalendarScreen(),
    ClientsScreen(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: _pages,
      ),
      floatingActionButton: _CenterFab(
        onPressed: () => showQuickAddSheet(context),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _PelviBottomBar(
        index: _index,
        onChanged: (i) => setState(() => _index = i),
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
    final reduce = MediaQuery.disableAnimationsOf(context);
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
      child: FloatingActionButton(
        onPressed: widget.onPressed,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        backgroundColor: PelviColors.pink700,
        foregroundColor: PelviColors.inkInverse,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PelviRadius.fab),
        ),
        child: const Icon(Icons.add, size: 25),
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
  });

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PelviColors.surface,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: PelviColors.chromeBorder, width: 1),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                Expanded(
                  child: _TabItem(
                    icon: Icons.today_outlined,
                    selectedIcon: Icons.today,
                    label: 'Today',
                    selected: index == 0,
                    onTap: () => onChanged(0),
                  ),
                ),
                Expanded(
                  child: _TabItem(
                    icon: Icons.calendar_month_outlined,
                    selectedIcon: Icons.calendar_month,
                    label: 'Calendar',
                    selected: index == 1,
                    onTap: () => onChanged(1),
                  ),
                ),
                const SizedBox(width: 56), // FAB gap
                Expanded(
                  child: _TabItem(
                    icon: Icons.people_outline,
                    selectedIcon: Icons.people,
                    label: 'Clients',
                    selected: index == 2,
                    onTap: () => onChanged(2),
                  ),
                ),
                Expanded(
                  child: _TabItem(
                    icon: Icons.more_horiz,
                    selectedIcon: Icons.more_horiz,
                    label: 'More',
                    selected: index == 3,
                    onTap: () => onChanged(3),
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
    final color = selected ? PelviColors.pink700 : PelviColors.inkMuted;
    return InkWell(
      onTap: onTap,
      splashColor: PelviColors.surfaceMuted,
      highlightColor: PelviColors.surfaceMuted,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? PelviColors.pink50 : Colors.transparent,
              borderRadius: BorderRadius.circular(PelviRadius.full),
            ),
            child: Icon(selected ? selectedIcon : icon, size: 21, color: color),
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
    );
  }
}
