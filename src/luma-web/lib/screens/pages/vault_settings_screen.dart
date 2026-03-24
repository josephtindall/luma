import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/page_service.dart';
import '../../services/user_service.dart';
import '../../theme/tokens.dart';

const _kRoles = [
  (label: 'Viewer', id: 'builtin:vault-viewer'),
  (label: 'Editor', id: 'builtin:vault-editor'),
  (label: 'Admin', id: 'builtin:vault-admin'),
];

String _roleLabel(String roleId) {
  for (final r in _kRoles) {
    if (r.id == roleId) return r.label;
  }
  return roleId;
}

/// Vault settings screen. Supports two modes:
///  - Normal: uses [pageService] + vault is identified by [slug].
///  - Admin:  uses [userService] + vault is identified by [vaultId].
///    adminMode must be true and userService must be provided.
class VaultSettingsScreen extends StatefulWidget {
  /// Normal mode: identify vault by slug (resolves to id on load).
  final String? slug;

  /// Admin mode: identify vault by id directly.
  final String? vaultId;

  final PageService pageService;
  final UserService? userService;
  final bool adminMode;

  const VaultSettingsScreen({
    super.key,
    this.slug,
    this.vaultId,
    required this.pageService,
    this.userService,
    this.adminMode = false,
  }) : assert(
          slug != null || vaultId != null,
          'Either slug or vaultId must be provided',
        );

  @override
  State<VaultSettingsScreen> createState() => _VaultSettingsScreenState();
}

class _VaultSettingsScreenState extends State<VaultSettingsScreen> {
  VaultSummary? _vault;
  List<VaultMemberDetail> _members = [];
  List<VaultGroupMemberDetail> _groupMembers = [];
  bool _loadingMembers = true;
  String? _error;

  // Permissions
  Map<String, bool> _perms = {};
  bool _loadingPerms = true;

  final _nameController = TextEditingController();
  bool _isPrivate = true;
  bool _savingSettings = false;
  bool _archiving = false;

  // User member add
  UserSearchResult? _selectedUser;
  String _addRoleId = 'builtin:vault-viewer';
  bool _addingMember = false;

  // Group member add
  GroupSearchResult? _selectedGroup;
  String _addGroupRoleId = 'builtin:vault-viewer';
  bool _addingGroupMember = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    if (widget.adminMode && widget.vaultId != null) {
      _vault = widget.pageService.vaults
          .where((v) => v.id == widget.vaultId)
          .firstOrNull;
    } else if (widget.slug != null) {
      _vault = widget.pageService.vaults
          .where((v) => v.slug == widget.slug)
          .firstOrNull;
    }

    if (_vault != null) {
      _nameController.text = _vault!.name;
      _isPrivate = _vault!.isPrivate;
    }

    await Future.wait([_loadMembers(), _loadPermissions()]);
  }

  String get _effectiveVaultId => _vault?.id ?? widget.vaultId ?? '';

  bool get _canEdit => _perms['can_edit'] == true;
  bool get _canArchive => _perms['can_archive'] == true;
  bool get _canManageMembers => _perms['can_manage_members'] == true;
  bool get _canManageRoles => _perms['can_manage_roles'] == true;

  void _goBack() {
    if (widget.adminMode) {
      context.go('/admin/vaults');
    } else {
      context.go('/vaults/${widget.slug}');
    }
  }

  Future<void> _loadPermissions() async {
    if (_effectiveVaultId.isEmpty) {
      setState(() => _loadingPerms = false);
      return;
    }
    // Admin mode: full permissions by definition.
    if (widget.adminMode) {
      setState(() {
        _perms = {
          'can_edit': true,
          'can_archive': true,
          'can_manage_members': true,
          'can_manage_roles': true,
        };
        _loadingPerms = false;
      });
      return;
    }
    final perms =
        await widget.pageService.fetchVaultPermissions(_effectiveVaultId);
    if (mounted) {
      setState(() {
        _perms = perms;
        _loadingPerms = false;
      });
    }
  }

  Future<void> _loadMembers() async {
    if (_effectiveVaultId.isEmpty) {
      setState(() {
        _loadingMembers = false;
        _error = 'Vault not found';
      });
      return;
    }
    setState(() {
      _loadingMembers = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.adminMode
            ? widget.userService!.adminListVaultMembers(_effectiveVaultId)
            : widget.pageService.listVaultMembers(_effectiveVaultId),
        widget.adminMode
            ? widget.userService!
                .adminListVaultGroupMembers(_effectiveVaultId)
            : widget.pageService.listVaultGroupMembers(_effectiveVaultId),
      ]);
      if (mounted) {
        setState(() {
          _members = results[0] as List<VaultMemberDetail>;
          // Filter out legacy "system:*" group identifiers only.
          // luma-auth system groups (Users, Super Admins) are shown so
          // admins can see which system groups have vault access.
          _groupMembers = (results[1] as List<VaultGroupMemberDetail>)
              .where((g) => !g.groupId.startsWith('system:'))
              .toList();
          _loadingMembers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loadingMembers = false;
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    if (!_canEdit) return;
    final newName = _nameController.text.trim();
    if (newName.isEmpty) return;
    setState(() => _savingSettings = true);
    try {
      if (widget.adminMode) {
        await widget.userService!.adminUpdateVault(
          _effectiveVaultId,
          name: newName != _vault?.name ? newName : null,
          isPrivate: _isPrivate != _vault?.isPrivate ? _isPrivate : null,
        );
      } else {
        await widget.pageService.updateVault(
          _effectiveVaultId,
          name: newName != _vault?.name ? newName : null,
          isPrivate: _isPrivate != _vault?.isPrivate ? _isPrivate : null,
        );
        _vault = widget.pageService.vaults
            .where((v) => v.id == _effectiveVaultId)
            .firstOrNull;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingSettings = false);
    }
  }

  Future<void> _archiveVault() async {
    if (!_canArchive) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive vault'),
        content: const Text(
          'This vault and all its content will be archived and no longer visible. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _archiving = true);
    try {
      if (widget.adminMode) {
        await widget.userService!.adminArchiveVault(_effectiveVaultId);
      } else {
        await widget.pageService.archiveVault(_effectiveVaultId);
      }
      if (mounted) {
        if (widget.adminMode) {
          context.go('/admin/vaults');
        } else {
          context.go('/home');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _archiving = false);
      }
    }
  }

  Future<void> _changeRole(VaultMemberDetail member, String newRole) async {
    if (!_canManageRoles) return;
    try {
      if (widget.adminMode) {
        await widget.userService!.adminUpdateMemberRole(
          _effectiveVaultId,
          member.userId,
          newRole,
        );
      } else {
        await widget.pageService.updateMemberRole(
          _effectiveVaultId,
          member.userId,
          newRole,
        );
      }
      await _loadMembers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _removeMember(VaultMemberDetail member) async {
    if (!_canManageMembers) return;
    final name = member.displayName.isNotEmpty
        ? member.displayName
        : member.userId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member'),
        content: Text('Remove $name from this vault?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (widget.adminMode) {
        await widget.userService!.adminRemoveVaultMember(
          _effectiveVaultId,
          member.userId,
        );
      } else {
        await widget.pageService.removeVaultMember(
          _effectiveVaultId,
          member.userId,
        );
      }
      await _loadMembers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _addMember() async {
    final user = _selectedUser;
    if (user == null || !_canManageMembers) return;
    setState(() => _addingMember = true);
    try {
      if (widget.adminMode) {
        await widget.userService!.adminAddVaultMember(
          _effectiveVaultId,
          user.id,
          _addRoleId,
        );
      } else {
        await widget.pageService.addVaultMember(
          _effectiveVaultId,
          user.id,
          _addRoleId,
        );
      }
      setState(() => _selectedUser = null);
      await _loadMembers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _addingMember = false);
    }
  }

  Future<void> _changeGroupRole(
      VaultGroupMemberDetail member, String newRole) async {
    if (!_canManageRoles) return;
    try {
      if (widget.adminMode) {
        await widget.userService!.adminUpdateGroupMemberRole(
            _effectiveVaultId, member.groupId, newRole);
      } else {
        await widget.pageService
            .updateGroupMemberRole(_effectiveVaultId, member.groupId, newRole);
      }
      await _loadMembers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _removeGroupMember(VaultGroupMemberDetail member) async {
    if (!_canManageMembers) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove group'),
        content: Text('Remove ${member.groupName} from this vault?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (widget.adminMode) {
        await widget.userService!
            .adminRemoveVaultGroupMember(_effectiveVaultId, member.groupId);
      } else {
        await widget.pageService
            .removeVaultGroupMember(_effectiveVaultId, member.groupId);
      }
      await _loadMembers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _addGroupMember() async {
    final group = _selectedGroup;
    if (group == null || !_canManageMembers) return;
    setState(() => _addingGroupMember = true);
    try {
      if (widget.adminMode) {
        await widget.userService!.adminAddVaultGroupMember(
            _effectiveVaultId, group.id, _addGroupRoleId);
      } else {
        await widget.pageService
            .addVaultGroupMember(_effectiveVaultId, group.id, _addGroupRoleId);
      }
      setState(() => _selectedGroup = null);
      await _loadMembers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _addingGroupMember = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _goBack),
        title: Text(
          widget.adminMode ? 'Admin — Vault Settings' : 'Vault Settings',
        ),
      ),
      body: _loadingPerms
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Name & Privacy ──────────────────────────────────────
                      Text('General',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _nameController,
                        enabled: _canEdit,
                        decoration: const InputDecoration(
                          labelText: 'Vault name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        title: const Text('Private vault'),
                        subtitle:
                            const Text('Only members can view content'),
                        value: _isPrivate,
                        onChanged:
                            _canEdit ? (v) => setState(() => _isPrivate = v) : null,
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Tooltip(
                          message:
                              _canEdit ? '' : 'Requires vault:edit permission',
                          child: FilledButton(
                            onPressed: (_savingSettings || !_canEdit)
                                ? null
                                : _saveSettings,
                            child: _savingSettings
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Text('Save changes'),
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),
                      Divider(color: colorScheme.outlineVariant),
                      const SizedBox(height: 24),

                      // ── User Members ────────────────────────────────────────
                      Text('Members',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),

                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(_error!,
                              style:
                                  TextStyle(color: colorScheme.error)),
                        ),

                      if (_loadingMembers)
                        const Center(child: CircularProgressIndicator())
                      else
                        ..._members.map(
                          (m) => _MemberRow(
                            member: m,
                            canChangeRole: _canManageRoles,
                            canRemove: _canManageMembers,
                            onRoleChange: (role) => _changeRole(m, role),
                            onRemove: () => _removeMember(m),
                          ),
                        ),

                      const SizedBox(height: 24),
                      Divider(color: colorScheme.outlineVariant),
                      const SizedBox(height: 24),

                      // ── Add user member ─────────────────────────────────────
                      Text('Add member',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Autocomplete<UserSearchResult>(
                              displayStringForOption: (r) =>
                                  r.displayName.isNotEmpty
                                      ? '${r.displayName} (${r.email})'
                                      : r.email,
                              optionsBuilder:
                                  (textEditingValue) async {
                                final q = textEditingValue.text.trim();
                                if (q.length < 2) return [];
                                try {
                                  final results = await widget.pageService
                                      .searchUsers(q);
                                  final memberIds =
                                      _members.map((m) => m.userId).toSet();
                                  return results
                                      .where((r) => !memberIds.contains(r.id))
                                      .toList();
                                } catch (_) {
                                  return [];
                                }
                              },
                              onSelected: (result) {
                                setState(() => _selectedUser = result);
                              },
                              fieldViewBuilder:
                                  (ctx, ctrl, focusNode, onSubmit) =>
                                      TextField(
                                controller: ctrl,
                                focusNode: focusNode,
                                enabled: _canManageMembers,
                                decoration: const InputDecoration(
                                  labelText: 'Search by name or email',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (_) =>
                                    setState(() => _selectedUser = null),
                              ),
                              optionsViewBuilder:
                                  (ctx, onSelected, options) => Align(
                                alignment: Alignment.topLeft,
                                child: Material(
                                  elevation: 4,
                                  borderRadius:
                                      LumaRadius.radiusMd,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                        maxHeight: 200),
                                    child: ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      itemBuilder: (ctx, i) {
                                        final r = options.elementAt(i);
                                        return ListTile(
                                          title: Text(
                                              r.displayName.isNotEmpty
                                                  ? r.displayName
                                                  : r.email),
                                          subtitle:
                                              r.displayName.isNotEmpty
                                                  ? Text(r.email)
                                                  : null,
                                          onTap: () => onSelected(r),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          DropdownButton<String>(
                            value: _addRoleId,
                            items: _kRoles
                                .map((r) => DropdownMenuItem(
                                      value: r.id,
                                      child: Text(r.label),
                                    ))
                                .toList(),
                            onChanged: _canManageMembers
                                ? (v) {
                                    if (v != null) {
                                      setState(() => _addRoleId = v);
                                    }
                                  }
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Tooltip(
                            message: !_canManageMembers
                                ? 'Requires vault:manage-members permission'
                                : '',
                            child: FilledButton(
                              onPressed: (_addingMember ||
                                      _selectedUser == null ||
                                      !_canManageMembers)
                                  ? null
                                  : _addMember,
                              child: _addingMember
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Text('Add'),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 32),
                      Divider(color: colorScheme.outlineVariant),
                      const SizedBox(height: 24),

                      // ── Group Members ───────────────────────────────────────
                      Text('Groups',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),

                      if (_loadingMembers)
                        const SizedBox.shrink()
                      else
                        ..._groupMembers.map(
                          (g) => _GroupMemberRow(
                            member: g,
                            canChangeRole: _canManageRoles,
                            canRemove: _canManageMembers,
                            onRoleChange: (role) =>
                                _changeGroupRole(g, role),
                            onRemove: () => _removeGroupMember(g),
                          ),
                        ),

                      const SizedBox(height: 16),

                      // ── Add group member ────────────────────────────────────
                      Text('Add group',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Autocomplete<GroupSearchResult>(
                              displayStringForOption: (r) => r.name,
                              optionsBuilder:
                                  (textEditingValue) async {
                                final q = textEditingValue.text.trim();
                                if (q.length < 2) return [];
                                try {
                                  final results = await widget.pageService
                                      .searchGroups(q);
                                  final groupIds = _groupMembers
                                      .map((g) => g.groupId)
                                      .toSet();
                                  return results
                                      .where(
                                          (r) => !groupIds.contains(r.id))
                                      .toList();
                                } catch (_) {
                                  return [];
                                }
                              },
                              onSelected: (result) {
                                setState(() => _selectedGroup = result);
                              },
                              fieldViewBuilder:
                                  (ctx, ctrl, focusNode, onSubmit) =>
                                      TextField(
                                controller: ctrl,
                                focusNode: focusNode,
                                enabled: _canManageMembers,
                                decoration: const InputDecoration(
                                  labelText: 'Search by group name',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (_) =>
                                    setState(() => _selectedGroup = null),
                              ),
                              optionsViewBuilder:
                                  (ctx, onSelected, options) => Align(
                                alignment: Alignment.topLeft,
                                child: Material(
                                  elevation: 4,
                                  borderRadius:
                                      LumaRadius.radiusMd,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                        maxHeight: 200),
                                    child: ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      itemBuilder: (ctx, i) {
                                        final r = options.elementAt(i);
                                        return ListTile(
                                          title: Text(r.name),
                                          onTap: () => onSelected(r),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          DropdownButton<String>(
                            value: _addGroupRoleId,
                            items: _kRoles
                                .map((r) => DropdownMenuItem(
                                      value: r.id,
                                      child: Text(r.label),
                                    ))
                                .toList(),
                            onChanged: _canManageMembers
                                ? (v) {
                                    if (v != null) {
                                      setState(() => _addGroupRoleId = v);
                                    }
                                  }
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Tooltip(
                            message: !_canManageMembers
                                ? 'Requires vault:manage-members permission'
                                : '',
                            child: FilledButton(
                              onPressed: (_addingGroupMember ||
                                      _selectedGroup == null ||
                                      !_canManageMembers)
                                  ? null
                                  : _addGroupMember,
                              child: _addingGroupMember
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Text('Add'),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 48),
                      Divider(color: colorScheme.outlineVariant),
                      const SizedBox(height: 24),

                      // ── Danger zone ─────────────────────────────────────────
                      Text(
                        'Danger zone',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: colorScheme.error),
                      ),
                      const SizedBox(height: 12),
                      Tooltip(
                        message: _canArchive
                            ? ''
                            : 'Requires vault:archive permission',
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colorScheme.error,
                            side: BorderSide(color: colorScheme.error),
                          ),
                          onPressed: (_archiving || !_canArchive)
                              ? null
                              : _archiveVault,
                          icon: _archiving
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colorScheme.error,
                                  ),
                                )
                              : const Icon(Icons.archive_outlined),
                          label: const Text('Archive vault'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Archiving a vault hides it and all its content. This cannot be undone.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                                color: colorScheme.onSurfaceVariant),
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

class _MemberRow extends StatelessWidget {
  final VaultMemberDetail member;
  final bool canChangeRole;
  final bool canRemove;
  final void Function(String roleId) onRoleChange;
  final VoidCallback onRemove;

  const _MemberRow({
    required this.member,
    required this.canChangeRole,
    required this.canRemove,
    required this.onRoleChange,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final name = member.displayName.isNotEmpty
        ? member.displayName
        : member.userId;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
      ),
      title: Text(name),
      subtitle: member.email.isNotEmpty ? Text(member.email) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message:
                canChangeRole ? '' : 'Requires vault:manage-roles permission',
            child: DropdownButton<String>(
              value: _kRoles.any((r) => r.id == member.roleId)
                  ? member.roleId
                  : null,
              hint: Text(_roleLabel(member.roleId)),
              items: _kRoles
                  .map((r) => DropdownMenuItem(
                        value: r.id,
                        child: Text(r.label),
                      ))
                  .toList(),
              onChanged: canChangeRole
                  ? (v) {
                      if (v != null) onRoleChange(v);
                    }
                  : null,
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message:
                canRemove ? '' : 'Requires vault:manage-members permission',
            child: IconButton(
              icon: const Icon(Icons.person_remove_outlined),
              tooltip: canRemove ? 'Remove member' : null,
              onPressed: canRemove ? onRemove : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupMemberRow extends StatelessWidget {
  final VaultGroupMemberDetail member;
  final bool canChangeRole;
  final bool canRemove;
  final void Function(String roleId) onRoleChange;
  final VoidCallback onRemove;

  const _GroupMemberRow({
    required this.member,
    required this.canChangeRole,
    required this.canRemove,
    required this.onRoleChange,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final name =
        member.groupName.isNotEmpty ? member.groupName : member.groupId;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        child: const Icon(Icons.group_outlined, size: 18),
      ),
      title: Text(name),
      subtitle: const Text('Group'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message:
                canChangeRole ? '' : 'Requires vault:manage-roles permission',
            child: DropdownButton<String>(
              value: _kRoles.any((r) => r.id == member.roleId)
                  ? member.roleId
                  : null,
              hint: Text(_roleLabel(member.roleId)),
              items: _kRoles
                  .map((r) => DropdownMenuItem(
                        value: r.id,
                        child: Text(r.label),
                      ))
                  .toList(),
              onChanged: canChangeRole
                  ? (v) {
                      if (v != null) onRoleChange(v);
                    }
                  : null,
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message:
                canRemove ? '' : 'Requires vault:manage-members permission',
            child: IconButton(
              icon: const Icon(Icons.group_remove_outlined),
              tooltip: canRemove ? 'Remove group' : null,
              onPressed: canRemove ? onRemove : null,
            ),
          ),
        ],
      ),
    );
  }
}
