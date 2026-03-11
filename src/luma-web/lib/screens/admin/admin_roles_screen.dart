import 'package:flutter/material.dart';

import '../../models/custom_role.dart';
import '../../services/user_service.dart';

// Canonical action groups for permissions UI
const _actionGroups = <String, List<String>>{
  'Pages': ['page:read', 'page:create', 'page:edit', 'page:delete', 'page:archive', 'page:version', 'page:restore-version', 'page:share', 'page:transclude'],
  'Tasks': ['task:read', 'task:create', 'task:edit', 'task:delete', 'task:assign', 'task:close', 'task:comment'],
  'Flows': ['flow:read', 'flow:create', 'flow:edit', 'flow:delete', 'flow:publish', 'flow:execute', 'flow:comment'],
  'Vaults': ['vault:read', 'vault:create', 'vault:edit', 'vault:delete', 'vault:archive', 'vault:manage-members', 'vault:manage-roles'],
  'Users': ['user:read', 'user:invite', 'user:edit', 'user:delete', 'user:lock', 'user:unlock', 'user:revoke-sessions'],
  'Audit': ['audit:read-own', 'audit:read-all', 'audit:export-all'],
  'Instance': ['instance:read', 'instance:configure', 'instance:backup', 'instance:restore'],
  'Notifications': ['notification:read', 'notification:configure-own', 'notification:configure-all'],
  'Invitations': ['invitation:create', 'invitation:revoke', 'invitation:list'],
  'Groups': ['group:read', 'group:create', 'group:rename', 'group:delete', 'group:add-member', 'group:remove-member', 'group:assign-role', 'group:unassign-role'],
  'Roles': ['role:read', 'role:create', 'role:update', 'role:delete', 'role:set-permission', 'role:remove-permission', 'role:assign-user', 'role:unassign-user'],
};

class AdminRolesScreen extends StatefulWidget {
  final UserService userService;
  const AdminRolesScreen({super.key, required this.userService});

  @override
  State<AdminRolesScreen> createState() => _AdminRolesScreenState();
}

class _AdminRolesScreenState extends State<AdminRolesScreen> {
  List<CustomRoleRecord>? _roles;
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
      final roles = await widget.userService.listCustomRoles();
      if (mounted) setState(() { _roles = roles; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _showCreateDialog() {
    showDialog(
      context: context,
      builder: (_) => _CreateRoleDialog(
        userService: widget.userService,
        onCreated: _load,
      ),
    );
  }

  void _showManageDialog(CustomRoleRecord role) {
    showDialog(
      context: context,
      builder: (_) => _RoleManageDialog(
        userService: widget.userService,
        role: role,
        onChanged: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Chip(
                label: Text(
                  _roles == null ? 'Roles' : 'Roles (${_roles!.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Create role'),
                onPressed: _showCreateDialog,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: TextStyle(color: colorScheme.error)),
            ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_roles != null && _roles!.isEmpty)
            const Expanded(child: Center(child: Text('No custom roles yet.')))
          else if (_roles != null)
            Expanded(
              child: ListView.separated(
                itemCount: _roles!.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final role = _roles![i];
                  return _RoleRow(
                    role: role,
                    onManage: () => _showManageDialog(role),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _RoleRow extends StatelessWidget {
  final CustomRoleRecord role;
  final VoidCallback onManage;

  const _RoleRow({required this.role, required this.onManage});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(role.name, style: Theme.of(context).textTheme.bodyLarge),
                    if (role.isSystem) ...[
                      const SizedBox(width: 8),
                      _SystemRoleBadge(),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _InfoChip(
                      label: role.priority != null ? 'Priority ${role.priority}' : 'No priority',
                      color: role.priority != null
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerHighest,
                      textColor: role.priority != null
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    _InfoChip(
                      label: '${role.permissions.length} permissions',
                      color: colorScheme.surfaceContainerHighest,
                      textColor: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    _InfoChip(
                      label: '${role.userCount + role.groupCount} assigned',
                      color: colorScheme.surfaceContainerHighest,
                      textColor: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Tooltip(
            message: role.isSystem ? 'System roles cannot be modified' : '',
            child: OutlinedButton(
              onPressed: role.isSystem ? null : onManage,
              child: const Text('Manage'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;

  const _InfoChip({required this.label, required this.color, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: textColor),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create role dialog
// ---------------------------------------------------------------------------

class _CreateRoleDialog extends StatefulWidget {
  final UserService userService;
  final VoidCallback onCreated;

  const _CreateRoleDialog({required this.userService, required this.onCreated});

  @override
  State<_CreateRoleDialog> createState() => _CreateRoleDialogState();
}

class _CreateRoleDialogState extends State<_CreateRoleDialog> {
  final _nameCtrl = TextEditingController();
  final _priorityCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priorityCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    int? priority;
    if (_priorityCtrl.text.trim().isNotEmpty) {
      priority = int.tryParse(_priorityCtrl.text.trim());
      if (priority == null) {
        setState(() => _error = 'Priority must be a number');
        return;
      }
    }

    final desc = _descCtrl.text.trim();
    setState(() { _saving = true; _error = null; });
    try {
      await widget.userService.createCustomRole(
        name,
        priority: priority,
        description: desc.isEmpty ? null : desc,
      );
      if (mounted) {
        Navigator.of(context).pop();
        widget.onCreated();
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Role'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Role name'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priorityCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Priority (optional)',
                hintText: 'Lower = higher priority',
              ),
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
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Manage role dialog
// ---------------------------------------------------------------------------

class _RoleManageDialog extends StatefulWidget {
  final UserService userService;
  final CustomRoleRecord role;
  final VoidCallback onChanged;

  const _RoleManageDialog({
    required this.userService,
    required this.role,
    required this.onChanged,
  });

  @override
  State<_RoleManageDialog> createState() => _RoleManageDialogState();
}

class _RoleManageDialogState extends State<_RoleManageDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priorityCtrl;
  late final TextEditingController _descCtrl;
  late CustomRoleRecord _role;
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  // Map from action → effect ("allow" | "allow_cascade" | "deny" | "" for none)
  late Map<String, String> _permMap;

  @override
  void initState() {
    super.initState();
    _role = widget.role;
    _nameCtrl = TextEditingController(text: _role.name);
    _priorityCtrl = TextEditingController(
      text: _role.priority != null ? '${_role.priority}' : '',
    );
    _descCtrl = TextEditingController(text: _role.description ?? '');
    _permMap = {for (final p in _role.permissions) p.action: p.effect};
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priorityCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final fresh = await widget.userService.getCustomRole(_role.id);
      if (mounted) {
        setState(() {
          _role = fresh;
          _nameCtrl.text = fresh.name;
          _priorityCtrl.text = fresh.priority != null ? '${fresh.priority}' : '';
          _descCtrl.text = fresh.description ?? '';
          _permMap = {for (final p in fresh.permissions) p.action: p.effect};
        });
      }
    } catch (_) {}
  }

  Future<void> _saveDetails() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    int? priority;
    if (_priorityCtrl.text.trim().isNotEmpty) {
      priority = int.tryParse(_priorityCtrl.text.trim());
      if (priority == null) {
        setState(() => _error = 'Priority must be a number');
        return;
      }
    }

    final desc = _descCtrl.text.trim();
    setState(() { _saving = true; _error = null; });
    try {
      await widget.userService.updateCustomRole(
        _role.id,
        name,
        priority: priority,
        clearPriority: priority == null,
        description: desc.isEmpty ? null : desc,
        clearDescription: desc.isEmpty,
      );
      await _reload();
      widget.onChanged();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete role?'),
        content: Text('Delete "${_role.name}"? This will remove all assignments.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await widget.userService.deleteCustomRole(_role.id);
      if (mounted) {
        Navigator.of(context).pop();
        widget.onChanged();
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _deleting = false; });
    }
  }

  Future<void> _setPermission(String action, String effect) async {
    // Optimistic update
    setState(() {
      if (effect.isEmpty) {
        _permMap.remove(action);
      } else {
        _permMap[action] = effect;
      }
    });
    try {
      if (effect.isEmpty) {
        await widget.userService.removeCustomRolePermission(_role.id, action);
      } else {
        await widget.userService.setCustomRolePermission(_role.id, action, effect);
      }
      widget.onChanged();
    } catch (e) {
      // Revert on failure
      await _reload();
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = colorScheme.outlineVariant.withAlpha(128);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                children: [
                  Text('Manage Role', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Divider(color: borderColor),
            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_error!, style: TextStyle(color: colorScheme.onErrorContainer)),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // --- Details section ---
                    _SectionHeader(label: 'Details'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Role name', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _priorityCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Priority (optional)',
                        hintText: 'Lower number = higher priority; blank = lowest',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _role.id,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant.withAlpha(100),
                            fontFamily: 'monospace',
                          ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Delete role'),
                          style: OutlinedButton.styleFrom(foregroundColor: colorScheme.error),
                          onPressed: _deleting ? null : _delete,
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: _saving ? null : _saveDetails,
                          child: _saving
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Save'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // --- Assignments section ---
                    _SectionHeader(label: 'Assignments'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _InfoChip(
                          label: '${_role.userCount} users',
                          color: colorScheme.surfaceContainerHighest,
                          textColor: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        _InfoChip(
                          label: '${_role.groupCount} groups',
                          color: colorScheme.surfaceContainerHighest,
                          textColor: colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // --- Permissions section ---
                    _SectionHeader(label: 'Permissions'),
                    const SizedBox(height: 4),
                    Text(
                      'Allow ↓ = allow_cascade (inherited through group nesting)',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    ..._actionGroups.entries.map((entry) {
                      return _PermissionGroup(
                        groupName: entry.key,
                        actions: entry.value,
                        permMap: _permMap,
                        onSet: _setPermission,
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Permission group + row
// ---------------------------------------------------------------------------

class _PermissionGroup extends StatefulWidget {
  final String groupName;
  final List<String> actions;
  final Map<String, String> permMap;
  final Future<void> Function(String action, String effect) onSet;

  const _PermissionGroup({
    required this.groupName,
    required this.actions,
    required this.permMap,
    required this.onSet,
  });

  @override
  State<_PermissionGroup> createState() => _PermissionGroupState();
}

class _PermissionGroupState extends State<_PermissionGroup> {
  bool _expanded = false;

  // Count set permissions in this group
  int get _setCount => widget.actions.where((a) => widget.permMap.containsKey(a)).length;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.groupName,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                if (_setCount > 0)
                  _InfoChip(
                    label: '$_setCount set',
                    color: colorScheme.primaryContainer,
                    textColor: colorScheme.onPrimaryContainer,
                  ),
              ],
            ),
          ),
        ),
        if (_expanded)
          ...widget.actions.map((action) => _PermissionRow(
                action: action,
                effect: widget.permMap[action] ?? '',
                onSet: widget.onSet,
              )),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final String action;
  final String effect; // "" | "allow" | "allow_cascade" | "deny"
  final Future<void> Function(String action, String effect) onSet;

  const _PermissionRow({required this.action, required this.effect, required this.onSet});

  // Pretty label: strip the prefix (e.g. "page:read" -> "read")
  String get _label {
    final idx = action.indexOf(':');
    return idx >= 0 ? action.substring(idx + 1) : action;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: 26, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          _EffectToggle(
            effect: effect,
            onChanged: (newEffect) => onSet(action, newEffect),
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
  }
}

class _EffectToggle extends StatelessWidget {
  final String effect;
  final void Function(String) onChanged;
  final ColorScheme colorScheme;

  const _EffectToggle({
    required this.effect,
    required this.onChanged,
    required this.colorScheme,
  });

  static const _effects = ['', 'allow', 'allow_cascade', 'deny'];
  static const _labels = ['—', 'Allow', 'Allow ↓', 'Deny'];

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: List.generate(_effects.length, (i) {
        return ButtonSegment<String>(
          value: _effects[i],
          label: Text(
            _labels[i],
            style: const TextStyle(fontSize: 11),
          ),
        );
      }),
      selected: {effect},
      onSelectionChanged: (s) => onChanged(s.first),
      style: ButtonStyle(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6)),
      ),
      showSelectedIcon: false,
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

class _SystemRoleBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 11, color: colorScheme.onTertiaryContainer),
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

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 0.5,
          ),
    );
  }
}
