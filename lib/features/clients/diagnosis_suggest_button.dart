import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/client_summary.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/diagnosis_propose.dart';
import '../../data/org.dart';
import '../../theme/theme.dart';

/// "Suggest from notes" — ranked major diagnoses as pills; pick one before write.
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
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => _DiagnosisPickDialog(proposal: proposal),
    );

    if (!mounted) return;
    final pick = selected?.trim() ?? '';
    if (pick.isEmpty) {
      setState(() => _busy = false);
      return;
    }

    final ok = await applySelectedDiagnosis(db, widget.client, pick);
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

class _DiagnosisPickDialog extends StatefulWidget {
  const _DiagnosisPickDialog({required this.proposal});

  final DiagnosisProposal proposal;

  @override
  State<_DiagnosisPickDialog> createState() => _DiagnosisPickDialogState();
}

class _DiagnosisPickDialogState extends State<_DiagnosisPickDialog> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final labels = widget.proposal.majorDiagnoses;

    return AlertDialog(
      title: const Text('Suggested diagnosis'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              labels.isEmpty
                  ? 'No major diagnoses to pick from.'
                  : 'Pick one major diagnosis for Diagnosis (current).',
              style: TextStyle(fontSize: 13, color: c.inkMuted),
            ),
            if (labels.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: PelviSpace.sm,
                runSpacing: PelviSpace.sm,
                children: [
                  for (final label in labels)
                    _DiagnosisPill(
                      label: label,
                      selected: _selected == label,
                      onTap: () => setState(() => _selected = label),
                    ),
                ],
              ),
            ],
            if (widget.proposal.caveats.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                widget.proposal.caveats,
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
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.pop(context, _selected),
          child: const Text('Save to chart'),
        ),
      ],
    );
  }
}

class _DiagnosisPill extends StatelessWidget {
  const _DiagnosisPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Material(
      color: selected ? c.pink50 : c.surface,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? c.pink700 : c.border),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? c.pink700 : c.ink,
            ),
          ),
        ),
      ),
    );
  }
}
