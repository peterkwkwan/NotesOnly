import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/auth.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/org.dart';
import '../../data/org_directory.dart';
import '../../theme/theme.dart';
import '../../widgets/show_snack.dart';

/// Clinic roster for the active org. Owners change roles. Owners and admins
/// invite and remove.
class PracticeMembersPanel extends StatefulWidget {
  const PracticeMembersPanel({super.key});

  @override
  State<PracticeMembersPanel> createState() => _PracticeMembersPanelState();
}

enum _MembersTab { active, pending }

class _PracticeMembersPanelState extends State<PracticeMembersPanel> {
  bool _loaded = false;
  bool _loading = false;
  bool _busy = false;
  String _orgId = '';
  String? _error;
  List<OrgRole> _actor = const [];
  List<OrgMember> _members = const [];
  List<OrgInvite> _pending = const [];
  OrgRole _inviteRole = OrgRole.practitioner;
  _MembersTab _tab = _MembersTab.active;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = AppDatabaseProvider.of(context);
      final orgId = (await db.getSetting(AppDatabase.activeOrgIdKey)) ?? '';
      final roles =
          parseOrgRoles(await db.getSetting(AppDatabase.activeOrgRolesKey));
      if (!mounted) return;
      if (orgId.isEmpty) {
        setState(() {
          _orgId = '';
          _actor = roles;
          _members = const [];
          _pending = const [];
          _loading = false;
        });
        return;
      }
      final directory = OrgDirectory();
      final members = await directory.listMembers(orgId);
      var pending = const <OrgInvite>[];
      if (canSendClinicInvite(roles)) {
        pending = await directory.listPendingInvites(orgId);
      }
      if (!mounted) return;
      final inviteRoles = clinicInviteRolesFor(roles);
      setState(() {
        _orgId = orgId;
        _actor = roles;
        _members = members;
        _pending = pending;
        if (!inviteRoles.contains(_inviteRole) && inviteRoles.isNotEmpty) {
          _inviteRole = inviteRoles.first;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load members: $e';
      });
    }
  }

  Future<void> _openInviteDialog() async {
    if (_busy) return;
    if (_orgId.isEmpty) {
      showPelviSnackBar(context, 'No clinic is active on this device.');
      return;
    }
    final inviteRoles = clinicInviteRolesFor(_actor);
    if (inviteRoles.isEmpty) return;

    final emailCtrl = TextEditingController();
    var role = inviteRoles.contains(_inviteRole)
        ? _inviteRole
        : inviteRoles.first;
    var sending = false;

    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = PelviColors.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> send() async {
              if (sending) return;
              final user = NotesAuth.currentUser;
              if (user == null) return;
              final emails = parseClinicInviteEmails(emailCtrl.text);
              if (emails.isEmpty) {
                showPelviSnackBar(ctx, 'Enter a Google account email');
                return;
              }
              final bad = emails.where((e) => !isClinicInviteEmail(e)).toList();
              if (bad.isNotEmpty) {
                showPelviSnackBar(
                  ctx,
                  'Invalid email: ${bad.first}',
                );
                return;
              }
              if (!canInviteWithRole(actor: _actor, role: role)) {
                showPelviSnackBar(ctx, 'You cannot invite with that role');
                return;
              }
              setLocal(() => sending = true);
              try {
                final ids = <String>[];
                for (final email in emails) {
                  final id = await OrgDirectory().createInvite(
                    user: user,
                    email: email,
                    kind: 'join',
                    orgId: _orgId,
                    role: role.name,
                    issuedByPlatformAdmin: false,
                  );
                  ids.add(id);
                }
                if (!ctx.mounted) return;
                await Clipboard.setData(
                  ClipboardData(text: ids.join('\n')),
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx, true);
                if (!mounted) return;
                setState(() {
                  _inviteRole = role;
                  _tab = _MembersTab.pending;
                });
                showPelviSnackBar(
                  context,
                  ids.length == 1
                      ? 'Invite created. Code copied.'
                      : '${ids.length} invites created. Codes copied.',
                );
                await _reload();
              } catch (e) {
                if (ctx.mounted) {
                  showPelviSnackBar(ctx, 'Could not send invite: $e');
                }
              } finally {
                if (ctx.mounted) setLocal(() => sending = false);
              }
            }

            return AlertDialog(
              title: const Text('Send invite'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Google account email',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: c.ink,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 7),
                    TextField(
                      controller: emailCtrl,
                      enabled: !sending,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        hintText: 'friend@gmail.com; other@gmail.com',
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'They must sign in with this Google email. Separate multiple with semicolons.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: c.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Role on invite',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: c.ink,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final r in inviteRoles)
                          _RoleChip(
                            label: orgRoleLabel(r),
                            selected: role == r,
                            onTap: sending
                                ? null
                                : () => setLocal(() => role = r),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Admins can invite Practitioner or Admin only — not Owner.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: c.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: sending ? null : () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: sending ? null : send,
                  child: const Text('Send invite'),
                ),
              ],
            );
          },
        );
      },
    );
    emailCtrl.dispose();
    if (sent != true || !mounted) return;
  }

  Future<void> _copyInvite(OrgInvite invite) async {
    await Clipboard.setData(ClipboardData(text: invite.id));
    if (mounted) showPelviSnackBar(context, 'Code copied');
  }

  Future<void> _revokeInvite(OrgInvite invite) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await OrgDirectory().revokeInvite(inviteId: invite.id);
      if (!mounted) return;
      showPelviSnackBar(context, 'Invite revoked');
      await _reload();
    } catch (e) {
      if (mounted) showPelviSnackBar(context, 'Could not revoke invite: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeRole(OrgMember member) async {
    if (_busy) return;
    final owners = activeOwnerCount(_members);
    final next = await _askRoles(member, owners);
    if (next == null || !mounted) return;
    if (joinOrgRoles(next) == joinOrgRoles(member.roles)) return;
    if (!canSetMemberRoles(
      actor: _actor,
      target: member,
      nextRoles: next,
      owners: owners,
    )) {
      showPelviSnackBar(context, 'The last owner stays an owner');
      return;
    }
    setState(() => _busy = true);
    try {
      await OrgDirectory().setMemberRoles(
        orgId: _orgId,
        uid: member.uid,
        roles: next,
      );
      if (!mounted) return;
      if (member.uid == NotesAuth.currentUser?.uid) {
        await AppDatabaseProvider.of(context).setSetting(
          AppDatabase.activeOrgRolesKey,
          joinOrgRoles(next),
        );
      }
      if (!mounted) return;
      showPelviSnackBar(context, 'Role updated');
      await _reload();
    } catch (e) {
      if (mounted) showPelviSnackBar(context, 'Could not update role: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(OrgMember member) async {
    if (_busy) return;
    final owners = activeOwnerCount(_members);
    if (!canRemoveMember(actor: _actor, target: member, owners: owners)) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member'),
        content: Text(
          '${memberLabel(member)} loses access. Past appointments stay on the clinic.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await OrgDirectory().deactivateMember(orgId: _orgId, uid: member.uid);
      if (!mounted) return;
      showPelviSnackBar(context, 'Member removed');
      await _reload();
    } catch (e) {
      if (mounted) showPelviSnackBar(context, 'Could not remove member: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<OrgRole>?> _askRoles(OrgMember member, int owners) {
    var selected = {...member.roles};
    final lastOwner = member.roles.contains(OrgRole.owner) && owners <= 1;
    return showDialog<List<OrgRole>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final next = normalizeOrgRoles(selected);
            final allowed = canSetMemberRoles(
              actor: _actor,
              target: member,
              nextRoles: next,
              owners: owners,
            );
            final c = PelviColors.of(ctx);
            return AlertDialog(
              title: Text(memberLabel(member)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final role in OrgRole.values)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: selected.contains(role),
                      title: Text(orgRoleLabel(role)),
                      onChanged: role == OrgRole.owner && lastOwner
                          ? null
                          : (value) {
                              setLocal(() {
                                if (value == true) {
                                  selected.add(role);
                                } else {
                                  selected.remove(role);
                                }
                              });
                            },
                    ),
                  if (lastOwner)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'The last owner stays an owner.',
                        style: TextStyle(fontSize: 12, color: c.inkMuted),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed:
                      allowed ? () => Navigator.pop(ctx, next) : null,
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    if (_loading && _members.isEmpty && _error == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_orgId.isEmpty && _error == null) {
      return Text(
        'No clinic is active on this device.',
        style: TextStyle(fontSize: 12, height: 1.5, color: c.inkMuted),
      );
    }
    if (_error != null && _members.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _error!,
            style: TextStyle(fontSize: 12, height: 1.5, color: c.danger),
          ),
          TextButton(onPressed: _reload, child: const Text('Retry')),
        ],
      );
    }

    final owners = activeOwnerCount(_members);
    final canEditRoles = _actor.contains(OrgRole.owner);
    final canInvite = canSendClinicInvite(_actor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'Owners set roles. Owners and admins can invite and remove someone. The last owner stays.',
                style: TextStyle(fontSize: 11, height: 1.5, color: c.inkMuted),
              ),
            ),
            if (canInvite) ...[
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _busy ? null : _openInviteDialog,
                child: const Text('Invite'),
              ),
            ],
          ],
        ),
        if (canInvite) ...[
          const SizedBox(height: 18),
          _MembersTabBar(
            tab: _tab,
            onChanged: (tab) => setState(() => _tab = tab),
          ),
          const SizedBox(height: 14),
          if (_tab == _MembersTab.pending)
            _PendingList(
              pending: _pending,
              busy: _busy,
              onCopy: _copyInvite,
              onRevoke: _revokeInvite,
            )
          else
            _ActiveMembersList(
              members: _members,
              actor: _actor,
              owners: owners,
              canEditRoles: canEditRoles,
              busy: _busy,
              onChange: _changeRole,
              onRemove: _remove,
            ),
        ] else ...[
          const SizedBox(height: 14),
          _ActiveMembersList(
            members: _members,
            actor: _actor,
            owners: owners,
            canEditRoles: canEditRoles,
            busy: _busy,
            onChange: _changeRole,
            onRemove: _remove,
          ),
        ],
      ],
    );
  }
}

class _MembersTabBar extends StatelessWidget {
  const _MembersTabBar({
    required this.tab,
    required this.onChanged,
  });

  final _MembersTab tab;
  final ValueChanged<_MembersTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          _MembersTabButton(
            label: 'Active members',
            selected: tab == _MembersTab.active,
            onTap: () => onChanged(_MembersTab.active),
          ),
          const SizedBox(width: 18),
          _MembersTabButton(
            label: 'Pending',
            selected: tab == _MembersTab.pending,
            onTap: () => onChanged(_MembersTab.pending),
          ),
        ],
      ),
    );
  }
}

class _MembersTabButton extends StatelessWidget {
  const _MembersTabButton({
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
    return InkWell(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? c.pink700 : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              height: 20 / 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? c.pink700 : c.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveMembersList extends StatelessWidget {
  const _ActiveMembersList({
    required this.members,
    required this.actor,
    required this.owners,
    required this.canEditRoles,
    required this.busy,
    required this.onChange,
    required this.onRemove,
  });

  final List<OrgMember> members;
  final List<OrgRole> actor;
  final int owners;
  final bool canEditRoles;
  final bool busy;
  final ValueChanged<OrgMember> onChange;
  final ValueChanged<OrgMember> onRemove;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    if (members.isEmpty) {
      return Text(
        'No members yet.',
        style: TextStyle(fontSize: 13, color: c.ink),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < members.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: c.border),
            const SizedBox(height: 12),
          ],
          _MemberRow(
            member: members[i],
            canChange: canEditRoles && members[i].active && !busy,
            canRemove: canRemoveMember(
                  actor: actor,
                  target: members[i],
                  owners: owners,
                ) &&
                !busy,
            onChange: () => onChange(members[i]),
            onRemove: () => onRemove(members[i]),
          ),
        ],
      ],
    );
  }
}

class _PendingList extends StatelessWidget {
  const _PendingList({
    required this.pending,
    required this.busy,
    required this.onCopy,
    required this.onRevoke,
  });

  final List<OrgInvite> pending;
  final bool busy;
  final ValueChanged<OrgInvite> onCopy;
  final ValueChanged<OrgInvite> onRevoke;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    if (pending.isEmpty) {
      return Text(
        'No pending invites.',
        style: TextStyle(fontSize: 13, color: c.inkMuted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < pending.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _PendingRow(
            invite: pending[i],
            busy: busy,
            onCopy: () => onCopy(pending[i]),
            onRevoke: () => onRevoke(pending[i]),
          ),
        ],
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    return Material(
      color: selected ? c.pink50 : c.surface,
      borderRadius: BorderRadius.circular(PelviRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PelviRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PelviRadius.sm),
            border: Border.all(color: selected ? c.pink700 : c.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? c.pink700 : c.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({
    required this.invite,
    required this.busy,
    required this.onCopy,
    required this.onRevoke,
  });

  final OrgInvite invite;
  final bool busy;
  final VoidCallback onCopy;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final role = invite.role == null ? 'Invite' : orgRoleLabel(invite.role!);
    final days = invite.expiresAt.difference(DateTime.now().toUtc()).inDays;
    final expiry = days <= 0
        ? 'expires today'
        : 'expires in ${days == 1 ? '1 day' : '$days days'}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                invite.email.isEmpty ? invite.id : invite.email,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: c.ink,
                  height: 1.5,
                ),
              ),
              Text(
                '$role · $expiry',
                style: TextStyle(fontSize: 11, height: 1.5, color: c.inkMuted),
              ),
            ],
          ),
        ),
        _RowAction(
          label: 'Copy code',
          color: c.pink700,
          onTap: busy ? null : onCopy,
        ),
        const SizedBox(width: 12),
        _RowAction(
          label: 'Revoke',
          color: c.danger,
          onTap: busy ? null : onRevoke,
        ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.canChange,
    required this.canRemove,
    required this.onChange,
    required this.onRemove,
  });

  final OrgMember member;
  final bool canChange;
  final bool canRemove;
  final VoidCallback onChange;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final roles = member.roles.map(orgRoleLabel).join(', ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                memberLabel(member),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: c.ink,
                  height: 1.5,
                ),
              ),
              Text(
                member.active ? (roles.isEmpty ? 'Member' : roles) : 'Removed',
                style: TextStyle(fontSize: 11, height: 1.5, color: c.inkMuted),
              ),
            ],
          ),
        ),
        if (canChange)
          _RowAction(label: 'Change role', color: c.pink700, onTap: onChange),
        if (canRemove) ...[
          const SizedBox(width: 12),
          _RowAction(label: 'Remove', color: c.danger, onTap: onRemove),
        ],
      ],
    );
  }
}

class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PelviRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: onTap == null ? color.withValues(alpha: 0.4) : color,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
