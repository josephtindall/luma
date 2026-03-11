import 'package:flutter/material.dart';

import '../../models/group.dart';
import '../../models/custom_role.dart';
import '../../models/user.dart';
import '../../services/user_service.dart';

class AdminGroupsScreen extends StatefulWidget {
  final UserService userService;
  const AdminGroupsScreen({super.key, required this.userService});

  @override
  State<AdminGroupsScreen> createState() => _AdminGroupsScreenState();
}

class _AdminGroupsScreenState extends State<AdminGroupsScreen> {
  List<GroupRecord>? _groups;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final groups = await widget.userService.listGroups();
      if (mounted) setState(() { _groups = groups; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load groups. Please try again.'; _loading = false; });
    }
  }

  void _showCreateDialog() {
    showDialog(
      context: context,
      builder: (_) => _CreateGroupDialog(
        userService: widget.userService,
        onCreated: _load,
      ),
    );
  }

  void _showManageDialog(GroupRecord group) {
    showDialog(
      context: context,
      builder: (_) => _GroupManageDialog(
        userService: widget.userService,
        group: group,
        onChanged: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(_groups == null ? 'Groups' : 'Groups (${_groups!.length})'),
                  backgroundColor: colorScheme.secondaryContainer,
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _showCreateDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Create group'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Center(child: Text(_error!, style: TextStyle(color: colorScheme.error)))
            else if (_groups == null || _groups!.isEmpty)
              const Center(child: Text('No groups yet'))
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _groups!.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final g = _groups![i];
                    return ListTile(
                      title: Row(
                        children: [
                          Text(g.name),
                          if (g.isSystem) ...[
                            const SizedBox(width: 8),
                            const _SystemBadge(),
                          ],
                        ],
                      ),
                      subtitle: Text('${g.memberCount} member${g.memberCount == 1 ? '' : 's'}'
                          ' · ${g.roleIds.length} role${g.roleIds.length == 1 ? '' : 's'}'),
                      trailing: OutlinedButton(
                        onPressed: () => _showManageDialog(g),
                        child: const Text('Manage'),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Create group dialog ──────────────────────────────────────────────────────

class _CreateGroupDialog extends StatefulWidget {
  final UserService userService;
  final VoidCallback onCreated;
  const _CreateGroupDialog({required this.userService, required this.onCreated});

  @override
  State<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<_CreateGroupDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() { _nameCtrl.dispose(); _descCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() { _saving = true; _error = null; });
    try {
      final desc = _descCtrl.text.trim();
      await widget.userService.createGroup(
        _nameCtrl.text.trim(),
        description: desc.isEmpty ? null : desc,
      );
      if (mounted) { Navigator.of(context).pop(); widget.onCreated(); }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create group'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Group name'),
              autofocus: true,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
              maxLines: 2,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _submit, child: const Text('Create')),
      ],
    );
  }
}

// ── Manage group dialog ──────────────────────────────────────────────────────

class _GroupManageDialog extends StatefulWidget {
  final UserService userService;
  final GroupRecord group;
  final VoidCallback onChanged;
  const _GroupManageDialog({
    required this.userService,
    required this.group,
    required this.onChanged,
  });

  @override
  State<_GroupManageDialog> createState() => _GroupManageDialogState();
}

class _GroupManageDialogState extends State<_GroupManageDialog> {
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
    _nameCtrl = TextEditingController(text: widget.group.name);
    _descCtrl = TextEditingController(text: widget.group.description ?? '');
    _loadDetail();
  }

  @override
  void dispose() { _nameCtrl.dispose(); _descCtrl.dispose(); super.dispose(); }

  Future<void> _loadDetail() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        widget.userService.getGroup(widget.group.id),
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
              .where((g) => g.id != widget.group.id)
              .toList();
          _allRoles = results[3] as List<CustomRoleRecord>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load groups. Please try again.'; _loading = false; });
    }
  }

  Future<void> _rename() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    final desc = _descCtrl.text.trim();
    try {
      await widget.userService.renameGroup(
        widget.group.id,
        _nameCtrl.text.trim(),
        description: desc.isEmpty ? null : desc,
        clearDescription: desc.isEmpty,
      );
      if (mounted) { widget.onChanged(); await _loadDetail(); }
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
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.userService.deleteGroup(widget.group.id);
      if (mounted) { Navigator.of(context).pop(); widget.onChanged(); }
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  void _showError(String msg) {
    final display = msg.replaceFirst('Exception: ', '');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(display.isEmpty ? 'Something went wrong. Please try again.' : display),
      backgroundColor: Theme.of(context).colorScheme.error,
    ));
  }

  Future<void> _addUserMember(String userId) async {
    try {
      await widget.userService.addGroupMember(widget.group.id, 'user', userId);
      await _loadDetail();
    } catch (e) { if (mounted) _showError(e.toString()); }
  }

  Future<void> _addGroupMember(String groupId) async {
    try {
      await widget.userService.addGroupMember(widget.group.id, 'group', groupId);
      await _loadDetail();
    } catch (e) { if (mounted) _showError(e.toString()); }
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
      await widget.userService.removeGroupMember(widget.group.id, m.memberType, m.memberId);
      await _loadDetail();
    } catch (e) { if (mounted) _showError('Could not remove member. Please try again.'); }
  }

  Future<void> _assignRole(String roleId) async {
    try {
      await widget.userService.assignRoleToGroup(widget.group.id, roleId);
      await _loadDetail();
    } catch (e) { if (mounted) _showError(e.toString()); }
  }

  Future<void> _removeRole(String roleId) async {
    try {
      await widget.userService.removeRoleFromGroup(widget.group.id, roleId);
      await _loadDetail();
    } catch (e) { if (mounted) _showError(e.toString()); }
  }

  String _memberLabel(GroupMemberRecord m) {
    if (m.memberType == 'user') {
      final u = _allUsers?.where((u) => u.id == m.memberId).firstOrNull;
      return u?.displayName ?? m.memberId;
    } else {
      final g = (_allGroups ?? []) + [widget.group];
      final found = g.where((g) => g.id == m.memberId).firstOrNull;
      return found?.name ?? m.memberId;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final detail = _detail;
    final isSystem = detail?.isSystem ?? false;
    final noMemberControl = detail?.noMemberControl ?? false;
    final canDelete = (detail?.memberCount ?? 1) == 0 && !isSystem;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('Manage group',
                                  style: Theme.of(context).textTheme.titleMedium),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                        const Divider(),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ── Name + Description ──────────────────
                                Text('Name', style: Theme.of(context).textTheme.labelLarge),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(child: TextField(
                                      controller: _nameCtrl,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                    )),
                                    const SizedBox(width: 8),
                                    OutlinedButton(onPressed: _rename, child: const Text('Save')),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _descCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Description (optional)',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  maxLines: 2,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  widget.group.id,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant.withAlpha(100),
                                        fontFamily: 'monospace',
                                      ),
                                ),
                                if (isSystem) ...[
                                  const SizedBox(height: 8),
                                  const _SystemBadge(large: true),
                                ],
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: canDelete ? _delete : null,
                                  icon: const Icon(Icons.delete_outline, size: 16),
                                  label: Text(isSystem
                                      ? 'Cannot delete (system group)'
                                      : canDelete
                                          ? 'Delete group'
                                          : 'Cannot delete (has members)'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: canDelete ? colorScheme.error : null,
                                  ),
                                ),
                                const Divider(height: 32),
                                // ── Members ─────────────────────────────
                                Text('Members', style: Theme.of(context).textTheme.labelLarge),
                                const SizedBox(height: 8),
                                if (noMemberControl)
                                  Text(
                                    'Membership is managed automatically by the system.',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
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
                                      icon: const Icon(Icons.remove_circle_outline, size: 18),
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
                                const Divider(height: 32),
                                // ── Roles ────────────────────────────────
                                Text('Assigned roles', style: Theme.of(context).textTheme.labelLarge),
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
                                      leading: const Icon(Icons.shield_outlined, size: 20),
                                      title: Text(role?.name ?? rid),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, size: 18),
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
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}

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
          onChanged: (v) => setState(() { _type = v!; _selectedId = null; }),
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
                .map((r) => DropdownMenuItem(value: r.id, child: Text(r.name)))
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

class _SystemBadge extends StatelessWidget {
  final bool large;
  const _SystemBadge({this.large = false});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: large ? 10 : 6, vertical: large ? 4 : 2),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline,
              size: large ? 14 : 11,
              color: colorScheme.onTertiaryContainer),
          SizedBox(width: large ? 4 : 3),
          Text(
            'System',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onTertiaryContainer,
                  fontSize: large ? 12 : null,
                ),
          ),
        ],
      ),
    );
  }
}
