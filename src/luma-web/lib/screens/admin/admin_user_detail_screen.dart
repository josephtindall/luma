import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/custom_role.dart';
import '../../models/user.dart';
import '../../services/user_service.dart';
import '../../widgets/user_avatar.dart';

class AdminUserDetailScreen extends StatefulWidget {
  final UserService userService;
  final AdminUserRecord? user;
  final bool isSelf;

  const AdminUserDetailScreen({
    super.key,
    required this.userService,
    this.user,
    this.isSelf = false,
  });

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  bool _loading = false;
  PasswordResetLinkResult? _resetLink;

  List<CustomRoleRecord>? _userRoles;
  List<CustomRoleRecord>? _allRoles;
  String? _addRoleId;
  bool _addingRole = false;

  @override
  void initState() {
    super.initState();
    if (widget.user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/admin/users');
      });
      return;
    }
    _loadCustomRoles();
  }

  Future<void> _loadCustomRoles() async {
    try {
      final results = await Future.wait([
        widget.userService.getUserCustomRoles(widget.user!.id),
        widget.userService.listCustomRoles(),
      ]);
      if (mounted) {
        setState(() {
          _userRoles = results[0];
          _allRoles = results[1];
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load role assignments')),
        );
      }
    }
  }

  Future<void> _removeCustomRole(String roleId) async {
    try {
      await widget.userService
          .removeCustomRoleFromUser(widget.user!.id, roleId);
      await _loadCustomRoles();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Something went wrong. Please try again.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    }
  }

  Future<void> _assignCustomRole() async {
    if (_addRoleId == null) return;
    setState(() => _addingRole = true);
    try {
      await widget.userService
          .assignCustomRoleToUser(widget.user!.id, _addRoleId!);
      setState(() => _addRoleId = null);
      await _loadCustomRoles();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Something went wrong. Please try again.'),
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
      if (mounted) context.go('/admin/users');
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Something went wrong. Please try again.'),
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
      final result = await widget.userService
          .adminCreatePasswordResetLink(widget.user!.id);
      if (mounted) setState(() => _resetLink = result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Something went wrong. Please try again.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final u = widget.user!;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/admin/users')),
        title: Row(
          children: [
            UserAvatar(
              avatarSeed: u.avatarSeed,
              displayName: u.displayName,
              size: 28,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                u.displayName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(u.email,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 20),

                // ── Account ───────────────────────────────────────────────
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

                const SizedBox(height: 24),

                // ── Password ──────────────────────────────────────────────
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
                  label: const Text('Force password change on next login'),
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

                const SizedBox(height: 24),

                // ── Sessions ──────────────────────────────────────────────
                _SectionHeader(label: 'Sessions'),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: Icon(Icons.devices_outlined,
                      color: widget.isSelf ? null : cs.error),
                  label: Text('Revoke all sessions',
                      style:
                          TextStyle(color: widget.isSelf ? null : cs.error)),
                  onPressed: widget.isSelf || _loading
                      ? null
                      : () => _confirm(
                            title: 'Revoke all sessions',
                            message:
                                'Sign ${u.displayName} out of all devices immediately? '
                                'They can log in again normally.',
                            confirmLabel: 'Revoke',
                            confirmColor: cs.error,
                            action: () =>
                                widget.userService.revokeUserSessions(u.id),
                          ),
                ),

                const SizedBox(height: 24),

                // ── MFA & Passkeys ────────────────────────────────────────
                _SectionHeader(label: 'MFA & Passkeys'),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: Icon(Icons.phonelink_lock_outlined,
                      color:
                          (widget.isSelf || u.totpCount == 0 || _loading)
                              ? null
                              : cs.error),
                  label: Text(
                    'Remove authenticator apps (${u.totpCount})',
                    style: TextStyle(
                        color:
                            (widget.isSelf || u.totpCount == 0 || _loading)
                                ? null
                                : cs.error),
                  ),
                  onPressed: (widget.isSelf || u.totpCount == 0 || _loading)
                      ? null
                      : () => _confirm(
                            title: 'Remove authenticator apps',
                            message:
                                'Remove all ${u.totpCount} TOTP authenticator '
                                'app(s) for ${u.displayName}? '
                                'They will lose MFA if no passkeys remain.',
                            confirmLabel: 'Remove',
                            confirmColor: cs.error,
                            action: () =>
                                widget.userService.adminDeleteAllTOTP(u.id),
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

                const SizedBox(height: 24),

                // ── Custom Roles ──────────────────────────────────────────
                _SectionHeader(label: 'Custom Roles'),
                const SizedBox(height: 8),
                if (_userRoles == null)
                  const SizedBox(
                    height: 24,
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
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
                                .where((r) =>
                                    _userRoles!.every((ur) => ur.id != r.id))
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

// ── Helpers ───────────────────────────────────────────────────────────────────

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
