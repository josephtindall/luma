import 'package:flutter/material.dart';

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
  late Future<List<AdminUserRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.userService.listAdminUsers();
  }

  void _reload() {
    setState(() {
      _future = widget.userService.listAdminUsers();
    });
  }

  Future<void> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
    required Future<void> Function() action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: confirmColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await action();
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<AdminUserRecord>>(
        future: _future,
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
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _reload,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final users = snap.data ?? [];
          final currentProfile = widget.userService.profile;

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Users',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(width: 12),
                        Chip(label: Text('${users.length}')),
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
                              isSelf: currentProfile?.id == users[i].id,
                              onLock: () => _confirmAction(
                                title: 'Lock account',
                                message:
                                    'This will immediately revoke all sessions for '
                                    '${users[i].displayName} and prevent them from '
                                    'logging in. Continue?',
                                confirmLabel: 'Lock',
                                confirmColor:
                                    Theme.of(context).colorScheme.error,
                                action: () =>
                                    widget.userService.lockUser(users[i].id),
                              ),
                              onUnlock: () => _confirmAction(
                                title: 'Unlock account',
                                message:
                                    'Allow ${users[i].displayName} to log in again?',
                                confirmLabel: 'Unlock',
                                confirmColor:
                                    Theme.of(context).colorScheme.primary,
                                action: () =>
                                    widget.userService.unlockUser(users[i].id),
                              ),
                              onRevokeSessions: () => _confirmAction(
                                title: 'Revoke all sessions',
                                message:
                                    'Sign ${users[i].displayName} out of all devices '
                                    'immediately? They can log in again normally.',
                                confirmLabel: 'Revoke',
                                confirmColor:
                                    Theme.of(context).colorScheme.error,
                                action: () => widget.userService
                                    .revokeUserSessions(users[i].id),
                              ),
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
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  final AdminUserRecord user;
  final bool isSelf;
  final VoidCallback onLock;
  final VoidCallback onUnlock;
  final VoidCallback onRevokeSessions;

  const _UserRow({
    required this.user,
    required this.isSelf,
    required this.onLock,
    required this.onUnlock,
    required this.onRevokeSessions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Wrap(
            spacing: 6,
            children: [
              if (user.isOwner)
                _Badge(label: 'Owner', color: colorScheme.primaryContainer,
                    textColor: colorScheme.onPrimaryContainer),
              if (user.mfaEnabled)
                _Badge(label: 'MFA', color: colorScheme.secondaryContainer,
                    textColor: colorScheme.onSecondaryContainer),
              if (user.isLocked)
                _Badge(label: 'Locked', color: colorScheme.errorContainer,
                    textColor: colorScheme.onErrorContainer),
            ],
          ),
          const SizedBox(width: 8),
          // Action menu — disabled for own account to prevent self-lock
          MenuAnchor(
            menuChildren: [
              if (user.isLocked)
                MenuItemButton(
                  leadingIcon: const Icon(Icons.lock_open_outlined),
                  onPressed: isSelf ? null : onUnlock,
                  child: const Text('Unlock account'),
                )
              else
                MenuItemButton(
                  leadingIcon: Icon(Icons.lock_outlined,
                      color: isSelf ? null : colorScheme.error),
                  onPressed: isSelf ? null : onLock,
                  child: Text(
                    'Lock account',
                    style: isSelf
                        ? null
                        : TextStyle(color: colorScheme.error),
                  ),
                ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.devices_outlined),
                onPressed: isSelf ? null : onRevokeSessions,
                child: const Text('Revoke all sessions'),
              ),
            ],
            builder: (context, controller, _) => IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: isSelf ? 'Cannot modify your own account' : 'Actions',
              onPressed: isSelf
                  ? null
                  : () {
                      if (controller.isOpen) {
                        controller.close();
                      } else {
                        controller.open();
                      }
                    },
            ),
          ),
        ],
      ),
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
