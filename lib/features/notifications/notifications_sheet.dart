import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/show_snack.dart';
import '../appointments/appointment_form_screen.dart';
import '../clients/client_format.dart';
import '../clients/client_profile_screen.dart';

/// In-app recall list — mirrors the Today bell. Purple badge is reserved for unread.
/// Figma Notifications sheet top radius (`2:7531`).
const _kSheetTopRadius = 28.0;

Future<void> showNotificationsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: PelviColors.of(context).surface,
    barrierColor: PelviColors.of(context).overlay,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(_kSheetTopRadius),
      ),
    ),
    builder: (context) => const _NotificationsSheet(),
  );
}

enum _RecallAction {
  whatsapp,
  appointment,
  mute,
  clear,
  profile,
}

Future<_RecallAction?> _showRecallActionSheet(
  BuildContext context, {
  required String clientName,
}) {
  return showModalBottomSheet<_RecallAction>(
    context: context,
    backgroundColor: PelviColors.of(context).surface,
    barrierColor: PelviColors.of(context).overlay,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(PelviRadius.lg)),
    ),
    builder: (context) {
      final text = Theme.of(context).textTheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
                    PelviSpace.page,
                    PelviSpace.sm,
                    PelviSpace.page,
                    PelviSpace.md,
                  ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: PelviColors.of(context).border,
                    borderRadius: BorderRadius.circular(PelviRadius.full),
                  ),
                ),
              ),
              const SizedBox(height: PelviSpace.md),
              Text(clientName, style: text.titleLarge),
              const SizedBox(height: PelviSpace.xs),
              Text(
                'Recall actions',
                style: text.bodyMedium?.copyWith(color: PelviColors.of(context).inkMuted),
              ),
              const SizedBox(height: PelviSpace.md),
              const Divider(height: 1),
              _ActionRow(
                icon: Icons.chat_outlined,
                title: 'WhatsApp',
                onTap: () => Navigator.pop(context, _RecallAction.whatsapp),
              ),
              const Divider(height: 1),
              _ActionRow(
                icon: Icons.event_outlined,
                title: 'Create appointment',
                onTap: () =>
                    Navigator.pop(context, _RecallAction.appointment),
              ),
              const Divider(height: 1),
              _ActionRow(
                icon: Icons.notifications_off_outlined,
                title: 'Mute recalls',
                onTap: () => Navigator.pop(context, _RecallAction.mute),
              ),
              const Divider(height: 1),
              _ActionRow(
                icon: Icons.clear_outlined,
                title: 'Clear',
                onTap: () => Navigator.pop(context, _RecallAction.clear),
              ),
              const Divider(height: 1),
              _ActionRow(
                icon: Icons.person_outline,
                title: 'Open profile',
                onTap: () => Navigator.pop(context, _RecallAction.profile),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      splashColor: PelviColors.of(context).surfaceMuted,
      highlightColor: PelviColors.of(context).surfaceMuted,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: PelviSpace.sm + 4,
          horizontal: PelviSpace.xs,
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: PelviColors.of(context).pink700),
            const SizedBox(width: PelviSpace.md),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsSheet extends StatelessWidget {
  const _NotificationsSheet();

  Future<void> _onRowTap(
    BuildContext context,
    RecallDueEntry entry,
  ) async {
    final db = AppDatabaseProvider.of(context);
    final name = clientDisplayName(entry.client);
    final action = await _showRecallActionSheet(context, clientName: name);
    if (action == null || !context.mounted) return;

    switch (action) {
      case _RecallAction.whatsapp:
        final phone = entry.client.phone?.trim() ?? '';
        if (phone.isEmpty) {
          showPelviSnackBar(context, 'No phone number for this client.');
          return;
        }
        final digits = phone.replaceAll(RegExp(r'\D'), '');
        await launchUrl(
          Uri.parse('https://wa.me/$digits'),
          mode: LaunchMode.externalApplication,
        );
      case _RecallAction.appointment:
        Navigator.of(context).pop();
        if (!context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AppointmentFormScreen(clientId: entry.client.id),
          ),
        );
      case _RecallAction.mute:
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Mute recalls?'),
            content: Text(
              'Stop showing recall reminders for $name until you unmute '
              'on their profile.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(
                  foregroundColor: PelviColors.of(context).warning,
                ),
                child: const Text('Mute'),
              ),
            ],
          ),
        );
        if (ok == true) await db.setRecallMuted(entry.client.id, true);
      case _RecallAction.clear:
        await db.clearRecallInboxItem(entry.client.id);
      case _RecallAction.profile:
        Navigator.of(context).pop();
        if (!context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ClientProfileScreen(clientId: entry.client.id),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = AppDatabaseProvider.of(context);
    final c = PelviColors.of(context);
    final text = Theme.of(context).textTheme;
    final height = MediaQuery.sizeOf(context).height * 0.72;
    final now = DateTime.now();

    return SizedBox(
      height: height,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 26,
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: PelviSpace.page),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Notifications',
                            style: text.titleLarge?.copyWith(
                              fontSize: 26,
                              height: 1,
                              letterSpacing: -0.8,
                            ),
                          ),
                        ),
                        Tooltip(
                          message: 'Close',
                          child: Material(
                            color: c.surfaceMuted,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => Navigator.of(context).pop(),
                              child: SizedBox(
                                width: 34,
                                height: 34,
                                child: Icon(
                                  Icons.close,
                                  size: 18,
                                  color: c.inkMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: PelviSpace.lg),
                    Expanded(
                      child: StreamBuilder<List<RecallDueEntry>>(
                        stream: db.watchRecallInboxClients(),
                        builder: (context, snap) {
                          final due = snap.data;
                          if (due == null) {
                            return Center(
                              child: CircularProgressIndicator(
                                color: c.pink700,
                              ),
                            );
                          }
                          if (due.isEmpty) {
                            return Center(
                              child: Text(
                                'No recalls due.',
                                style: text.bodyMedium?.copyWith(
                                  color: c.inkMuted,
                                ),
                              ),
                            );
                          }
                          return ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: due.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: PelviSpace.sm),
                            itemBuilder: (context, i) {
                              final entry = due[i];
                              return _RecallNotificationCard(
                                entry: entry,
                                now: now,
                                onTap: () => _onRowTap(context, entry),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bordered recall row — Figma `2:7540`.
class _RecallNotificationCard extends StatelessWidget {
  const _RecallNotificationCard({
    required this.entry,
    required this.now,
    required this.onTap,
  });

  final RecallDueEntry entry;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final text = Theme.of(context).textTheme;

    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PelviRadius.lg),
        side: BorderSide(color: c.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PelviRadius.lg),
        splashColor: c.surfaceMuted,
        highlightColor: c.surfaceMuted,
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.purple50,
                  borderRadius: BorderRadius.circular(PelviRadius.md),
                ),
                child: Text(
                  clientInitials(entry.client),
                  style: text.bodyMedium?.copyWith(
                    fontSize: 14,
                    height: 1,
                    fontWeight: FontWeight.w500,
                    color: c.purple700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recall · ${clientDisplayName(entry.client)}',
                      style: text.bodyMedium?.copyWith(
                        fontSize: 15,
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      formatLastSeenCaption(entry.lastSeen, now),
                      style: text.bodyMedium?.copyWith(
                        fontSize: 12,
                        height: 1.2,
                        fontWeight: FontWeight.w400,
                        color: c.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: c.inkMuted, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bell with optional purple unread dot when [dueCount] > 0.
class NotificationBellButton extends StatelessWidget {
  const NotificationBellButton({
    super.key,
    required this.dueCount,
    required this.onPressed,
  });

  final int dueCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Notifications',
      onPressed: onPressed,
      icon: SizedBox(
        width: 42,
        height: 42,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: PelviColors.of(context).surfaceMuted,
                shape: BoxShape.circle,
                border: Border.all(color: PelviColors.of(context).border),
              ),
              child: Icon(
                Icons.notifications_none_outlined,
                size: 20,
                color: PelviColors.of(context).inkMuted,
              ),
            ),
            if (dueCount > 0)
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: PelviColors.of(context).purple700,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
