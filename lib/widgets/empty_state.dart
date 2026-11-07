import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Full-screen quiet empty state — ink Medium title, muted body, optional CTA.
class QuietEmptyState extends StatelessWidget {
  const QuietEmptyState({
    super.key,
    required this.title,
    required this.body,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String body;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PelviSpace.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 290),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayLarge,
              ),
              const SizedBox(height: PelviSpace.md),
              Text(
                body,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: PelviColors.of(context).inkMuted,
                    ),
              ),
              if (primaryLabel != null && onPrimary != null) ...[
                const SizedBox(height: PelviSpace.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onPrimary,
                    child: Text(primaryLabel!),
                  ),
                ),
              ],
              if (secondaryLabel != null && onSecondary != null) ...[
                const SizedBox(height: PelviSpace.sm),
                TextButton(
                  onPressed: onSecondary,
                  style: TextButton.styleFrom(
                    foregroundColor: PelviColors.of(context).pink700,
                  ),
                  child: Text(secondaryLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Solid soft-pink empty well (Figma: `#f8eaf0`, filled dusty-pink CTA).
class DashedEmptyWell extends StatelessWidget {
  const DashedEmptyWell({
    super.key,
    required this.message,
    this.ctaLabel,
    this.onCta,
  });

  final String message;
  final String? ctaLabel;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    final well = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: PelviColors.of(context).pink50,
        borderRadius: BorderRadius.circular(PelviRadius.lg),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: PelviColors.of(context).inkMuted,
                  fontSize: 14,
                  height: 1.5,
                ),
          ),
          if (ctaLabel != null && onCta != null) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: onCta,
                icon: const Icon(Icons.add, size: 19),
                label: Text(ctaLabel!),
              ),
            ),
          ],
        ],
      ),
    );
    if (onCta == null) return well;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onCta,
        borderRadius: BorderRadius.circular(PelviRadius.lg),
        splashColor: PelviColors.of(context).surfaceMuted,
        highlightColor: PelviColors.of(context).surfaceMuted,
        child: well,
      ),
    );
  }
}
