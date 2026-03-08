import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/user.dart';
import '../../services/user_service.dart';
import '../../widgets/user_avatar.dart';

class AdminUsersScreen extends StatefulWidget {
  final UserService userService;

  const AdminUsersScreen({super.key, required this.userService});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late Future<List<AdminUserRecord>> _usersFuture;
  late Future<List<InvitationRecord>> _invFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _usersFuture = widget.userService.listAdminUsers();
    _invFuture = widget.userService.listInvitations();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _reloadUsers() {
    setState(() {
      _usersFuture = widget.userService.listAdminUsers();
    });
  }

  void _reloadInvitations() {
    setState(() {
      _invFuture = widget.userService.listInvitations();
    });
  }

  Future<void> _confirmAction({
    required BuildContext ctx,
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
    required Future<void> Function() action,
    VoidCallback? onSuccess,
  }) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dlg) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlg, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: confirmColor),
            onPressed: () => Navigator.pop(dlg, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await action();
      onSuccess?.call();
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

  void _showInvitePanel([String? initialEmail, String? revokeId]) {
    showDialog<void>(
      context: context,
      builder: (_) => _InvitePanel(
        userService: widget.userService,
        initialEmail: initialEmail,
        revokeId: revokeId,
      ),
    ).then((_) => _reloadInvitations());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Tab bar, centred with the same max-width as the content below
          Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'Users'),
                    Tab(text: 'Invitations'),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _UsersTab(
                  future: _usersFuture,
                  currentUserId: widget.userService.profile?.id,
                  onLock: (u) => _confirmAction(
                    ctx: context,
                    title: 'Lock account',
                    message: 'This will immediately revoke all sessions for '
                        '${u.displayName} and prevent them from logging in. '
                        'Continue?',
                    confirmLabel: 'Lock',
                    confirmColor: Theme.of(context).colorScheme.error,
                    action: () => widget.userService.lockUser(u.id),
                    onSuccess: _reloadUsers,
                  ),
                  onUnlock: (u) => _confirmAction(
                    ctx: context,
                    title: 'Unlock account',
                    message: 'Allow ${u.displayName} to log in again?',
                    confirmLabel: 'Unlock',
                    confirmColor: Theme.of(context).colorScheme.primary,
                    action: () => widget.userService.unlockUser(u.id),
                    onSuccess: _reloadUsers,
                  ),
                  onRevokeSessions: (u) => _confirmAction(
                    ctx: context,
                    title: 'Revoke all sessions',
                    message:
                        'Sign ${u.displayName} out of all devices immediately? '
                        'They can log in again normally.',
                    confirmLabel: 'Revoke',
                    confirmColor: Theme.of(context).colorScheme.error,
                    action: () =>
                        widget.userService.revokeUserSessions(u.id),
                    onSuccess: _reloadUsers,
                  ),
                  onReload: _reloadUsers,
                ),
                _InvitationsTab(
                  future: _invFuture,
                  onRevoke: (inv) => _confirmAction(
                    ctx: context,
                    title: 'Revoke invitation',
                    message: 'Revoke the invitation for ${inv.email}? '
                        'The invite link will stop working immediately.',
                    confirmLabel: 'Revoke',
                    confirmColor: Theme.of(context).colorScheme.error,
                    action: () =>
                        widget.userService.revokeInvitation(inv.id),
                    onSuccess: _reloadInvitations,
                  ),
                  onReinvite: (inv) => _showInvitePanel(inv.email, inv.id),
                  onCreateInvite: () => _showInvitePanel(),
                  onReload: _reloadInvitations,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Users tab ─────────────────────────────────────────────────────────────────

class _UsersTab extends StatelessWidget {
  final Future<List<AdminUserRecord>> future;
  final String? currentUserId;
  final void Function(AdminUserRecord) onLock;
  final void Function(AdminUserRecord) onUnlock;
  final void Function(AdminUserRecord) onRevokeSessions;
  final VoidCallback onReload;

  const _UsersTab({
    required this.future,
    required this.currentUserId,
    required this.onLock,
    required this.onUnlock,
    required this.onRevokeSessions,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AdminUserRecord>>(
      future: future,
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
                FilledButton(onPressed: onReload, child: const Text('Retry')),
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
                            isSelf: currentUserId == users[i].id,
                            onLock: () => onLock(users[i]),
                            onUnlock: () => onUnlock(users[i]),
                            onRevokeSessions: () =>
                                onRevokeSessions(users[i]),
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

// ── Invitations tab ───────────────────────────────────────────────────────────

class _InvitationsTab extends StatefulWidget {
  final Future<List<InvitationRecord>> future;
  final void Function(InvitationRecord) onRevoke;
  final void Function(InvitationRecord) onReinvite;
  final VoidCallback onCreateInvite;
  final VoidCallback onReload;

  const _InvitationsTab({
    required this.future,
    required this.onRevoke,
    required this.onReinvite,
    required this.onCreateInvite,
    required this.onReload,
  });

  @override
  State<_InvitationsTab> createState() => _InvitationsTabState();
}

class _InvitationsTabState extends State<_InvitationsTab> {
  String? _filter; // null = all

  List<InvitationRecord> _applyFilter(List<InvitationRecord> all) {
    return switch (_filter) {
      'pending' => all.where((i) => i.isPendingValid).toList(),
      'expired' => all.where((i) => i.isExpired).toList(),
      'accepted' => all.where((i) => i.isAccepted).toList(),
      'revoked' => all.where((i) => i.isRevoked).toList(),
      _ => all,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<InvitationRecord>>(
      future: widget.future,
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
                  'Could not load invitations: ${snap.error}',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: widget.onReload,
                    child: const Text('Retry')),
              ],
            ),
          );
        }

        final all = snap.data ?? [];
        final visible = _applyFilter(all);

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
                      Text('Invitations',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(width: 12),
                      Chip(label: Text('${visible.length}')),
                      const Spacer(),
                      FilledButton.icon(
                        icon: const Icon(Icons.person_add_outlined),
                        label: const Text('Create invite'),
                        onPressed: widget.onCreateInvite,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      _chip(context, null, 'All', all.length),
                      _chip(context, 'pending', 'Pending',
                          all.where((i) => i.isPendingValid).length),
                      _chip(context, 'expired', 'Expired',
                          all.where((i) => i.isExpired).length),
                      _chip(context, 'accepted', 'Accepted',
                          all.where((i) => i.isAccepted).length),
                      _chip(context, 'revoked', 'Revoked',
                          all.where((i) => i.isRevoked).length),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (visible.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: Text(
                          'No invitations to show.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                    )
                  else
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (int i = 0; i < visible.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            _InvitationRow(
                              inv: visible[i],
                              onRevoke: () => widget.onRevoke(visible[i]),
                              onReinvite: () =>
                                  widget.onReinvite(visible[i]),
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

  Widget _chip(
      BuildContext context, String? value, String label, int count) {
    return FilterChip(
      label: Text('$label ($count)'),
      selected: _filter == value,
      onSelected: (_) => setState(() => _filter = value),
    );
  }
}

class _InvitationRow extends StatelessWidget {
  final InvitationRecord inv;
  final VoidCallback onRevoke;
  final VoidCallback onReinvite;

  const _InvitationRow({
    required this.inv,
    required this.onRevoke,
    required this.onReinvite,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  inv.email.isEmpty ? '(no email)' : inv.email,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (inv.note.isNotEmpty)
                  Text(
                    inv.note,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                const SizedBox(height: 4),
                Text(
                  _dateLabel(),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _statusBadge(context),
          const SizedBox(width: 8),
          _actions(context),
        ],
      ),
    );
  }

  Widget _statusBadge(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (label, bg, fg) = switch (true) {
      _ when inv.isPendingValid => (
          'Pending',
          cs.primaryContainer,
          cs.onPrimaryContainer
        ),
      _ when inv.isExpired =>
        ('Expired', cs.errorContainer, cs.onErrorContainer),
      _ when inv.isAccepted => (
          'Accepted',
          cs.secondaryContainer,
          cs.onSecondaryContainer
        ),
      _ => ('Revoked', cs.surfaceContainerHighest, cs.onSurfaceVariant),
    };
    return _Badge(label: label, color: bg, textColor: fg);
  }

  Widget _actions(BuildContext context) {
    // Accepted and revoked invitations have no further actions
    if (inv.isAccepted || inv.isRevoked) {
      return const SizedBox(width: 40);
    }
    return MenuAnchor(
      menuChildren: [
        if (inv.isPendingValid)
          MenuItemButton(
            leadingIcon: const Icon(Icons.link_outlined),
            onPressed: onReinvite,
            child: const Text('View / resend link'),
          ),
        if (inv.isExpired)
          MenuItemButton(
            leadingIcon: const Icon(Icons.refresh_outlined),
            onPressed: onReinvite,
            child: const Text('Re-invite'),
          ),
        MenuItemButton(
          leadingIcon: Icon(Icons.cancel_outlined,
              color: Theme.of(context).colorScheme.error),
          onPressed: onRevoke,
          child: Text(
            'Revoke',
            style:
                TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        icon: const Icon(Icons.more_vert),
        tooltip: 'Actions',
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
      ),
    );
  }

  String _dateLabel() {
    final fmt = _fmtDate;
    if (inv.isAccepted && inv.acceptedAt != null) {
      return 'Joined ${fmt(inv.acceptedAt!)}';
    }
    if (inv.isRevoked && inv.revokedAt != null) {
      return 'Revoked ${fmt(inv.revokedAt!)}';
    }
    if (inv.isExpired) {
      return 'Expired ${fmt(inv.expiresAt)}';
    }
    return 'Expires ${fmt(inv.expiresAt)}';
  }

  String _fmtDate(DateTime dt) {
    final l = dt.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-'
        '${l.day.toString().padLeft(2, '0')}';
  }
}

// ── User row ─────────────────────────────────────────────────────────────────

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
                _Badge(
                    label: 'Owner',
                    color: colorScheme.primaryContainer,
                    textColor: colorScheme.onPrimaryContainer),
              if (user.mfaEnabled)
                _Badge(
                    label: 'MFA',
                    color: colorScheme.secondaryContainer,
                    textColor: colorScheme.onSecondaryContainer),
              if (user.isLocked)
                _Badge(
                    label: 'Locked',
                    color: colorScheme.errorContainer,
                    textColor: colorScheme.onErrorContainer),
            ],
          ),
          const SizedBox(width: 8),
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
              tooltip:
                  isSelf ? 'Cannot modify your own account' : 'Actions',
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

// ── Shared badge ─────────────────────────────────────────────────────────────

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

// ── Invite panel ─────────────────────────────────────────────────────────────

class _InvitePanel extends StatefulWidget {
  final UserService userService;
  final String? initialEmail;
  final String? revokeId;

  const _InvitePanel({required this.userService, this.initialEmail, this.revokeId});

  @override
  State<_InvitePanel> createState() => _InvitePanelState();
}

class _InvitePanelState extends State<_InvitePanel> {
  late final TextEditingController _emailController;
  bool _creating = false;
  String? _joinUrl;
  String? _error;
  bool _copied = false;
  // ID of the most recently created invite — used when regenerating so we
  // revoke the one we just made rather than the original widget.revokeId.
  String? _createdInvId;

  bool get _hasInitialEmail =>
      widget.initialEmail != null && widget.initialEmail!.isNotEmpty;
  bool get _isResend => widget.revokeId != null;

  @override
  void initState() {
    super.initState();
    _emailController =
        TextEditingController(text: widget.initialEmail ?? '');
    // Auto-create only for completely new invites where an email is
    // pre-filled but there is no existing invite to replace.
    if (_hasInitialEmail && !_isResend) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _create());
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      // On regenerate, revoke the invite we created this session.
      // On first generate, revoke the original (widget.revokeId).
      final idToRevoke = _createdInvId ?? widget.revokeId;
      if (idToRevoke != null) {
        await widget.userService.revokeInvitation(idToRevoke);
      }
      final result = await widget.userService.createInvitation(email);
      final url = '${Uri.base.origin}/join?token=${result.token}';
      setState(() {
        _joinUrl = url;
        _createdInvId = result.id;
        _creating = false;
      });
    } catch (e) {
      setState(() {
        _creating = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _copyUrl() async {
    if (_joinUrl == null) return;
    await Clipboard.setData(ClipboardData(text: _joinUrl!));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    _isResend ? 'Resend Invite' : 'Create Invite',
                    style: theme.textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _emailController,
                enabled: !_hasInitialEmail && _joinUrl == null && !_creating,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  hintText: 'user@example.com',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                autofocus: !_hasInitialEmail,
                onSubmitted: (_) => _isResend ? null : _create(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: TextStyle(color: theme.colorScheme.error)),
              ],
              if (_joinUrl == null) ...[
                if (_isResend) ...[
                  const SizedBox(height: 12),
                  Text(
                    'The original invite link cannot be retrieved. '
                    'Generating a new link will revoke the current one.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _creating ? null : _create,
                  child: _creating
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isResend ? 'Generate new link' : 'Create invite'),
                ),
              ] else ...[
                const SizedBox(height: 24),
                Text(
                  'Invite URL',
                  style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          _joinUrl!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(
                          _copied ? Icons.check : Icons.copy_outlined),
                      tooltip: _copied ? 'Copied!' : 'Copy',
                      onPressed: _copyUrl,
                    ),
                    IconButton(
                      icon: _creating
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_outlined),
                      tooltip: 'Regenerate link',
                      onPressed: _creating ? null : _create,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('Send invite via Email'),
                  onPressed: null,
                ),
                const SizedBox(height: 24),
                Center(
                  child: QrImageView(
                    data: _joinUrl!,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
