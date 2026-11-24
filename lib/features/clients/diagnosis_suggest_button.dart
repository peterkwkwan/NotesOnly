import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/client_summary.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/diagnosis_propose.dart';
import '../../data/org.dart';
import '../../theme/theme.dart';

/// "Suggest from notes" — proposes diagnosis via Vertex, then confirm before write.
class DiagnosisSuggestButton extends StatefulWidget {
  const DiagnosisSuggestButton({
    super.key,
    required this.client,
    this.compact = false,
    this.onApplied,
  });

  final Client client;
  final bool compact;

  /// Called after Drift write succeeds (e.g. refresh UI).
  final VoidCallback? onApplied;

  @override
  State<DiagnosisSuggestButton> createState() => _DiagnosisSuggestButtonState();
}

class _DiagnosisSuggestButtonState extends State<DiagnosisSuggestButton> {
  final _api = DiagnosisProposeApi();
  bool _busy = false;
  bool _allowed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadAcl());
    });
  }

  Future<void> _loadAcl() async {
    final db = AppDatabaseProvider.of(context);
    final roles =
        parseOrgRoles(await db.getSetting(AppDatabase.activeOrgRolesKey));
    if (!mounted) return;
    setState(() {
      _allowed = canViewClientSummary(roles) &&
          !isAdminBlockedFromSummary(roles);
    });
  }

  Future<void> _onPressed() async {
    if (_busy) return;
    setState(() => _busy = true);
    final db = AppDatabaseProvider.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);

    final result = await proposeClientDiagnosis(
      db: db,
      client: widget.client,
      api: _api,
    );

    if (!mounted) return;

    if (result.error != null || result.proposal == null) {
      setState(() => _busy = false);
      final msg = switch (result.error) {
        'offline' => 'Connect to suggest diagnosis.',
        'admin_blocked' => 'Not available for Admin accounts.',
        'no_org' => 'Join a clinic to suggest diagnosis.',
        'signed_out' => 'Sign in to suggest diagnosis.',
        final other => other ?? 'Could not suggest diagnosis.',
      };
      messenger?.showSnackBar(SnackBar(content: Text(msg)));
      return;
    }

    final proposal = result.proposal!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DiagnosisConfirmDialog(proposal: proposal),
    );

    if (!mounted) return;
    if (confirmed != true) {
      setState(() => _busy = false);
      return;
    }

    final ok = await applyDiagnosisProposal(db, widget.client, proposal);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Could not save diagnosis.')),
      );
      return;
    }
    messenger?.showSnackBar(
      const SnackBar(content: Text('Diagnosis updated.')),
    );
    widget.onApplied?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) return const SizedBox.shrink();
    final c = PelviColors.of(context);
    final label = widget.compact ? 'Suggest diagnosis' : 'Suggest from notes';

    return TextButton.icon(
      onPressed: _busy ? null : () => unawaited(_onPressed()),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: _busy
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: c.purple700,
              ),
            )
          : Icon(Icons.auto_awesome, size: 16, color: c.purple700),
      label: Text(
        label,
        style: TextStyle(
          color: c.purple700,
          fontSize: widget.compact ? 12 : 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DiagnosisConfirmDialog extends StatelessWidget {
  const _DiagnosisConfirmDialog({required this.proposal});

  final DiagnosisProposal proposal;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final current = proposal.diagnosisCurrent.trim().isEmpty
        ? '(none)'
        : proposal.diagnosisCurrent;
    final past = proposal.diagnosisPast.trim().isEmpty
        ? '(none)'
        : proposal.diagnosisPast;

    return AlertDialog(
      title: const Text('Suggested diagnosis'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Review before saving to the chart.',
              style: TextStyle(fontSize: 13, color: c.inkMuted),
            ),
            const SizedBox(height: 16),
            Text(
              'CURRENT',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: c.inkMuted,
              ),
            ),
            const SizedBox(height: 6),
            Text(current, style: TextStyle(fontSize: 14, color: c.ink)),
            const SizedBox(height: 14),
            Text(
              'PAST',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: c.inkMuted,
              ),
            ),
            const SizedBox(height: 6),
            Text(past, style: TextStyle(fontSize: 14, color: c.ink)),
            if (proposal.caveats.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                proposal.caveats,
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: c.inkMuted,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'AI suggestion — not a clinical record until you confirm.',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: c.purple700.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: proposal.isEmpty
              ? null
              : () => Navigator.pop(context, true),
          child: const Text('Save to chart'),
        ),
      ],
    );
  }
}
