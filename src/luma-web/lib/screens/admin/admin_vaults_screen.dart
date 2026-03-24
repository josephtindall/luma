import 'package:flutter/material.dart';

import '../../services/page_service.dart' show VaultMemberDetail, VaultGroupMemberDetail;
import '../../services/user_service.dart';
import '../../theme/tokens.dart';
import '../../widgets/data_table.dart';
import '../../widgets/pagination.dart';
import '../../widgets/perm_button.dart';
import '../../widgets/slideout_panel.dart';

class AdminVaultsScreen extends StatefulWidget {
  final UserService userService;

  const AdminVaultsScreen({super.key, required this.userService});

  @override
  State<AdminVaultsScreen> createState() => _AdminVaultsScreenState();
}

class _AdminVaultsScreenState extends State<AdminVaultsScreen> {
  late Future<List<AdminVaultRecord>> _vaultsFuture;
  int _currentPage = 0;
  static const _pageSize = 25;

  @override
  void initState() {
    super.initState();
    _vaultsFuture = widget.userService.listAllVaults();
  }

  void _reload() {
    setState(() {
      _vaultsFuture = widget.userService.listAllVaults();
      _currentPage = 0;
    });
  }

  void _showCreateVaultSlideout() {
    final titleNotifier = ValueNotifier('Create vault');
    showSlideoutPanel(
      context: context,
      titleNotifier: titleNotifier,
      bodyBuilder: (_) => _CreateVaultContent(
        userService: widget.userService,
        titleNotifier: titleNotifier,
        onCreated: (vault) {
          _reload();
          return _VaultDetailContent(
            vault: vault,
            userService: widget.userService,
            onChanged: _reload,
          );
        },
      ),
    ).whenComplete(() => titleNotifier.dispose());
  }

  void _showVaultSlideout(AdminVaultRecord vault) {
    showSlideoutPanel(
      context: context,
      title: vault.name,
      bodyBuilder: (_) => _VaultDetailContent(
        vault: vault,
        userService: widget.userService,
        onChanged: _reload,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return FutureBuilder<List<AdminVaultRecord>>(
      future: _vaultsFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Could not load vaults: ${snap.error}',
                  style: TextStyle(color: cs.error),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _reload, child: const Text('Retry')),
              ],
            ),
          );
        }

        final vaults = snap.data ?? [];
        final totalPages = (vaults.length / _pageSize).ceil().clamp(1, 999);
        final pageStart = _currentPage * _pageSize;
        final pageVaults = vaults.sublist(
          pageStart, (pageStart + _pageSize).clamp(0, vaults.length));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Vaults',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          '${vaults.length} total \u00b7 Manage all vaults in the instance.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  PermButton(
                    label: 'Create vault',
                    filled: true,
                    enabled: widget.userService.canManageVaults,
                    requiredPermission: 'vault:create',
                    onPressed: _showCreateVaultSlideout,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: vaults.isEmpty
                    ? const Center(child: Text('No vaults found.'))
                          : LumaDataTable<AdminVaultRecord>(
                              onRowTap: _showVaultSlideout,
                              columns: [
                                LumaColumn<AdminVaultRecord>(
                                  label: 'Name',
                                  cellBuilder: (v, _) => Text(
                                    v.name,
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                LumaColumn<AdminVaultRecord>(
                                  label: 'Slug',
                                  width: 160,
                                  cellBuilder: (v, _) => Text(
                                    v.slug,
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(fontFamily: 'monospace'),
                                  ),
                                ),
                                LumaColumn<AdminVaultRecord>(
                                  label: 'Visibility',
                                  width: 120,
                                  cellBuilder: (v, _) => Align(
                                    alignment: Alignment.centerLeft,
                                    child: _VisibilityBadge(
                                        isPrivate: v.isPrivate),
                                  ),
                                ),
                                LumaColumn<AdminVaultRecord>(
                                  label: 'Created',
                                  width: 120,
                                  cellBuilder: (v, _) => Text(
                                    _formatDate(v.createdAt),
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                                LumaColumn<AdminVaultRecord>(
                                  label: '',
                                  width: 100,
                                  cellBuilder: (v, _) => Align(
                                    alignment: Alignment.centerRight,
                                    child: OutlinedButton(
                                      onPressed: () => _showVaultSlideout(v),
                                      child: const Text('Manage'),
                                    ),
                                  ),
                                ),
                              ],
                              rows: pageVaults,
                            ),
              ),
            ],
          ),
        ),
            ),
            LumaPagination(
              currentPage: _currentPage,
              totalPages: totalPages,
              onPageChanged: (p) =>
                  setState(() => _currentPage = p),
            ),
          ],
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

// ── Vault detail content (slideout body) ─────────────────────────────────────

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

class _VaultDetailContent extends StatefulWidget {
  final AdminVaultRecord vault;
  final UserService userService;
  final VoidCallback onChanged;

  const _VaultDetailContent({
    required this.vault,
    required this.userService,
    required this.onChanged,
  });

  @override
  State<_VaultDetailContent> createState() => _VaultDetailContentState();
}

class _VaultDetailContentState extends State<_VaultDetailContent> {
  final _nameCtrl = TextEditingController();
  bool _isPrivate = true;
  bool _loading = true;
  bool _saving = false;
  bool _archiving = false;
  String? _error;

  List<VaultMemberDetail> _members = [];
  List<VaultGroupMemberDetail> _groupMembers = [];

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.vault.name;
    _isPrivate = widget.vault.isPrivate;
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        widget.userService.adminListVaultMembers(widget.vault.id),
        widget.userService.adminListVaultGroupMembers(widget.vault.id),
      ]);
      if (mounted) {
        setState(() {
          _members = results[0] as List<VaultMemberDetail>;
          _groupMembers = (results[1] as List<VaultGroupMemberDetail>)
              .where((g) => !g.groupId.startsWith('system:'))
              .toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load vault details.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.userService.adminUpdateVault(
        widget.vault.id,
        name: _nameCtrl.text.trim(),
        isPrivate: _isPrivate,
      );
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved')),
        );
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _archive() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive vault'),
        content: const Text(
          'This vault and all its content will be archived. This cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _archiving = true);
    try {
      await widget.userService.adminArchiveVault(widget.vault.id);
      widget.onChanged();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        _showError(e.toString());
        setState(() => _archiving = false);
      }
    }
  }

  Future<void> _changeRole(VaultMemberDetail m, String newRole) async {
    try {
      await widget.userService.adminUpdateMemberRole(
          widget.vault.id, m.userId, newRole);
      await _load();
      widget.onChanged();
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  Future<void> _removeMember(VaultMemberDetail m) async {
    final name = m.displayName.isNotEmpty ? m.displayName : m.userId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member'),
        content: Text('Remove $name from this vault?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.userService.adminRemoveVaultMember(widget.vault.id, m.userId);
      await _load();
      widget.onChanged();
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  Future<void> _changeGroupRole(VaultGroupMemberDetail g, String newRole) async {
    try {
      await widget.userService.adminUpdateGroupMemberRole(
          widget.vault.id, g.groupId, newRole);
      await _load();
      widget.onChanged();
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  Future<void> _removeGroupMember(VaultGroupMemberDetail g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove group'),
        content: Text('Remove ${g.groupName} from this vault?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.userService.adminRemoveVaultGroupMember(
          widget.vault.id, g.groupId);
      await _load();
      widget.onChanged();
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  void _showError(String msg) {
    final display = msg.replaceFirst('Exception: ', '');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(display.isEmpty ? 'Something went wrong.' : display),
      backgroundColor: Theme.of(context).colorScheme.error,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: cs.error)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Name + Privacy ───────────────────────
          Text('General', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Vault name',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Private vault'),
            subtitle: const Text('Only members can view content'),
            value: _isPrivate,
            onChanged: (v) => setState(() => _isPrivate = v),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save changes'),
            ),
          ),

          const Divider(height: 40),

          // ── Members ──────────────────────────────────
          Text('Members', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          if (_members.isEmpty)
            Text('No user members', style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant))
          else
            ..._members.map((m) {
              final name = m.displayName.isNotEmpty ? m.displayName : m.userId;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: CircleAvatar(
                  radius: 16,
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 13)),
                ),
                title: Text(name),
                subtitle: m.email.isNotEmpty ? Text(m.email) : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButton<String>(
                      value: _kRoles.any((r) => r.id == m.roleId)
                          ? m.roleId : null,
                      hint: Text(_roleLabel(m.roleId)),
                      items: _kRoles
                          .map((r) => DropdownMenuItem(
                                value: r.id, child: Text(r.label)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) _changeRole(m, v);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.person_remove_outlined, size: 18),
                      onPressed: () => _removeMember(m),
                    ),
                  ],
                ),
              );
            }),

          const Divider(height: 32),

          // ── Group Members ────────────────────────────
          Text('Groups', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          if (_groupMembers.isEmpty)
            Text('No group members', style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant))
          else
            ..._groupMembers.map((g) {
              final name = g.groupName.isNotEmpty ? g.groupName : g.groupId;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const CircleAvatar(
                  radius: 16,
                  child: Icon(Icons.group_outlined, size: 16),
                ),
                title: Text(name),
                subtitle: const Text('Group'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButton<String>(
                      value: _kRoles.any((r) => r.id == g.roleId)
                          ? g.roleId : null,
                      hint: Text(_roleLabel(g.roleId)),
                      items: _kRoles
                          .map((r) => DropdownMenuItem(
                                value: r.id, child: Text(r.label)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) _changeGroupRole(g, v);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.group_remove_outlined, size: 18),
                      onPressed: () => _removeGroupMember(g),
                    ),
                  ],
                ),
              );
            }),

          const Divider(height: 40),

          // ── Danger zone ──────────────────────────────
          Text('Danger zone',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: cs.error)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.error,
              side: BorderSide(color: cs.error),
            ),
            onPressed: _archiving ? null : _archive,
            icon: _archiving
                ? SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: cs.error))
                : const Icon(Icons.archive_outlined),
            label: const Text('Archive vault'),
          ),
          const SizedBox(height: 4),
          Text(
            'Archiving hides the vault and all its content. This cannot be undone.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Create vault slideout content ─────────────────────────────────────────────

class _CreateVaultContent extends StatefulWidget {
  final UserService userService;
  final ValueNotifier<String> titleNotifier;
  final Widget Function(AdminVaultRecord vault) onCreated;

  const _CreateVaultContent({
    required this.userService,
    required this.titleNotifier,
    required this.onCreated,
  });

  @override
  State<_CreateVaultContent> createState() => _CreateVaultContentState();
}

class _CreateVaultContentState extends State<_CreateVaultContent> {
  final _nameCtrl = TextEditingController();
  bool _isPrivate = true;
  bool _saving = false;
  String? _error;
  Widget? _detailView;

  @override
  void dispose() { _nameCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() { _saving = true; _error = null; });
    try {
      final vault = await widget.userService.createVault(
        _nameCtrl.text.trim(),
        isPrivate: _isPrivate,
      );
      if (!mounted) return;
      widget.titleNotifier.value = vault.name;
      setState(() => _detailView = widget.onCreated(vault));
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _saving = false;
      });
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
            decoration: const InputDecoration(labelText: 'Vault name'),
            autofocus: true,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Private vault'),
            subtitle: const Text('Only members can view content'),
            value: _isPrivate,
            onChanged: (v) => setState(() => _isPrivate = v),
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
                : const Text('Create vault'),
          ),
        ],
      ),
    );
  }
}

// ── Visibility badge ──────────────────────────────────────────────────────────

class _VisibilityBadge extends StatelessWidget {
  final bool isPrivate;

  const _VisibilityBadge({required this.isPrivate});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isPrivate
            ? cs.surfaceContainerHighest
            : cs.primaryContainer,
        borderRadius: LumaRadius.radiusLg,
      ),
      child: Text(
        isPrivate ? 'Private' : 'Shared',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isPrivate
                  ? cs.onSurfaceVariant
                  : cs.onPrimaryContainer,
            ),
      ),
    );
  }
}
