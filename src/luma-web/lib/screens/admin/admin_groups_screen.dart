import 'package:flutter/material.dart';

import '../../models/group.dart';
import '../../models/custom_role.dart';
import '../../models/user.dart';
import '../../services/user_service.dart';
import '../../theme/tokens.dart';
import '../../widgets/data_table.dart';
import '../../widgets/perm_button.dart';
import '../../widgets/permission_matrix.dart';
import '../../widgets/pagination.dart';
import '../../widgets/slideout_panel.dart';

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
  Set<int> _selected = {};
  int _currentPage = 0;
  static const _pageSize = 25;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; _selected = {}; _currentPage = 0; });
    try {
      final groups = await widget.userService.listGroups();
      if (mounted) setState(() { _groups = groups; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load groups. Please try again.'; _loading = false; });
    }
  }

  void _showCreateGroupSlideout() {
    final titleNotifier = ValueNotifier('Create group');
    showSlideoutPanel(
      context: context,
      titleNotifier: titleNotifier,
      bodyBuilder: (_) => _CreateGroupContent(
        userService: widget.userService,
        titleNotifier: titleNotifier,
        onCreated: (group) {
          _load();
          return _GroupDetailContent(
            group: group,
            userService: widget.userService,
            onChanged: _load,
          );
        },
      ),
    ).whenComplete(() => titleNotifier.dispose());
  }

  void _showGroupSlideout(GroupRecord group) {
    showSlideoutPanel(
      context: context,
      title: group.name,
      bodyBuilder: (_) => _GroupDetailContent(
        group: group,
        userService: widget.userService,
        onChanged: _load,
      ),
    );
  }

  Future<void> _bulkDelete() async {
    final groups = _groups!;
    final pageStart = _currentPage * _pageSize;
    final targets = _selected
        .map((i) => groups[pageStart + i])
        .where((g) => !g.isSystem && g.memberCount == 0)
        .toList();
    if (targets.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('Delete groups'),
        content: Text('Delete ${targets.length} group(s)? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlg, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(dlg, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    for (final g in targets) {
      try {
        await widget.userService.deleteGroup(g.id);
      } catch (_) {}
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final groups = _groups ?? [];
    final totalPages = (groups.length / _pageSize).ceil().clamp(1, 999);
    final pageStart = _currentPage * _pageSize;
    final pageGroups = groups.sublist(
      pageStart, (pageStart + _pageSize).clamp(0, groups.length));

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Groups',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      '${groups.length} total \u00b7 Organize users into teams.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              PermButton(
                label: 'Create group',
                filled: true,
                enabled: widget.userService.canCreateGroup,
                requiredPermission: 'group:create',
                onPressed: _showCreateGroupSlideout,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(
                child: Center(
                    child: Text(_error!,
                        style: TextStyle(color: cs.error))))
          else
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: groups.isEmpty
                        ? const Center(child: Text('No groups yet'))
                        : LumaDataTable<GroupRecord>(
                            showCheckboxes: widget.userService.canEditGroup,
                            selected: _selected,
                            onSelectionChanged: (s) => setState(() => _selected = s),
                            canSelect: (g, _) => !g.isSystem,
                            onRowTap: widget.userService.canEditGroup
                                ? _showGroupSlideout
                                : null,
                            bulkActionBar: (sel) => _BulkActionBar(
                              count: sel.length,
                              onClear: () => setState(() => _selected = {}),
                              actions: [
                                OutlinedButton.icon(
                                  icon: Icon(Icons.delete_outlined,
                                      size: 16, color: cs.error),
                                  label: Text('Delete',
                                      style: TextStyle(color: cs.error)),
                                  onPressed: _bulkDelete,
                                ),
                              ],
                            ),
                            columns: [
                              LumaColumn<GroupRecord>(
                                label: 'Name',
                                cellBuilder: (g, _) => Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(g.name,
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(fontWeight: FontWeight.w600),
                                              overflow: TextOverflow.ellipsis),
                                        ),
                                        if (g.isSystem) ...[
                                          const SizedBox(width: 8),
                                          const _SystemBadge(),
                                        ],
                                      ],
                                    ),
                                    if (g.description != null &&
                                        g.description!.isNotEmpty)
                                      Text(
                                        g.description!,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(color: cs.onSurfaceVariant),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              LumaColumn<GroupRecord>(
                                label: 'Members',
                                width: 120,
                                cellBuilder: (g, _) => Text(
                                  '${g.memberCount} member${g.memberCount == 1 ? '' : 's'}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                              LumaColumn<GroupRecord>(
                                label: 'Roles',
                                width: 100,
                                cellBuilder: (g, _) => Text(
                                  '${g.roleIds.length} role${g.roleIds.length == 1 ? '' : 's'}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                              LumaColumn<GroupRecord>(
                                label: '',
                                width: 100,
                                cellBuilder: (g, _) => Align(
                                  alignment: Alignment.centerRight,
                                  child: PermButton(
                                    label: 'Manage',
                                    enabled: widget.userService.canEditGroup,
                                    requiredPermission: 'group:rename',
                                    onPressed: () => _showGroupSlideout(g),
                                  ),
                                ),
                              ),
                            ],
                            rows: pageGroups,
                          ),
                  ),
                  LumaPagination(
                    currentPage: _currentPage,
                    totalPages: totalPages,
                    onPageChanged: (p) =>
                        setState(() { _currentPage = p; _selected = {}; }),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Bulk action bar ───────────────────────────────────────────────────────────

class _BulkActionBar extends StatelessWidget {
  final int count;
  final VoidCallback onClear;
  final List<Widget> actions;

  const _BulkActionBar({
    required this.count,
    required this.onClear,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withAlpha(60),
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withAlpha(128)),
        ),
      ),
      child: Row(
        children: [
          Text('$count selected',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          ...actions,
          const Spacer(),
          TextButton(
            onPressed: onClear,
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

// ── Group detail content (slideout body) ─────────────────────────────────────

class _GroupDetailContent extends StatefulWidget {
  final GroupRecord group;
  final UserService userService;
  final VoidCallback onChanged;

  const _GroupDetailContent({
    required this.group,
    required this.userService,
    required this.onChanged,
  });

  @override
  State<_GroupDetailContent> createState() => _GroupDetailContentState();
}

class _GroupDetailContentState extends State<_GroupDetailContent> {
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
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

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
        widget.group.id,
        _nameCtrl.text.trim(),
        description: desc.isEmpty ? null : desc,
        clearDescription: desc.isEmpty,
      );
      await _loadDetail();
      widget.onChanged();
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
      await widget.userService.deleteGroup(widget.group.id);
      widget.onChanged();
      if (mounted) Navigator.of(context).pop();
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
      await widget.userService.addGroupMember(widget.group.id, 'user', userId);
      await _loadDetail();
      widget.onChanged();
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  Future<void> _addGroupMember(String groupId) async {
    try {
      await widget.userService.addGroupMember(widget.group.id, 'group', groupId);
      await _loadDetail();
      widget.onChanged();
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
      await widget.userService.removeGroupMember(widget.group.id, m.memberType, m.memberId);
      await _loadDetail();
      widget.onChanged();
    } catch (e) {
      if (mounted) _showError('Could not remove member. Please try again.');
    }
  }

  Future<void> _assignRole(String roleId) async {
    try {
      await widget.userService.assignRoleToGroup(widget.group.id, roleId);
      await _loadDetail();
      widget.onChanged();
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  Future<void> _removeRole(String roleId) async {
    try {
      await widget.userService.removeRoleFromGroup(widget.group.id, roleId);
      await _loadDetail();
      widget.onChanged();
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  String _memberLabel(GroupMemberRecord m) {
    if (m.memberType == 'user') {
      final u = _allUsers?.where((u) => u.id == m.memberId).firstOrNull;
      return u?.displayName ?? m.memberId;
    } else {
      final allG = (_allGroups ?? []) + [widget.group];
      final found = allG.where((g) => g.id == m.memberId).firstOrNull;
      return found?.name ?? m.memberId;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: colorScheme.error)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadDetail, child: const Text('Retry')),
          ],
        ),
      );
    }

    final detail = _detail!;
    final isSystem = detail.isSystem;
    final noMemberControl = detail.noMemberControl;
    final canDelete = detail.memberCount == 0 && !isSystem;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isSystem)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: _SystemBadge(),
            ),

          // ── Name + Description ───────────────────────
          Text('Name', style: Theme.of(context).textTheme.labelLarge),
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
            widget.group.id,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withAlpha(100),
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
              foregroundColor: canDelete ? colorScheme.error : null,
            ),
          ),

          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hide from directory search'),
            subtitle: const Text(
              'When enabled, this group will not appear in search results for non-admin users.',
            ),
            value: detail.hideFromSearch,
            onChanged: isSystem
                ? null
                : (hide) async {
                    try {
                      await widget.userService
                          .setGroupHideFromSearch(widget.group.id, hide: hide);
                      await _loadDetail();
                      widget.onChanged();
                    } catch (e) {
                      if (mounted) _showError(e.toString());
                    }
                  },
          ),

          const Divider(height: 40),

          // ── Members ──────────────────────────────────
          Text('Members', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          if (noMemberControl)
            Text(
              'Membership is managed automatically by the system.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant),
            )
          else if (detail.members.isEmpty)
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
              existingMembers: detail.members,
              onAddUser: _addUserMember,
              onAddGroup: _addGroupMember,
            ),
          ],

          const Divider(height: 40),

          // ── Roles ─────────────────────────────────────
          Text('Assigned roles', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          if (detail.roleIds.isEmpty)
            const Text('No roles assigned')
          else
            ...detail.roleIds.map((rid) {
              final role = _allRoles?.where((r) => r.id == rid).firstOrNull;
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

          const Divider(height: 40),

          // ── Effective permissions ───────────────────────
          Text('Effective permissions', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          if (detail.roleIds.isEmpty)
            Text(
              'No roles assigned — no permissions granted.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            )
          else
            PermissionMatrix(
              permMap: resolveEffectivePermissions(
                (_allRoles ?? [])
                    .where((r) => detail.roleIds.contains(r.id))
                    .toList(),
              ),
              readOnly: true,
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Create group slideout content ─────────────────────────────────────────────

class _CreateGroupContent extends StatefulWidget {
  final UserService userService;
  final ValueNotifier<String> titleNotifier;
  final Widget Function(GroupRecord group) onCreated;

  const _CreateGroupContent({
    required this.userService,
    required this.titleNotifier,
    required this.onCreated,
  });

  @override
  State<_CreateGroupContent> createState() => _CreateGroupContentState();
}

class _CreateGroupContentState extends State<_CreateGroupContent> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _saving = false;
  String? _error;
  Widget? _detailView;

  @override
  void dispose() { _nameCtrl.dispose(); _descCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() { _saving = true; _error = null; });
    try {
      final desc = _descCtrl.text.trim();
      final group = await widget.userService.createGroup(
        _nameCtrl.text.trim(),
        description: desc.isEmpty ? null : desc,
      );
      if (!mounted) return;
      widget.titleNotifier.value = group.name;
      setState(() => _detailView = widget.onCreated(group));
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_detailView != null) return _detailView!;

    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
            Text(_error!, style: TextStyle(color: cs.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Create group'),
          ),
        ],
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

// ── System badge ─────────────────────────────────────────────────────────────

class _SystemBadge extends StatelessWidget {
  const _SystemBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: LumaRadius.radiusLg,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline,
              size: 11, color: colorScheme.onTertiaryContainer),
          const SizedBox(width: 3),
          Text(
            'System',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onTertiaryContainer,
                ),
          ),
        ],
      ),
    );
  }
}
