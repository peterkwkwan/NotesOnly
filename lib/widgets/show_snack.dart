import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// Matches [kDesktopShellMinWidth] without importing the shell layer.
const _kDesktopSnackMinWidth = 960.0;

/// Tone for the desktop Acme-style toast icon.
enum PelviSnackTone { success, error, warning }

/// SnackBar helper: mobile keeps the top under-app-bar slot; desktop web shell
/// gets a dark bottom-center toast (icon + title + optional detail/action).
void showPelviSnackBar(
  BuildContext context,
  String message, {
  String? detail,
  String? actionLabel,
  VoidCallback? onAction,
  PelviSnackTone? tone,
}) {
  final media = MediaQuery.of(context);
  final desktop = media.size.width >= _kDesktopSnackMinWidth;
  if (desktop) {
    _showDesktopSnack(
      context,
      message: message,
      detail: detail,
      actionLabel: actionLabel,
      onAction: onAction,
      tone: tone ?? _inferTone(message),
    );
    return;
  }

  final theme = Theme.of(context);
  final top = media.padding.top + kToolbarHeight + 8;
  const side = 16.0;
  // Match SnackBar content inset so measured wrap matches on-screen wrap.
  const contentInset = 16.0;
  final style = theme.snackBarTheme.contentTextStyle ??
      theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onInverseSurface,
      );
  final painter = TextPainter(
    text: TextSpan(text: message, style: style),
    textDirection: Directionality.of(context),
    textScaler: media.textScaler,
  )..layout(maxWidth: media.size.width - side * 2 - contentInset * 2);
  // Floating snack is bottom-aligned in the margin slot — slot ≈ bar height
  // keeps the top edge under the app bar as content wraps.
  final barHeight = math.max(48.0, painter.height + contentInset * 2);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, softWrap: true),
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.only(
        left: side,
        right: side,
        top: top,
        bottom: media.size.height - top - barHeight,
      ),
    ),
  );
}

PelviSnackTone _inferTone(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('overlapping') || lower.contains('conflict')) {
    return PelviSnackTone.warning;
  }
  const errorHints = [
    'could not',
    'failed',
    'error',
    'cannot',
    'must ',
    'enter ',
    'choose ',
    'select ',
    'nothing heard',
    'not found',
    'unavailable',
    'not available',
    'add clinical',
    'add a client',
    'no phone',
    'no clinic',
    'no earlier',
  ];
  for (final hint in errorHints) {
    if (lower.contains(hint)) return PelviSnackTone.error;
  }
  return PelviSnackTone.success;
}

void _showDesktopSnack(
  BuildContext context, {
  required String message,
  String? detail,
  String? actionLabel,
  VoidCallback? onAction,
  required PelviSnackTone tone,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();

  final media = MediaQuery.of(context);
  const barMaxWidth = 520.0;
  const bottomGap = 28.0;
  final side = math.max(24.0, (media.size.width - barMaxWidth) / 2);

  late final Color iconBg;
  late final IconData icon;
  switch (tone) {
    case PelviSnackTone.success:
      iconBg = const Color(0xFF1B9E4B);
      icon = Icons.sync;
    case PelviSnackTone.error:
      iconBg = PelviColors.danger;
      icon = Icons.error_outline;
    case PelviSnackTone.warning:
      iconBg = PelviColors.warning;
      icon = Icons.warning_amber_rounded;
  }

  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF2A2430),
      elevation: 0,
      duration: const Duration(seconds: 4),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF3F3848)),
      ),
      margin: EdgeInsets.only(
        left: side,
        right: side,
        bottom: bottomGap,
      ),
      content: _DesktopSnackContent(
        message: message,
        detail: detail,
        actionLabel: actionLabel,
        onAction: onAction == null
            ? null
            : () {
                messenger.hideCurrentSnackBar();
                onAction();
              },
        onDismiss: messenger.hideCurrentSnackBar,
        icon: icon,
        iconBg: iconBg,
      ),
    ),
  );
}

class _DesktopSnackContent extends StatelessWidget {
  const _DesktopSnackContent({
    required this.message,
    required this.icon,
    required this.iconBg,
    required this.onDismiss,
    this.detail,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? detail;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;
  final IconData icon;
  final Color iconBg;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: text.titleSmall?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFFFFCFA),
                        height: 1.25,
                      ) ??
                      const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFFFCFA),
                        height: 1.25,
                      ),
                ),
                if (detail != null && detail!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    style: text.bodySmall?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: const Color(0xFFBEB2C6),
                          height: 1.3,
                        ) ??
                        const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFBEB2C6),
                          height: 1.3,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: PelviColors.purple400,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: text.labelMedium?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
              child: Text(actionLabel!.toUpperCase()),
            ),
          ],
          IconButton(
            onPressed: onDismiss,
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close, size: 18, color: Color(0xFFFFFCFA)),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }
}
