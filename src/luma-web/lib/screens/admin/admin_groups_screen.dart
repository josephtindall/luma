import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/group.dart';
import '../../services/user_service.dart';
import '../../widgets/perm_button.dart';

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
    context.go('/admin/groups/${group.id}', extra: group);
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
                PermButton(
                  label: 'Create group',
                  filled: true,
                  enabled: widget.userService.canCreateGroup,
                  requiredPermission: 'group:create',
                  onPressed: _showCreateDialog,
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
                      trailing: PermButton(
                        label: 'Manage',
                        enabled: widget.userService.canEditGroup,
                        requiredPermission: 'group:rename',
                        onPressed: () => _showManageDialog(g),
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

class _SystemBadge extends StatelessWidget {
  const _SystemBadge();

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
