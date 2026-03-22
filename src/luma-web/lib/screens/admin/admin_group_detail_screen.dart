import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/group.dart';
import '../../models/custom_role.dart';
import '../../models/user.dart';
import '../../services/user_service.dart';
import '../../theme/tokens.dart';

class AdminGroupDetailScreen extends StatefulWidget {
  final UserService userService;
  final GroupRecord? group;

  const AdminGroupDetailScreen({
    super.key,
    required this.userService,
    this.group,
  });

  @override
  State<AdminGroupDetailScreen> createState() => _AdminGroupDetailScreenState();
}

class _AdminGroupDetailScreenState extends State<AdminGroupDetailScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  GroupRecord? _detail;
  List<AdminUserRecord>? _allUsers;
  List<GroupRecord>? _allGroups;
  List<CustomRoleRecord>? _allRoles;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.group == null) {
      _nameCtrl = TextEditingController();
      _descCtrl = TextEditingController();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) { context.go('/admin/groups'); }
      });
      return;
    }
    _nameCtrl = TextEditingController(text: widget.group!.name);
    _descCtrl = TextEditingController(text: widget.group!.description ?? '');
    _loadDetail();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    if (widget.group == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.userService.getGroup(widget.group!.id),
        widget.userService.listAdminUsers(),
        widget.userService.listGroups(),
        widget.userService.listCustomRoles(),
      ]);
      if (mounted) {
        final detail = results[0] as GroupRecord;
        setState(() {
          _detail = detail;
          _nameCtrl.text = detail.name;
          _descCtrl.text = detail.description ?? '';
          _allUsers = results[1] as List<AdminUserRecord>;
          _allGroups = (results[2] as List<GroupRecord>)
              .where((g) => g.id != widget.group!.id)
              .toList();
          _allRoles = results[3] as List<CustomRoleRecord>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load group details. Please try again.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _rename() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    final desc = _descCtrl.text.trim();
    try {
      await widget.userService.renameGroup(
        widget.group!.id,
        _nameCtrl.text.trim(),
        description: desc.isEmpty ? null : desc,
        clearDescription: desc.isEmpty,
      );
      await _loadDetail();
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete group'),
        content: const Text('Are you sure? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.userService.deleteGroup(widget.group!.id);
      if (mounted) context.go('/admin/groups');
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  void _showError(String msg) {
    final display = msg.replaceFirst('Exception: ', '');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          display.isEmpty ? 'Something went wrong. Please try again.' : display),
      backgroundColor: Theme.of(context).colorScheme.error,
    ));
  }

  Future<void> _addUserMember(String userId) async {
    try {
      await widget.userService
          .addGroupMember(widget.group!.id, 'user', userId);
      await _loadDetail();
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  Future<void> _addGroupMember(String groupId) async {
    try {
      await widget.userService
          .addGroupMember(widget.group!.id, 'group', groupId);
      await _loadDetail();
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  Future<void> _removeMember(GroupMemberRecord m) async {
    final label = _memberLabel(m);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text('Remove "$label" from this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.userService
          .removeGroupMember(widget.group!.id, m.memberType, m.memberId);
      await _loadDetail();
    } catch (e) {
      if (mounted) _showError('Could not remove member. Please try again.');
    }
  }

  Future<void> _assignRole(String roleId) async {
    try {
      await widget.userService
          .assignRoleToGroup(widget.group!.id, roleId);
      await _loadDetail();
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  Future<void> _removeRole(String roleId) async {
    try {
      await widget.userService
          .removeRoleFromGroup(widget.group!.id, roleId);
      await _loadDetail();
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  String _memberLabel(GroupMemberRecord m) {
    if (m.memberType == 'user') {
      final u = _allUsers?.where((u) => u.id == m.memberId).firstOrNull;
      return u?.displayName ?? m.memberId;
    } else {
      final allG = (_allGroups ?? []) + [widget.group!];
      final found = allG.where((g) => g.id == m.memberId).firstOrNull;
      return found?.name ?? m.memberId;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.group == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final detail = _detail;
    final isSystem = detail?.isSystem ?? false;
    final noMemberControl = detail?.noMemberControl ?? false;
    final canDelete = (detail?.memberCount ?? 1) == 0 && !isSystem;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/admin/groups')),
        title: Text(widget.group!.name),
        actions: [
          if (isSystem)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _SystemBadge(),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!,
                          style: TextStyle(color: colorScheme.error)),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: _loadDetail,
                          child: const Text('Retry')),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Name + Description ───────────────────────
                          Text('Name',
                              style: Theme.of(context).textTheme.labelLarge),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _nameCtrl,
                                  enabled: !isSystem,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                  onPressed: isSystem ? null : _rename,
                                  child: const Text('Save')),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _descCtrl,
                            enabled: !isSystem,
                            decoration: const InputDecoration(
                              labelText: 'Description (optional)',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.group!.id,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant
                                      .withAlpha(100),
                                  fontFamily: 'monospace',
                                ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: canDelete ? _delete : null,
                            icon: const Icon(Icons.delete_outline, size: 16),
                            label: Text(isSystem
                                ? 'Cannot delete (system group)'
                                : canDelete
                                    ? 'Delete group'
                                    : 'Cannot delete (has members)'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  canDelete ? colorScheme.error : null,
                            ),
                          ),

                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Hide from directory search'),
                            subtitle: const Text(
                              'When enabled, this group will not appear in search results for non-admin users.',
                            ),
                            value: detail?.hideFromSearch ?? false,
                            onChanged: isSystem
                                ? null
                                : (hide) async {
                                    try {
                                      await widget.userService
                                          .setGroupHideFromSearch(widget.group!.id, hide: hide);
                                      await _loadDetail();
                                    } catch (e) {
                                      if (mounted) _showError(e.toString());
                                    }
                                  },
                          ),

                          const Divider(height: 40),

                          // ── Members ──────────────────────────────────
                          Text('Members',
                              style: Theme.of(context).textTheme.labelLarge),
                          const SizedBox(height: 8),
                          if (noMemberControl)
                            Text(
                              'Membership is managed automatically by the system.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: colorScheme.onSurfaceVariant),
                            )
                          else if (detail!.members.isEmpty)
                            const Text('No members')
                          else
                            ...detail.members.map((m) => ListTile(
                                  dense: true,
                                  leading: Icon(
                                    m.memberType == 'user'
                                        ? Icons.person_outline
                                        : Icons.group_outlined,
                                    size: 20,
                                  ),
                                  title: Text(_memberLabel(m)),
                                  subtitle: Text(m.memberType),
                                  trailing: IconButton(
                                    icon: const Icon(
                                        Icons.remove_circle_outline,
                                        size: 18),
                                    onPressed: () => _removeMember(m),
                                  ),
                                )),
                          if (!noMemberControl) ...[
                            const SizedBox(height: 8),
                            _AddMemberRow(
                              allUsers: _allUsers ?? [],
                              allGroups: _allGroups ?? [],
                              existingMembers: detail!.members,
                              onAddUser: _addUserMember,
                              onAddGroup: _addGroupMember,
                            ),
                          ],

                          const Divider(height: 40),

                          // ── Roles ─────────────────────────────────────
                          Text('Assigned roles',
                              style: Theme.of(context).textTheme.labelLarge),
                          const SizedBox(height: 8),
                          if (detail!.roleIds.isEmpty)
                            const Text('No roles assigned')
                          else
                            ...detail.roleIds.map((rid) {
                              final role = _allRoles
                                  ?.where((r) => r.id == rid)
                                  .firstOrNull;
                              return ListTile(
                                dense: true,
                                leading:
                                    const Icon(Icons.shield_outlined, size: 20),
                                title: Text(role?.name ?? rid),
                                trailing: IconButton(
                                  icon: const Icon(
                                      Icons.remove_circle_outline,
                                      size: 18),
                                  onPressed: () => _removeRole(rid),
                                ),
                              );
                            }),
                          const SizedBox(height: 8),
                          _AddRoleRow(
                            allRoles: _allRoles ?? [],
                            assignedIds: detail.roleIds,
                            onAssign: _assignRole,
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }
}

// ── Add member row ────────────────────────────────────────────────────────────

class _AddMemberRow extends StatefulWidget {
  final List<AdminUserRecord> allUsers;
  final List<GroupRecord> allGroups;
  final List<GroupMemberRecord> existingMembers;
  final void Function(String) onAddUser;
  final void Function(String) onAddGroup;

  const _AddMemberRow({
    required this.allUsers,
    required this.allGroups,
    required this.existingMembers,
    required this.onAddUser,
    required this.onAddGroup,
  });

  @override
  State<_AddMemberRow> createState() => _AddMemberRowState();
}

class _AddMemberRowState extends State<_AddMemberRow> {
  String _type = 'user';
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final existingIds = widget.existingMembers
        .where((m) => m.memberType == _type)
        .map((m) => m.memberId)
        .toSet();

    final items = _type == 'user'
        ? widget.allUsers
            .where((u) => !existingIds.contains(u.id))
            .map((u) => DropdownMenuItem(value: u.id, child: Text(u.displayName)))
            .toList()
        : widget.allGroups
            .where((g) => !existingIds.contains(g.id))
            .map((g) => DropdownMenuItem(value: g.id, child: Text(g.name)))
            .toList();

    return Row(
      children: [
        DropdownButton<String>(
          value: _type,
          items: const [
            DropdownMenuItem(value: 'user', child: Text('User')),
            DropdownMenuItem(value: 'group', child: Text('Group')),
          ],
          onChanged: (v) =>
              setState(() {
                _type = v!;
                _selectedId = null;
              }),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<String>(
            value: _selectedId,
            hint: Text('Select $_type'),
            isExpanded: true,
            items: items,
            onChanged: (v) => setState(() => _selectedId = v),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: _selectedId == null
              ? null
              : () {
                  if (_type == 'user') {
                    widget.onAddUser(_selectedId!);
                  } else {
                    widget.onAddGroup(_selectedId!);
                  }
                  setState(() => _selectedId = null);
                },
        ),
      ],
    );
  }
}

// ── Add role row ──────────────────────────────────────────────────────────────

class _AddRoleRow extends StatefulWidget {
  final List<CustomRoleRecord> allRoles;
  final List<String> assignedIds;
  final void Function(String) onAssign;

  const _AddRoleRow({
    required this.allRoles,
    required this.assignedIds,
    required this.onAssign,
  });

  @override
  State<_AddRoleRow> createState() => _AddRoleRowState();
}

class _AddRoleRowState extends State<_AddRoleRow> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final available = widget.allRoles
        .where((r) => !widget.assignedIds.contains(r.id))
        .toList();

    return Row(
      children: [
        Expanded(
          child: DropdownButton<String>(
            value: _selectedId,
            hint: const Text('Select role'),
            isExpanded: true,
            items: available
                .map((r) =>
                    DropdownMenuItem(value: r.id, child: Text(r.name)))
                .toList(),
            onChanged: (v) => setState(() => _selectedId = v),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: _selectedId == null
              ? null
              : () {
                  widget.onAssign(_selectedId!);
                  setState(() => _selectedId = null);
                },
        ),
      ],
    );
  }
}

// ── System badge ──────────────────────────────────────────────────────────────

class _SystemBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: LumaRadius.radiusLg,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline,
              size: 14, color: colorScheme.onTertiaryContainer),
          const SizedBox(width: 4),
          Text(
            'System',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onTertiaryContainer,
                  fontSize: 12,
                ),
          ),
        ],
      ),
    );
  }
}
