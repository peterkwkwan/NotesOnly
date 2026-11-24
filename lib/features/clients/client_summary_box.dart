import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/client_summary.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/org.dart';
import '../../theme/theme.dart';

/// Purple Client Summary panel shared by mobile + web profiles.
class ClientSummaryBox extends StatefulWidget {
  const ClientSummaryBox({
    super.key,
    required this.client,
    this.compact = false,
  });

  final Client client;

  /// Web uses slightly tighter type; mobile keeps profile body styles.
  final bool compact;

  @override
  State<ClientSummaryBox> createState() => _ClientSummaryBoxState();
}

class _ClientSummaryBoxState extends State<ClientSummaryBox> {
  final _api = ClientSummaryApi();
  bool _loading = true;
  bool _regenerating = false;
  ClientSummaryCache? _cache;
  String? _statusHint;
  bool _adminBlocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  void didUpdateWidget(covariant ClientSummaryBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client.id != widget.client.id ||
        oldWidget.client.diagnosisCurrent != widget.client.diagnosisCurrent ||
        oldWidget.client.diagnosisPast != widget.client.diagnosisPast ||
        oldWidget.client.updatedAt != widget.client.updatedAt) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh({bool force = false}) async {
    final db = AppDatabaseProvider.of(context);
    final roles =
        parseOrgRoles(await db.getSetting(AppDatabase.activeOrgRolesKey));
    if (isAdminBlockedFromSummary(roles)) {
      if (!mounted) return;
      setState(() {
        _adminBlocked = true;
        _loading = false;
        _regenerating = false;
        _cache = null;
        _statusHint = null;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _adminBlocked = false;
      if (force) {
        _regenerating = true;
      } else {
        _loading = true;
      }
      _statusHint = null;
    });

    final result = await ensureClientSummary(
      db: db,
      client: widget.client,
      api: _api,
      force: force,
    );

    if (!mounted) return;
    setState(() {
      _loading = false;
      _regenerating = false;
      _cache = result.cache;
      _statusHint = switch (result.error) {
        null => null,
        'offline' => 'Connect to generate a summary.',
        'offline_stale' => 'Showing last summary — connect to refresh.',
        'admin_blocked' => null,
        'no_org' => 'Join a clinic to generate summaries.',
        'signed_out' => 'Sign in to generate a summary.',
        final other => other,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final text = Theme.of(context).textTheme;
    final titleSize = widget.compact ? 11.0 : null;
    final bodySize = widget.compact ? 12.0 : 13.0;
    final bodyHeight = widget.compact ? 1.5 : 1.65;

    Widget body;
    if (_adminBlocked) {
      body = Text(
        'AI summary is not available for Admin accounts.',
        style: text.bodyMedium?.copyWith(
          color: c.purple700,
          fontSize: bodySize,
          height: bodyHeight,
        ),
      );
    } else if (_loading && _cache == null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: c.purple700,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Generating summary…',
              style: text.bodyMedium?.copyWith(
                color: c.purple700,
                fontSize: bodySize,
                height: bodyHeight,
              ),
            ),
          ],
        ),
      );
    } else {
      final summary = _cache?.summary.trim();
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (summary == null || summary.isEmpty)
                ? 'No summary yet.'
                : summary,
            style: text.bodyMedium?.copyWith(
              color: c.purple700,
              fontSize: bodySize,
              height: bodyHeight,
            ),
          ),
          if (_statusHint != null) ...[
            const SizedBox(height: 8),
            Text(
              _statusHint!,
              style: text.bodySmall?.copyWith(
                color: c.purple700.withValues(alpha: 0.85),
                fontSize: widget.compact ? 11 : 12,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'AI-generated — not a clinical record.',
            style: text.bodySmall?.copyWith(
              color: c.purple700.withValues(alpha: 0.75),
              fontSize: widget.compact ? 10 : 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome, size: 13, color: c.purple700),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'CLIENT SUMMARY',
                style: (titleSize != null
                        ? TextStyle(
                            fontSize: titleSize,
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                            color: c.purple700,
                          )
                        : text.labelMedium?.copyWith(color: c.purple700)),
              ),
            ),
            if (!_adminBlocked)
              IconButton(
                tooltip: 'Regenerate',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: _regenerating || _loading
                    ? null
                    : () => unawaited(_refresh(force: true)),
                icon: _regenerating
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: c.purple700,
                        ),
                      )
                    : Icon(Icons.refresh, size: 18, color: c.purple700),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(widget.compact ? 20 : PelviSpace.md),
          decoration: BoxDecoration(
            color: c.purple50,
            borderRadius: BorderRadius.circular(PelviRadius.md),
          ),
          child: body,
        ),
      ],
    );
  }
}
