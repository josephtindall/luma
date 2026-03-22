import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/user.dart';
import '../../services/user_service.dart';
import '../../widgets/perm_button.dart';
import '../../theme/tokens.dart';
import '../../widgets/user_avatar.dart';

class AdminUsersScreen extends StatefulWidget {
  final UserService userService;

  const AdminUsersScreen({super.key, required this.userService});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  late Future<List<AdminUserRecord>> _usersFuture;

  @override
  void initState() {
    super.initState();
    _usersFuture = widget.userService.listAdminUsers();
  }

  void _reload() {
    setState(() {
      _usersFuture = widget.userService.listAdminUsers();
    });
  }

  void _showManageDialog(AdminUserRecord user) {
    context.go('/admin/users/${user.id}', extra: user);
  }

  void _showCreateUserDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => _CreateUserDialog(userService: widget.userService),
    ).then((_) => _reload());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AdminUserRecord>>(
      future: _usersFuture,
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
                  'Could not load users: ${snap.error}',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _reload, child: const Text('Retry')),
              ],
            ),
          );
        }

        final users = snap.data ?? [];

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Chip(
                    label: Text('Users (${users.length})'),
                    backgroundColor:
                        Theme.of(context).colorScheme.secondaryContainer,
                  ),
                  const Spacer(),
                  PermButton(
                    label: 'Create user',
                    filled: true,
                    enabled: widget.userService.canCreateUser,
                    requiredPermission: 'user:invite',
                    onPressed: _showCreateUserDialog,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: users.isEmpty
                    ? const Center(child: Text('No users yet'))
                    : ListView.separated(
                        itemCount: users.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (_, i) => _UserRow(
                          user: users[i],
                          isSelf: widget.userService.profile?.id ==
                              users[i].id,
                          canManage: widget.userService.canEditUser,
                          onManage: () => _showManageDialog(users[i]),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── User row ─────────────────────────────────────────────────────────────────

class _UserRow extends StatelessWidget {
  final AdminUserRecord user;
  final bool isSelf;
  final bool canManage;
  final VoidCallback onManage;

  const _UserRow({
    required this.user,
    required this.isSelf,
    required this.canManage,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          UserAvatar(
            avatarSeed: user.avatarSeed,
            displayName: user.displayName,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      user.displayName,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: 6),
                      Chip(
                        label: const Text('You'),
                        padding: EdgeInsets.zero,
                        labelPadding:
                            const EdgeInsets.symmetric(horizontal: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ],
                ),
                Text(
                  user.email,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Wrap(
            spacing: 6,
            children: [
              if (user.isOwner)
                _Badge(
                    label: 'Owner',
                    color: cs.primaryContainer,
                    textColor: cs.onPrimaryContainer),
              if (user.mfaEnabled)
                _Badge(
                    label: 'MFA',
                    color: cs.secondaryContainer,
                    textColor: cs.onSecondaryContainer),
              if (user.isLocked)
                _Badge(
                    label: 'Locked',
                    color: cs.errorContainer,
                    textColor: cs.onErrorContainer),
              if (user.forcePasswordChange)
                _Badge(
                    label: 'Pwd change',
                    color: cs.tertiaryContainer,
                    textColor: cs.onTertiaryContainer),
            ],
          ),
          const SizedBox(width: 8),
          PermButton(
            label: 'Manage',
            enabled: canManage,
            requiredPermission: 'user:edit',
            onPressed: onManage,
          ),
        ],
      ),
    );
  }
}

// ── Create user dialog ────────────────────────────────────────────────────────

class _CreateUserDialog extends StatefulWidget {
  final UserService userService;

  const _CreateUserDialog({required this.userService});

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _forceChange = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _pwdCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.userService.adminCreateUser(
        email: _emailCtrl.text.trim(),
        displayName: _nameCtrl.text.trim(),
        password: _pwdCtrl.text,
        forcePasswordChange: _forceChange,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('Create user', style: theme.textTheme.titleLarge),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autofocus: true,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Display name (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pwdCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v.length < 8) return 'At least 8 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v != _pwdCtrl.text ? 'Passwords do not match' : null,
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title:
                      const Text('Require password change on first login'),
                  value: _forceChange,
                  onChanged: (v) =>
                      setState(() => _forceChange = v ?? false),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: TextStyle(color: cs.error),
                      textAlign: TextAlign.center),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Create user'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Badge ─────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;

  const _Badge({
    required this.label,
    required this.color,
    required this.textColor,
  });

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
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: textColor),
      ),
    );
  }
}
