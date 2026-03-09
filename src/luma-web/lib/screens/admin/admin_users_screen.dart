import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/custom_role.dart';
import '../../models/user.dart';
import '../../services/user_service.dart';
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
    showDialog<void>(
      context: context,
      builder: (_) => _UserManageDialog(
        user: user,
        userService: widget.userService,
        isSelf: widget.userService.profile?.id == user.id,
        onChanged: _reload,
      ),
    );
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

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Users',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(width: 12),
                      Chip(label: Text('${users.length}')),
                      const Spacer(),
                      FilledButton.icon(
                        icon: const Icon(Icons.person_add_outlined),
                        label: const Text('Create user'),
                        onPressed: _showCreateUserDialog,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (int i = 0; i < users.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          _UserRow(
                            user: users[i],
                            isSelf: widget.userService.profile?.id ==
                                users[i].id,
                            onManage: () => _showManageDialog(users[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
  final VoidCallback onManage;

  const _UserRow({
    required this.user,
    required this.isSelf,
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
          OutlinedButton(
            onPressed: onManage,
            child: const Text('Manage'),
          ),
        ],
      ),
    );
  }
}

// ── User manage dialog ────────────────────────────────────────────────────────

class _UserManageDialog extends StatefulWidget {
  final AdminUserRecord user;
  final UserService userService;
  final bool isSelf;
  final VoidCallback onChanged;

  const _UserManageDialog({
    required this.user,
    required this.userService,
    required this.isSelf,
    required this.onChanged,
  });

  @override
  State<_UserManageDialog> createState() => _UserManageDialogState();
}

class _UserManageDialogState extends State<_UserManageDialog> {
  bool _loading = false;
  PasswordResetLinkResult? _resetLink;

  // Custom roles
  List<CustomRoleRecord>? _userRoles;
  List<CustomRoleRecord>? _allRoles;
  String? _addRoleId;
  bool _addingRole = false;

  @override
  void initState() {
    super.initState();
    _loadCustomRoles();
  }

  Future<void> _loadCustomRoles() async {
    try {
      final results = await Future.wait([
        widget.userService.getUserCustomRoles(widget.user.id),
        widget.userService.listCustomRoles(),
      ]);
      if (mounted) {
        setState(() {
          _userRoles = results[0];
          _allRoles = results[1];
        });
      }
    } catch (_) {}
  }

  Future<void> _removeCustomRole(String roleId) async {
    try {
      await widget.userService.removeCustomRoleFromUser(widget.user.id, roleId);
      await _loadCustomRoles();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    }
  }

  Future<void> _assignCustomRole() async {
    if (_addRoleId == null) return;
    setState(() => _addingRole = true);
    try {
      await widget.userService.assignCustomRoleToUser(widget.user.id, _addRoleId!);
      setState(() => _addRoleId = null);
      await _loadCustomRoles();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _addingRole = false);
    }
  }

  Future<void> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
    required Future<void> Function() action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlg) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlg, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: confirmColor),
            onPressed: () => Navigator.pop(dlg, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _loading = true);
    try {
      await action();
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    }
  }

  Future<void> _createResetLink() async {
    setState(() {
      _loading = true;
      _resetLink = null;
    });
    try {
      final result =
          await widget.userService.adminCreatePasswordResetLink(widget.user.id);
      if (mounted) setState(() => _resetLink = result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final u = widget.user;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                children: [
                  UserAvatar(
                      avatarSeed: u.avatarSeed,
                      displayName: u.displayName,
                      size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(u.displayName,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        Text(u.email,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionHeader(label: 'Account'),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, children: [
                      if (u.isOwner)
                        _Badge(
                            label: 'Owner',
                            color: cs.primaryContainer,
                            textColor: cs.onPrimaryContainer),
                      if (u.mfaEnabled)
                        _Badge(
                            label: 'MFA enabled',
                            color: cs.secondaryContainer,
                            textColor: cs.onSecondaryContainer),
                      if (u.isLocked)
                        _Badge(
                            label: 'Locked',
                            color: cs.errorContainer,
                            textColor: cs.onErrorContainer),
                      if (u.forcePasswordChange)
                        _Badge(
                            label: 'Password change pending',
                            color: cs.tertiaryContainer,
                            textColor: cs.onTertiaryContainer),
                    ]),
                    const SizedBox(height: 12),
                    if (u.isLocked)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.lock_open_outlined),
                        label: const Text('Unlock account'),
                        onPressed: widget.isSelf || _loading
                            ? null
                            : () => _confirm(
                                  title: 'Unlock account',
                                  message:
                                      'Allow ${u.displayName} to log in again?',
                                  confirmLabel: 'Unlock',
                                  confirmColor: cs.primary,
                                  action: () =>
                                      widget.userService.unlockUser(u.id),
                                ),
                      )
                    else
                      OutlinedButton.icon(
                        icon: Icon(Icons.lock_outlined,
                            color: widget.isSelf ? null : cs.error),
                        label: Text('Lock account',
                            style: TextStyle(
                                color: widget.isSelf ? null : cs.error)),
                        onPressed: widget.isSelf || _loading
                            ? null
                            : () => _confirm(
                                  title: 'Lock account',
                                  message:
                                      'This will immediately revoke all sessions for '
                                      '${u.displayName} and prevent them from logging in.',
                                  confirmLabel: 'Lock',
                                  confirmColor: cs.error,
                                  action: () =>
                                      widget.userService.lockUser(u.id),
                                ),
                      ),
                    const SizedBox(height: 20),
                    _SectionHeader(label: 'Password'),
                    const SizedBox(height: 8),
                    if (_resetLink != null) ...[
                      _PasswordResetPanel(
                        result: _resetLink!,
                        onRegenerate: _createResetLink,
                        loading: _loading,
                      ),
                      const SizedBox(height: 8),
                    ],
                    OutlinedButton.icon(
                      icon: const Icon(Icons.link_outlined),
                      label: Text(_resetLink == null
                          ? 'Create reset link'
                          : 'Regenerate link'),
                      onPressed: _loading ? null : _createResetLink,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.password_outlined),
                      label:
                          const Text('Force password change on next login'),
                      onPressed: widget.isSelf || _loading
                          ? null
                          : () => _confirm(
                                title: 'Force password change',
                                message:
                                    '${u.displayName} will be required to set a new '
                                    'password on their next login attempt. '
                                    'All current sessions will be revoked.',
                                confirmLabel: 'Force change',
                                confirmColor: cs.primary,
                                action: () => widget.userService
                                    .adminForcePasswordChange(u.id),
                              ),
                    ),
                    const SizedBox(height: 20),
                    _SectionHeader(label: 'Sessions'),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: Icon(Icons.devices_outlined,
                          color: widget.isSelf ? null : cs.error),
                      label: Text('Revoke all sessions',
                          style: TextStyle(
                              color: widget.isSelf ? null : cs.error)),
                      onPressed: widget.isSelf || _loading
                          ? null
                          : () => _confirm(
                                title: 'Revoke all sessions',
                                message:
                                    'Sign ${u.displayName} out of all devices immediately? '
                                    'They can log in again normally.',
                                confirmLabel: 'Revoke',
                                confirmColor: cs.error,
                                action: () => widget.userService
                                    .revokeUserSessions(u.id),
                              ),
                    ),
                    const SizedBox(height: 20),
                    _SectionHeader(label: 'MFA & Passkeys'),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: Icon(Icons.phonelink_lock_outlined,
                          color: (widget.isSelf ||
                                  u.totpCount == 0 ||
                                  _loading)
                              ? null
                              : cs.error),
                      label: Text(
                        'Remove authenticator apps (${u.totpCount})',
                        style: TextStyle(
                            color: (widget.isSelf ||
                                    u.totpCount == 0 ||
                                    _loading)
                                ? null
                                : cs.error),
                      ),
                      onPressed:
                          (widget.isSelf || u.totpCount == 0 || _loading)
                              ? null
                              : () => _confirm(
                                    title: 'Remove authenticator apps',
                                    message:
                                        'Remove all ${u.totpCount} TOTP authenticator '
                                        'app(s) for ${u.displayName}? '
                                        'They will lose MFA if no passkeys remain.',
                                    confirmLabel: 'Remove',
                                    confirmColor: cs.error,
                                    action: () => widget.userService
                                        .adminDeleteAllTOTP(u.id),
                                  ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: Icon(Icons.fingerprint_outlined,
                          color: (widget.isSelf ||
                                  u.passkeyCount == 0 ||
                                  _loading)
                              ? null
                              : cs.error),
                      label: Text(
                        'Remove passkeys (${u.passkeyCount})',
                        style: TextStyle(
                            color: (widget.isSelf ||
                                    u.passkeyCount == 0 ||
                                    _loading)
                                ? null
                                : cs.error),
                      ),
                      onPressed:
                          (widget.isSelf || u.passkeyCount == 0 || _loading)
                              ? null
                              : () => _confirm(
                                    title: 'Remove passkeys',
                                    message:
                                        'Revoke all ${u.passkeyCount} passkey(s) for '
                                        '${u.displayName}? '
                                        'They will lose MFA if no authenticator apps remain.',
                                    confirmLabel: 'Remove',
                                    confirmColor: cs.error,
                                    action: () => widget.userService
                                        .adminRevokeAllPasskeys(u.id),
                                  ),
                    ),
                    const SizedBox(height: 20),
                    _SectionHeader(label: 'Custom Roles'),
                    const SizedBox(height: 8),
                    if (_userRoles == null)
                      const SizedBox(
                        height: 24,
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    else ...[
                      if (_userRoles!.isEmpty)
                        Text('No custom roles assigned.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant))
                      else
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: _userRoles!.map((role) {
                            return Chip(
                              label: Text(role.name),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () => _removeCustomRole(role.id),
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 8),
                      if (_allRoles != null) ...[
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _addRoleId,
                                decoration: const InputDecoration(
                                  labelText: 'Add role',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: _allRoles!
                                    .where((r) => _userRoles!
                                        .every((ur) => ur.id != r.id))
                                    .map((r) => DropdownMenuItem(
                                          value: r.id,
                                          child: Text(r.name),
                                        ))
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => _addRoleId = v),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: (_addRoleId == null || _addingRole)
                                  ? null
                                  : _assignCustomRole,
                              child: _addingRole
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Text('Assign'),
                            ),
                          ],
                        ),
                      ],
                    ],
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

// ── Password reset panel ──────────────────────────────────────────────────────

class _PasswordResetPanel extends StatefulWidget {
  final PasswordResetLinkResult result;
  final VoidCallback onRegenerate;
  final bool loading;

  const _PasswordResetPanel({
    required this.result,
    required this.onRegenerate,
    required this.loading,
  });

  @override
  State<_PasswordResetPanel> createState() => _PasswordResetPanelState();
}

class _PasswordResetPanelState extends State<_PasswordResetPanel> {
  bool _copied = false;

  String get _resetUrl =>
      '${Uri.base.origin}/reset-password?token=${widget.result.token}';

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _resetUrl));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Password reset URL',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  _resetUrl,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFamily: 'monospace'),
                ),
              ),
              IconButton(
                icon: Icon(_copied ? Icons.check : Icons.copy_outlined),
                tooltip: _copied ? 'Copied!' : 'Copy',
                onPressed: _copy,
              ),
              IconButton(
                icon: widget.loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_outlined),
                tooltip: 'Regenerate',
                onPressed: widget.loading ? null : widget.onRegenerate,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: QrImageView(
              data: _resetUrl,
              size: 160,
              backgroundColor: Colors.white,
            ),
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
      setState(() => _error = e.toString());
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

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context)
          .textTheme
          .labelMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
        borderRadius: BorderRadius.circular(12),
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
