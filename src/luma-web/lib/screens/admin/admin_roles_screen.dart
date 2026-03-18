import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/custom_role.dart';
import '../../services/user_service.dart';

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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final roles = await widget.userService.listCustomRoles();
      if (mounted) {
        setState(() {
          _roles = roles;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load roles. Please try again.';
          _loading = false;
        });
      }
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
    context.go('/admin/roles/${role.id}', extra: role);
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
                    Text(role.name,
                        style: Theme.of(context).textTheme.bodyLarge),
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
                      label: role.priority != null
                          ? 'Priority ${role.priority}'
                          : 'No priority',
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
    setState(() {
      _saving = true;
      _error = null;
    });
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
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _saving = false;
        });
      }
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
              decoration:
                  const InputDecoration(labelText: 'Description (optional)'),
              maxLines: 2,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create'),
        ),
      ],
    );
  }
}

