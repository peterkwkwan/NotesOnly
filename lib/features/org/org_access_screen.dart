import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/auth.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/join_token.dart';
import '../../data/org.dart';
import '../../data/org_directory.dart';
import '../../data/sync.dart';
import '../../theme/theme.dart';
import '../../widgets/show_snack.dart';
import '../shell/desktop_chrome.dart';

/// Waiting for clinic (magic-link join) or platform-admin invite tools.
class OrgAccessScreen extends StatefulWidget {
  const OrgAccessScreen({super.key, this.waiting = false, this.onJoined});

  /// Signed in, no clinic yet.
  final bool waiting;

  /// Fired when an invite is accepted or sync binds a clinic.
  final VoidCallback? onJoined;

  @override
  State<OrgAccessScreen> createState() => _OrgAccessScreenState();
}

class _OrgAccessScreenState extends State<OrgAccessScreen> {
  final _email = TextEditingController();
  final _orgId = TextEditingController();
  final _clinicName = TextEditingController();
  String _kind = 'create-org';
  String _role = 'practitioner';
  bool _busy = false;
  bool _joining = false;
  bool _canSend = false;
  bool _platformAdmin = false;
  bool _grantOwner = false;
  String? _issuedJoinUrl;
  String? _joinError;
  StreamSubscription<String?>? _orgSub;
  bool _joinAttempted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAccess();
      // App-level accept runs on auth; retry here if still waiting with a token.
      if (widget.waiting) _tryJoinFromToken();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.waiting || _orgSub != null) return;
    _orgSub = AppDatabaseProvider.of(context)
        .watchSetting(AppDatabase.activeOrgIdKey)
        .listen((id) {
      if (id != null && id.isNotEmpty) widget.onJoined?.call();
    });
  }

  Future<void> _loadAccess() async {
    if (!mounted) return;
    final db = AppDatabaseProvider.of(context);
    final roles = parseOrgRoles(await db.getSetting(AppDatabase.activeOrgRolesKey));
    final orgId = await db.getSetting(AppDatabase.activeOrgIdKey);
    final email = NotesAuth.currentUser?.email;
    if (!mounted) return;
    final grantOwner =
        isPlatformAdminEmail(email) || roles.contains(OrgRole.owner);
    setState(() {
      _platformAdmin = isPlatformAdminEmail(email);
      _grantOwner = grantOwner;
      _canSend = grantOwner || roles.contains(OrgRole.admin);
      if (!_platformAdmin) _kind = 'join';
      if (!grantOwner) _role = 'practitioner';
      if (orgId != null && orgId.isNotEmpty) _orgId.text = orgId;
    });
  }

  Future<void> _tryJoinFromToken() async {
    if (_joinAttempted || !widget.waiting) return;
    final token = captureJoinTokenFromUri();
    if (token == null || token.isEmpty) return;
    _joinAttempted = true;
    final user = NotesAuth.currentUser;
    if (user == null) return;

    setState(() {
      _joining = true;
      _joinError = null;
    });
    try {
      final directory = OrgDirectory();
      String? clinicName;
      // create-org invites need a clinic name; probe via accept error is messy —
      // ask only when the callable says so.
      AcceptedInvite accepted;
      try {
        accepted = await directory.acceptInviteToken(token: token);
      } catch (e) {
        final msg = '$e';
        if (msg.contains('Name the clinic')) {
          if (!mounted) return;
          clinicName = await _askClinicName();
          if (clinicName == null) {
            setState(() {
              _joining = false;
              _joinError = 'Name the clinic to finish this invite.';
            });
            return;
          }
          accepted = await directory.acceptInviteToken(
            token: token,
            clinicName: clinicName,
          );
        } else {
          rethrow;
        }
      }
      if (!mounted) return;
      final db = AppDatabaseProvider.of(context);
      final sync = AppDatabaseProvider.syncOf(context);
      await db.setSetting(AppDatabase.activeOrgIdKey, accepted.orgId);
      await db.setSetting(
        AppDatabase.activeOrgRolesKey,
        accepted.roles.join(','),
      );
      if (clinicName != null) await db.setClinicName(clinicName);
      clearPendingJoinToken();
      replaceJoinUrlWithHome();
      await sync.syncNow();
      if (!mounted) return;
      widget.onJoined?.call();
    } catch (e) {
      if (!mounted) return;
      final msg = '$e';
      // Keep token only for wrong-account so sign-out/in can retry.
      // Drop stale/rotated/revoked tokens so sessionStorage cannot keep
      // retrying an old hash while Members Pending shows a newer invite.
      if (!_isWrongAccountJoinError(msg)) {
        clearPendingJoinToken();
        replaceJoinUrlWithHome();
      }
      setState(() {
        _joinError = _friendlyJoinError(e);
        _joining = false;
      });
    }
  }

  bool _isWrongAccountJoinError(String s) =>
      s.contains('different Google account');

  String _friendlyJoinError(Object e) {
    final s = '$e';
    if (_isWrongAccountJoinError(s)) {
      return 'This invite is for a different Google account. '
          'Sign out and sign in with the invited email.';
    }
    if (s.contains('replaced')) {
      return 'This invite link has been replaced. '
          'Open the latest invite link from your email.';
    }
    if (s.contains('expired')) return 'This invite has expired.';
    if (s.contains('revoked')) return 'This invite was revoked.';
    if (s.contains('already used')) return 'This invite was already used.';
    if (s.contains('not-found') || s.contains('Invite not found')) {
      return 'This invite link is invalid.';
    }
    return s;
  }

  @override
  void dispose() {
    _orgSub?.cancel();
    _email.dispose();
    _orgId.dispose();
    _clinicName.dispose();
    super.dispose();
  }

  Future<String?> _askClinicName() {
    _clinicName.clear();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name the clinic'),
        content: TextField(
          controller: _clinicName,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Clinic name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = _clinicName.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx, name);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final user = NotesAuth.currentUser;
    if (user == null) return;
    if (_kind == 'join' && _orgId.text.trim().isEmpty) {
      showPelviSnackBar(context, 'Enter the clinic id');
      return;
    }
    if (_email.text.trim().isEmpty) {
      showPelviSnackBar(context, 'Enter an email');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await OrgDirectory().createClinicInvite(
        email: _email.text,
        kind: _kind,
        orgId: _kind == 'join' ? _orgId.text.trim() : null,
        role: _kind == 'join' ? _role : null,
      );
      if (!mounted) return;
      setState(() => _issuedJoinUrl = result.joinUrl);
      if (result.joinUrl.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: result.joinUrl));
      }
      if (!mounted) return;
      showPelviSnackBar(
        context,
        result.emailed
            ? 'Invite sent to ${_email.text.trim().toLowerCase()}. Link copied.'
            : 'Invite created but email failed. Link copied — share it manually.',
      );
    } catch (e) {
      if (mounted) showPelviSnackBar(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AppDatabaseProvider.of(context).clearLocalClinicForAccountSwitch();
      await NotesAuth.signOut();
    } catch (e) {
      if (mounted) showPelviSnackBar(context, 'Sign out failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final email = NotesAuth.currentUser?.email;
    final maxFormWidth = widget.waiting && isDesktopShell(context)
        ? 380.0
        : double.infinity;
    final pendingToken = peekPendingJoinToken();

    final form = <Widget>[
      if (widget.waiting) ...[
        Text(
          'Waiting for a clinic',
          textAlign: TextAlign.center,
          style: text.titleLarge,
        ),
        const SizedBox(height: PelviSpace.sm),
        Text(
          email == null
              ? 'Sign-in does not create a clinic. Open the invite link from your email.'
              : pendingToken != null || _joining
                  ? 'Signed in as $email. Joining clinic…'
                  : 'Signed in as $email. Open the invite link from your email to join a clinic.',
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(
            color: PelviColors.of(context).inkMuted,
          ),
        ),
        const SizedBox(height: PelviSpace.md),
        const _SyncLine(),
        if (_joining) ...[
          const SizedBox(height: PelviSpace.lg),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: PelviSpace.sm),
          Text(
            'Joining…',
            textAlign: TextAlign.center,
            style: text.bodyMedium,
          ),
        ],
        if (_joinError != null) ...[
          const SizedBox(height: PelviSpace.md),
          Text(
            _joinError!,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(
              color: PelviColors.of(context).danger,
            ),
          ),
        ],
        const SizedBox(height: PelviSpace.lg),
        TextButton(
          onPressed: _busy || _joining ? null : _signOut,
          child: const Text('Sign out'),
        ),
      ],
      if (!widget.waiting && !_canSend)
        Text(
          'An owner sends invites for this clinic.',
          style: text.bodyMedium?.copyWith(
            color: PelviColors.of(context).inkMuted,
          ),
        ),
      if (!widget.waiting && _canSend) ...[
        Text('Send an invite', style: text.titleMedium),
        const SizedBox(height: PelviSpace.sm),
        Text(
          'Sends a magic link by email. No invite codes.',
          style: text.bodySmall?.copyWith(
            color: PelviColors.of(context).inkMuted,
          ),
        ),
        const SizedBox(height: PelviSpace.sm),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: 'Google account email'),
        ),
        if (_platformAdmin) ...[
          const SizedBox(height: PelviSpace.sm),
          DropdownButtonFormField<String>(
            initialValue: _kind,
            items: const [
              DropdownMenuItem(value: 'create-org', child: Text('Create a clinic')),
              DropdownMenuItem(value: 'join', child: Text('Join a clinic')),
            ],
            onChanged: _busy
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => _kind = value);
                  },
          ),
        ],
        if (_kind == 'join') ...[
          const SizedBox(height: PelviSpace.sm),
          TextField(
            controller: _orgId,
            decoration: const InputDecoration(hintText: 'Clinic id'),
          ),
          const SizedBox(height: PelviSpace.sm),
          DropdownButtonFormField<String>(
            initialValue: _role,
            items: [
              if (_grantOwner)
                const DropdownMenuItem(value: 'owner', child: Text('Owner')),
              const DropdownMenuItem(value: 'admin', child: Text('Admin')),
              const DropdownMenuItem(
                value: 'practitioner',
                child: Text('Practitioner'),
              ),
            ],
            onChanged: _busy
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => _role = value);
                  },
          ),
        ],
        const SizedBox(height: PelviSpace.md),
        FilledButton(
          onPressed: _busy ? null : _send,
          child: const Text('Send invite'),
        ),
        if (_issuedJoinUrl != null) ...[
          const SizedBox(height: PelviSpace.md),
          SelectableText(
            _issuedJoinUrl!,
            style: text.bodySmall,
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _issuedJoinUrl!));
              showPelviSnackBar(context, 'Link copied');
            },
            child: const Text('Copy link'),
          ),
        ],
      ],
    ];

    return Scaffold(
      appBar: widget.waiting ? null : AppBar(title: const Text('Invites')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxFormWidth),
            child: widget.waiting
                ? Padding(
                    padding: const EdgeInsets.all(PelviSpace.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(),
                        ...form,
                        const Spacer(),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(PelviSpace.lg),
                    children: form,
                  ),
          ),
        ),
      ),
    );
  }
}

class _SyncLine extends StatelessWidget {
  const _SyncLine();

  @override
  Widget build(BuildContext context) {
    final sync = AppDatabaseProvider.syncOf(context);
    return StreamBuilder<SyncStatus>(
      stream: sync.watchStatus(),
      builder: (context, snap) {
        final status = snap.data;
        if (status == SyncStatus.syncing) {
          return Text(
            'Checking your account…',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          );
        }
        if (status == SyncStatus.error && sync.lastError != null) {
          return Text(
            sync.lastError!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: PelviColors.of(context).danger,
                ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}
