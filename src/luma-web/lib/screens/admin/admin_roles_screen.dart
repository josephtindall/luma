import 'package:flutter/material.dart';

import '../../models/custom_role.dart';
import '../../services/user_service.dart';
import '../../theme/tokens.dart';
import '../../widgets/perm_button.dart';
import '../../widgets/permission_matrix.dart';
import '../../widgets/slideout_panel.dart';

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
      if (mounted) setState(() { _error = 'Could not load roles. Please try again.'; _loading = false; });
    }
  }

  void _showCreateRoleSlideout() {
    final titleNotifier = ValueNotifier('Create role');
    showSlideoutPanel(
      context: context,
      titleNotifier: titleNotifier,
      bodyBuilder: (_) => _CreateRoleContent(
        userService: widget.userService,
        titleNotifier: titleNotifier,
        onCreated: (role) {
          _load();
          return _RoleDetailContent(
            roleId: role.id,
            role: role,
            userService: widget.userService,
            onChanged: _load,
          );
        },
      ),
    ).whenComplete(() => titleNotifier.dispose());
  }

  void _showRoleSlideout(CustomRoleRecord role) {
    showSlideoutPanel(
      context: context,
      title: role.name,
      bodyBuilder: (_) => _RoleDetailContent(
        roleId: role.id,
        role: role,
        userService: widget.userService,
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Roles',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      '${_roles?.length ?? 0} total \u00b7 Configure permission roles.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              PermButton(
                label: 'Create role',
                filled: true,
                enabled: widget.userService.canCreateRole,
                requiredPermission: 'role:create',
                onPressed: _showCreateRoleSlideout,
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
                    canManage: widget.userService.canEditRole,
                    onManage: () => _showRoleSlideout(role),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ── Role detail content (slideout body) ──────────────────────────────────────

class _RoleDetailContent extends StatefulWidget {
  final String roleId;
  final CustomRoleRecord? role;
  final UserService userService;
  final VoidCallback onChanged;

  const _RoleDetailContent({
    required this.roleId,
    this.role,
    required this.userService,
    required this.onChanged,
  });

  @override
  State<_RoleDetailContent> createState() => _RoleDetailContentState();
}

class _RoleDetailContentState extends State<_RoleDetailContent> {
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
          _priorityCtrl.text = fresh.priority != null ? '${fresh.priority}' : '';
          _descCtrl.text = fresh.description ?? '';
          _permMap = {for (final p in fresh.permissions) p.action: p.effect};
        });
      }
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _reload() async {
    try {
      final fresh = await widget.userService.getCustomRole(widget.roleId);
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
        widget.roleId,
        name,
        priority: priority,
        clearPriority: priority == null,
        description: desc.isEmpty ? null : desc,
        clearDescription: desc.isEmpty,
      );
      await _reload();
      widget.onChanged();
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
        content: Text('Delete "${_role?.name ?? ''}"? This will remove all assignments.'),
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
      widget.onChanged();
      if (mounted) Navigator.of(context).pop();
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
        await widget.userService.removeCustomRolePermission(widget.roleId, action);
      } else {
        await widget.userService.setCustomRolePermission(widget.roleId, action, effect);
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
      return const Center(child: CircularProgressIndicator());
    }

    final role = _role!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (role.isSystem)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SystemRoleBadge(),
            ),

          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: LumaRadius.radiusMd,
              ),
              child: Text(_error!,
                  style: TextStyle(color: colorScheme.onErrorContainer)),
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
                  style: OutlinedButton.styleFrom(foregroundColor: colorScheme.error),
                  onPressed: _deleting ? null : _delete,
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _saveDetails,
                  child: _saving
                      ? const SizedBox(
                          width: 16, height: 16,
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
          PermissionMatrix(
            permMap: _permMap,
            readOnly: role.isSystem,
            onSet: _setPermission,
          ),
        ],
      ),
    );
  }
}

// ── Role row ─────────────────────────────────────────────────────────────────

class _RoleRow extends StatelessWidget {
  final CustomRoleRecord role;
  final bool canManage;
  final VoidCallback onManage;

  const _RoleRow({required this.role, required this.canManage, required this.onManage});

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
          if (role.isSystem)
            Tooltip(
              message: 'System roles cannot be modified',
              child: OutlinedButton.icon(
                icon: const Icon(Icons.lock_outline, size: 14),
                label: const Text('Manage'),
                onPressed: null,
              ),
            )
          else
            PermButton(
              label: 'Manage',
              enabled: canManage,
              requiredPermission: 'role:update',
              onPressed: onManage,
            ),
        ],
      ),
    );
  }
}

// ── Create role slideout content ──────────────────────────────────────────────

class _CreateRoleContent extends StatefulWidget {
  final UserService userService;
  final ValueNotifier<String> titleNotifier;
  final Widget Function(CustomRoleRecord role) onCreated;

  const _CreateRoleContent({
    required this.userService,
    required this.titleNotifier,
    required this.onCreated,
  });

  @override
  State<_CreateRoleContent> createState() => _CreateRoleContentState();
}

class _CreateRoleContentState extends State<_CreateRoleContent> {
  final _nameCtrl = TextEditingController();
  final _priorityCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _saving = false;
  String? _error;
  Widget? _detailView;

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
      final role = await widget.userService.createCustomRole(
        name,
        priority: priority,
        description: desc.isEmpty ? null : desc,
      );
      if (!mounted) return;
      widget.titleNotifier.value = role.name;
      setState(() => _detailView = widget.onCreated(role));
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
    if (_detailView != null) return _detailView!;

    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
            Text(_error!, style: TextStyle(color: cs.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Create role'),
          ),
        ],
      ),
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
        borderRadius: LumaRadius.radiusLg,
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
        borderRadius: LumaRadius.radiusLg,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: textColor),
      ),
    );
  }
}
