import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/auth.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/org.dart';
import '../../data/org_directory.dart';
import '../../data/sync.dart';
import '../../theme/theme.dart';
import '../../widgets/show_snack.dart';

/// Paste an invite, or send one. Not an admin console.
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
  final _code = TextEditingController();
  final _email = TextEditingController();
  final _orgId = TextEditingController();
  final _clinicName = TextEditingController();
  String _kind = 'create-org';
  String _role = 'practitioner';
  bool _busy = false;
  bool _canSend = false;
  bool _platformAdmin = false;
  bool _grantOwner = false;
  String? _issuedCode;
  StreamSubscription<String?>? _orgSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAccess());
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

  @override
  void dispose() {
    _orgSub?.cancel();
    _code.dispose();
    _email.dispose();
    _orgId.dispose();
    _clinicName.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    final user = NotesAuth.currentUser;
    if (user == null) return;
    setState(() => _busy = true);
    try {
      final directory = OrgDirectory();
      final preview = await directory.peekInvite(_code.text);
      String? clinicName;
      if (preview['kind'] == 'create-org') {
        if (!mounted) return;
        clinicName = await _askClinicName();
        if (clinicName == null) return;
      }
      final orgId = await directory.acceptInvite(
        user: user,
        inviteId: _code.text,
        clinicName: clinicName,
      );
      if (!mounted) return;
      final db = AppDatabaseProvider.of(context);
      final sync = AppDatabaseProvider.syncOf(context);
      final roles = preview['kind'] == 'create-org'
          ? 'owner,practitioner'
          : (preview['role'] as String? ?? 'practitioner');
      await db.setSetting(AppDatabase.activeOrgIdKey, orgId);
      await db.setSetting(AppDatabase.activeOrgRolesKey, roles);
      if (clinicName != null) await db.setPractitionerName(clinicName);
      await sync.syncNow();
      if (!mounted) return;
      widget.onJoined?.call();
      if (!widget.waiting) Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) showPelviSnackBar(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
      final id = await OrgDirectory().createInvite(
        user: user,
        email: _email.text,
        kind: _kind,
        orgId: _kind == 'join' ? _orgId.text.trim() : null,
        role: _kind == 'join' ? _role : null,
        issuedByPlatformAdmin: _platformAdmin,
      );
      if (!mounted) return;
      setState(() => _issuedCode = id);
    } catch (e) {
      if (mounted) showPelviSnackBar(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke() async {
    setState(() => _busy = true);
    try {
      await OrgDirectory().revokeInvite(inviteId: _code.text);
      if (mounted) showPelviSnackBar(context, 'Invite revoked');
    } catch (e) {
      if (mounted) showPelviSnackBar(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final email = NotesAuth.currentUser?.email;

    return Scaffold(
      appBar: widget.waiting ? null : AppBar(title: const Text('Invites')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(PelviSpace.lg),
          children: [
            if (widget.waiting) ...[
              Text(
                'Waiting for a clinic',
                textAlign: TextAlign.center,
                style: text.titleLarge,
              ),
              const SizedBox(height: PelviSpace.sm),
              Text(
                email == null
                    ? 'Sign-in does not create a clinic. Paste an invite code.'
                    : 'Signed in as $email. Paste an invite code to join or create a clinic.',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                  color: PelviColors.of(context).inkMuted,
                ),
              ),
              const SizedBox(height: PelviSpace.md),
              const _SyncLine(),
              const SizedBox(height: PelviSpace.lg),
            ],
            if (!widget.waiting && !_canSend)
              Text(
                'An owner sends invites for this clinic.',
                style: text.bodyMedium?.copyWith(
                  color: PelviColors.of(context).inkMuted,
                ),
              ),
            if (widget.waiting || _canSend) ...[
              Text('INVITE CODE', style: text.labelMedium),
              const SizedBox(height: PelviSpace.xs),
              TextField(
                controller: _code,
                decoration: const InputDecoration(hintText: 'Paste code'),
              ),
            ],
            if (widget.waiting) ...[
              const SizedBox(height: PelviSpace.md),
              FilledButton(
                onPressed: _busy ? null : _accept,
                child: const Text('Accept invite'),
              ),
            ],
            if (_canSend) ...[
              const SizedBox(height: PelviSpace.sm),
              TextButton(
                onPressed: _busy ? null : _revoke,
                child: const Text('Revoke unused invite'),
              ),
              const SizedBox(height: PelviSpace.lg),
              Text('Send an invite', style: text.titleMedium),
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
                child: const Text('Create invite'),
              ),
              if (_issuedCode != null) ...[
                const SizedBox(height: PelviSpace.md),
                SelectableText(_issuedCode!),
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _issuedCode!));
                    showPelviSnackBar(context, 'Code copied');
                  },
                  child: const Text('Copy code'),
                ),
              ],
            ],
          ],
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
