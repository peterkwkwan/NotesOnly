import 'package:flutter/material.dart';

import '../../data/auth.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/org.dart';
import '../../data/org_directory.dart';
import '../../theme/theme.dart';
import '../../widgets/show_snack.dart';

/// Clinic roster for the active org. Owners change roles. Owners and admins remove.
class PracticeMembersPanel extends StatefulWidget {
  const PracticeMembersPanel({super.key});

  @override
  State<PracticeMembersPanel> createState() => _PracticeMembersPanelState();
}

class _PracticeMembersPanelState extends State<PracticeMembersPanel> {
  bool _loaded = false;
  bool _loading = false;
  bool _busy = false;
  String _orgId = '';
  String? _error;
  List<OrgRole> _actor = const [];
  List<OrgMember> _members = const [];

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
          _loading = false;
        });
        return;
      }
      final members = await OrgDirectory().listMembers(orgId);
      if (!mounted) return;
      setState(() {
        _orgId = orgId;
        _actor = roles;
        _members = members;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Owners set roles. Owners and admins can remove someone. The last owner stays.',
          style: TextStyle(fontSize: 11, height: 1.5, color: c.inkMuted),
        ),
        const SizedBox(height: 14),
        if (_members.isEmpty)
          Text(
            'No members yet.',
            style: TextStyle(fontSize: 13, color: c.ink),
          ),
        for (var i = 0; i < _members.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: c.border),
            const SizedBox(height: 12),
          ],
          _MemberRow(
            member: _members[i],
            canChange: canEditRoles &&
                _members[i].active &&
                !_busy,
            canRemove: canRemoveMember(
              actor: _actor,
              target: _members[i],
              owners: owners,
            ) &&
                !_busy,
            onChange: () => _changeRole(_members[i]),
            onRemove: () => _remove(_members[i]),
          ),
        ],
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
  final VoidCallback onTap;

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
            color: color,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
