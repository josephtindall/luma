import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/custom_role.dart';
import '../../services/user_service.dart';

// Canonical action groups for permissions UI
const _actionGroups = <String, List<String>>{
  'Pages': [
    'page:read',
    'page:create',
    'page:edit',
    'page:delete',
    'page:archive',
    'page:version',
    'page:restore-version',
    'page:share',
    'page:transclude'
  ],
  'Tasks': [
    'task:read',
    'task:create',
    'task:edit',
    'task:delete',
    'task:assign',
    'task:close',
    'task:comment'
  ],
  'Flows': [
    'flow:read',
    'flow:create',
    'flow:edit',
    'flow:delete',
    'flow:publish',
    'flow:execute',
    'flow:comment'
  ],
  'Vaults': [
    'vault:read',
    'vault:create',
    'vault:edit',
    'vault:delete',
    'vault:archive',
    'vault:manage-members',
    'vault:manage-roles'
  ],
  'Users': [
    'user:read',
    'user:invite',
    'user:edit',
    'user:delete',
    'user:lock',
    'user:unlock',
    'user:revoke-sessions'
  ],
  'Audit': [
    'audit:read-own',
    'audit:read-all',
    'audit:export-all',
    'audit:read-pii'
  ],
  'Instance': [
    'instance:read',
    'instance:configure',
    'instance:backup',
    'instance:restore'
  ],
  'Notifications': [
    'notification:read',
    'notification:configure-own',
    'notification:configure-all'
  ],
  'Invitations': ['invitation:create', 'invitation:revoke', 'invitation:list'],
  'Groups': [
    'group:read',
    'group:create',
    'group:rename',
    'group:delete',
    'group:add-member',
    'group:remove-member',
    'group:assign-role',
    'group:unassign-role'
  ],
  'Roles': [
    'role:read',
    'role:create',
    'role:update',
    'role:delete',
    'role:set-permission',
    'role:remove-permission',
    'role:assign-user',
    'role:unassign-user'
  ],
};

class AdminRoleDetailScreen extends StatefulWidget {
  final UserService userService;
  final String roleId;
  final CustomRoleRecord? role;

  const AdminRoleDetailScreen({
    super.key,
    required this.userService,
    required this.roleId,
    this.role,
  });

  @override
  State<AdminRoleDetailScreen> createState() => _AdminRoleDetailScreenState();
}

class _AdminRoleDetailScreenState extends State<AdminRoleDetailScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priorityCtrl;
  late final TextEditingController _descCtrl;
  CustomRoleRecord? _role;
  bool _saving = false;
  bool _deleting = false;
  String? _error;
  late Map<String, String> _permMap;

  @override
  void initState() {
    super.initState();
    _role = widget.role;
    _nameCtrl = TextEditingController(text: _role?.name ?? '');
    _priorityCtrl = TextEditingController(
      text: _role?.priority != null ? '${_role!.priority}' : '',
    );
    _descCtrl = TextEditingController(text: _role?.description ?? '');
    _permMap = {
      for (final p in _role?.permissions ?? []) p.action: p.effect
    };

    if (_role == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadRole();
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priorityCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRole() async {
    try {
      final fresh = await widget.userService.getCustomRole(widget.roleId);
      if (mounted) {
        setState(() {
          _role = fresh;
          _nameCtrl.text = fresh.name;
          _priorityCtrl.text =
              fresh.priority != null ? '${fresh.priority}' : '';
          _descCtrl.text = fresh.description ?? '';
          _permMap = {for (final p in fresh.permissions) p.action: p.effect};
        });
      }
    } catch (_) {
      if (mounted) context.go('/admin/roles');
    }
  }

  Future<void> _reload() async {
    try {
      final fresh = await widget.userService.getCustomRole(widget.roleId);
      if (mounted) {
        setState(() {
          _role = fresh;
          _nameCtrl.text = fresh.name;
          _priorityCtrl.text =
              fresh.priority != null ? '${fresh.priority}' : '';
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
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.userService.updateCustomRole(
        widget.roleId,
        name,
        priority: priority,
        clearPriority: priority == null,
        description: desc.isEmpty ? null : desc,
        clearDescription: desc.isEmpty,
      );
      await _reload();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete role?'),
        content: Text(
            'Delete "${_role?.name ?? ''}"? This will remove all assignments.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await widget.userService.deleteCustomRole(widget.roleId);
      if (mounted) context.go('/admin/roles');
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _deleting = false;
        });
      }
    }
  }

  Future<void> _setPermission(String action, String effect) async {
    setState(() {
      if (effect.isEmpty) {
        _permMap.remove(action);
      } else {
        _permMap[action] = effect;
      }
    });
    try {
      if (effect.isEmpty) {
        await widget.userService
            .removeCustomRolePermission(widget.roleId, action);
      } else {
        await widget.userService
            .setCustomRolePermission(widget.roleId, action, effect);
      }
    } catch (e) {
      await _reload();
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_role == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final role = _role!;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/admin/roles')),
        title: Text(role.name),
        actions: [
          if (role.isSystem)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _SystemRoleBadge(),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_error!,
                        style:
                            TextStyle(color: colorScheme.onErrorContainer)),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Details ──────────────────────────────────────────────
                _SectionHeader(label: 'Details'),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameCtrl,
                  enabled: !role.isSystem,
                  decoration: const InputDecoration(
                      labelText: 'Role name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _priorityCtrl,
                  enabled: !role.isSystem,
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
                  enabled: !role.isSystem,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 6),
                Text(
                  role.id,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withAlpha(100),
                        fontFamily: 'monospace',
                      ),
                ),
                const SizedBox(height: 12),
                if (!role.isSystem)
                  Row(
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Delete role'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: colorScheme.error),
                        onPressed: _deleting ? null : _delete,
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _saving ? null : _saveDetails,
                        child: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Save'),
                      ),
                    ],
                  ),

                const SizedBox(height: 32),
                Divider(color: colorScheme.outlineVariant),
                const SizedBox(height: 16),

                // ── Assignments ───────────────────────────────────────────
                _SectionHeader(label: 'Assignments'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _InfoChip(
                      label: '${role.userCount} users',
                      color: colorScheme.surfaceContainerHighest,
                      textColor: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    _InfoChip(
                      label: '${role.groupCount} groups',
                      color: colorScheme.surfaceContainerHighest,
                      textColor: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),

                const SizedBox(height: 32),
                Divider(color: colorScheme.outlineVariant),
                const SizedBox(height: 16),

                // ── Permissions ───────────────────────────────────────────
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
                    readOnly: role.isSystem,
                    onSet: _setPermission,
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Permission group + row ────────────────────────────────────────────────────

class _PermissionGroup extends StatefulWidget {
  final String groupName;
  final List<String> actions;
  final Map<String, String> permMap;
  final bool readOnly;
  final Future<void> Function(String action, String effect) onSet;

  const _PermissionGroup({
    required this.groupName,
    required this.actions,
    required this.permMap,
    required this.readOnly,
    required this.onSet,
  });

  @override
  State<_PermissionGroup> createState() => _PermissionGroupState();
}

class _PermissionGroupState extends State<_PermissionGroup> {
  bool _expanded = false;

  int get _setCount =>
      widget.actions.where((a) => widget.permMap.containsKey(a)).length;

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
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
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
                readOnly: widget.readOnly,
                onSet: widget.onSet,
              )),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final String action;
  final String effect;
  final bool readOnly;
  final Future<void> Function(String action, String effect) onSet;

  const _PermissionRow({
    required this.action,
    required this.effect,
    required this.readOnly,
    required this.onSet,
  });

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
            readOnly: readOnly,
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
  final bool readOnly;
  final void Function(String) onChanged;
  final ColorScheme colorScheme;

  const _EffectToggle({
    required this.effect,
    required this.readOnly,
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
      onSelectionChanged: readOnly ? null : (s) => onChanged(s.first),
      style: ButtonStyle(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        padding:
            const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6)),
      ),
      showSelectedIcon: false,
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

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

class _InfoChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;

  const _InfoChip(
      {required this.label, required this.color, required this.textColor});

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
        style:
            Theme.of(context).textTheme.labelSmall?.copyWith(color: textColor),
      ),
    );
  }
}
