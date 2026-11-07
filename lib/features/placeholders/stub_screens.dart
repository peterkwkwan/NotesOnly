import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../../widgets/empty_state.dart';

/// Placeholder destination for quick-add / future flows.
class StubScreen extends StatelessWidget {
  const StubScreen({
    super.key,
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: QuietEmptyState(
        title: title,
        body: body,
        primaryLabel: 'Back',
        onPrimary: () => Navigator.of(context).pop(),
      ),
    );
  }
}

/// Shared tab scaffold: hairline app bar + quiet empty body.
class TabPlaceholderScaffold extends StatelessWidget {
  const TabPlaceholderScaffold({
    super.key,
    required this.title,
    required this.emptyTitle,
    required this.emptyBody,
    this.actions,
    this.trailingWell,
  });

  final String title;
  final String emptyTitle;
  final String emptyBody;
  final List<Widget>? actions;
  final Widget? trailingWell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: actions,
      ),
      body: Column(
        children: [
          Expanded(
            child: QuietEmptyState(
              title: emptyTitle,
              body: emptyBody,
            ),
          ),
          if (trailingWell != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                    PelviSpace.page,
                    0,
                    PelviSpace.page,
                    PelviSpace.lg,
                  ),
              child: trailingWell!,
            ),
        ],
      ),
    );
  }
}
