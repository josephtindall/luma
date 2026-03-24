import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/custom_role.dart';
import '../../models/group.dart';
import '../../models/user.dart';
import '../../services/user_service.dart';
import '../../theme/tokens.dart';
import '../../widgets/data_table.dart';
import '../../widgets/perm_button.dart';
import '../../widgets/permission_matrix.dart';
import '../../widgets/slideout_panel.dart';
import '../../widgets/pagination.dart';
import '../../widgets/skeleton/admin_skeletons.dart';
import '../../widgets/user_avatar.dart';

class AdminUsersScreen extends StatefulWidget {
  final UserService userService;

  const AdminUsersScreen({super.key, required this.userService});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  List<AdminUserRecord>? _users;
  List<InvitationRecord>? _invites;
  String? _error;
  bool _loading = true;
  bool _showInvites = false;
  String? _invFilter; // null = pending only, or 'all','expired','accepted','revoked'
  Set<int> _selected = {};
  int _currentPage = 0;
  static const _pageSize = 25;

  @override
  void initState() {
    super.initState();
    final cachedUsers = widget.userService.cachedAdminUsers;
    final cachedInvites = widget.userService.cachedInvitations;
    if (cachedUsers != null) {
      _users = cachedUsers;
      _invites = cachedInvites;
      _loading = false;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; _selected = {}; _currentPage = 0; });
    try {
      final results = await Future.wait([
        widget.userService.listAdminUsers(),
        if (widget.userService.canManageInvitations)
          widget.userService.listInvitations(),
      ]);
      if (!mounted) return;
      setState(() {
        _users = results[0] as List<AdminUserRecord>;
        if (results.length > 1) {
          _invites = results[1] as List<InvitationRecord>;
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load users: $e';
          _loading = false;
        });
      }
    }
  }

  Map<String, String> _computeHandles(List<AdminUserRecord> users) {
    final counts = <String, int>{};
    final assigned = <String, String>{};
    // First pass: count occurrences of each prefix.
    final prefixes = <String, String>{};
    for (final u in users) {
      final prefix = u.email.split('@').first.toLowerCase();
      prefixes[u.id] = prefix;
      counts[prefix] = (counts[prefix] ?? 0) + 1;
    }
    // Second pass: assign handles with deduplication.
    final seen = <String, int>{};
    for (final u in users) {
      final prefix = prefixes[u.id]!;
      final n = seen[prefix] ?? 0;
      seen[prefix] = n + 1;
      assigned[u.id] = n == 0 ? '@$prefix' : '@$prefix$n';
    }
    return assigned;
  }

  void _showUserSlideout(AdminUserRecord user) {
    showSlideoutPanel(
      context: context,
      title: user.displayName,
      bodyBuilder: (_) => _UserDetailContent(
        user: user,
        userService: widget.userService,
        isSelf: widget.userService.profile?.id == user.id,
        onChanged: _load,
      ),
    );
  }

  void _showCreateUserSlideout() {
    final titleNotifier = ValueNotifier('Create user');
    showSlideoutPanel(
      context: context,
      titleNotifier: titleNotifier,
      bodyBuilder: (_) => _CreateUserContent(
        userService: widget.userService,
        titleNotifier: titleNotifier,
        onCreated: (user) {
          _load();
          return _UserDetailContent(
            user: user,
            userService: widget.userService,
            isSelf: widget.userService.profile?.id == user.id,
            onChanged: _load,
          );
        },
      ),
    ).whenComplete(() => titleNotifier.dispose());
  }

  void _showInviteSlideout([String? initialEmail, String? revokeId]) {
    showSlideoutPanel(
      context: context,
      title: revokeId != null ? 'Resend Invite' : 'Create Invite',
      bodyBuilder: (_) => _InviteContent(
        userService: widget.userService,
        initialEmail: initialEmail,
        revokeId: revokeId,
      ),
    ).then((_) => _load());
  }

  Future<void> _revokeWithConfirm(InvitationRecord inv) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('Revoke invitation'),
        content: Text(
            'Revoke the invitation for ${inv.email}? '
            'The invite link will stop working immediately.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlg, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(dlg, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.userService.revokeInvitation(inv.id);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not revoke invitation. Please try again.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _bulkLock() async {
    final users = _users!;
    final pageStart = _currentPage * _pageSize;
    final targets = _selected
        .map((i) => users[pageStart + i])
        .where((u) => !u.isLocked && widget.userService.profile?.id != u.id)
        .toList();
    if (targets.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('Lock accounts'),
        content: Text('Lock ${targets.length} user account(s)? '
            'They will be signed out and unable to log in.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlg, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(dlg, true),
            child: const Text('Lock'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    for (final u in targets) {
      try {
        await widget.userService.lockUser(u.id);
      } catch (_) {}
    }
    _load();
  }

  Future<void> _bulkUnlock() async {
    final users = _users!;
    final pageStart = _currentPage * _pageSize;
    final targets = _selected
        .map((i) => users[pageStart + i])
        .where((u) => u.isLocked)
        .toList();
    if (targets.isEmpty) return;
    for (final u in targets) {
      try {
        await widget.userService.unlockUser(u.id);
      } catch (_) {}
    }
    _load();
  }

  List<InvitationRecord> _filteredInvites() {
    if (_invites == null) return [];
    return switch (_invFilter) {
      'all' => _invites!,
      'expired' => _invites!.where((i) => i.isExpired).toList(),
      'accepted' => _invites!.where((i) => i.isAccepted).toList(),
      'revoked' => _invites!.where((i) => i.isRevoked).toList(),
      _ => _invites!.where((i) => i.isPendingValid).toList(),
    };
  }

  int get _pendingCount =>
      _invites?.where((i) => i.isPendingValid).length ?? 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading && _users == null) {
      return const UsersScreenSkeleton();
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: cs.error)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final users = _users ?? [];
    final handles = _computeHandles(users);
    final selfId = widget.userService.profile?.id;
    final totalPages = (users.length / _pageSize).ceil().clamp(1, 999);
    final pageStart = _currentPage * _pageSize;
    final pageUsers = users.sublist(
      pageStart, (pageStart + _pageSize).clamp(0, users.length));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Users',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      '${users.length} total \u00b7 Manage user accounts and permissions.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (widget.userService.canManageInvitations) ...[
                _InviteBadgeButton(
                  count: _pendingCount,
                  isActive: _showInvites,
                  onTap: () =>
                      setState(() => _showInvites = !_showInvites),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.mail_outlined, size: 16),
                  label: const Text('Invite'),
                  onPressed: () => _showInviteSlideout(),
                ),
                const SizedBox(width: 8),
              ],
              PermButton(
                label: 'Create user',
                filled: true,
                enabled: widget.userService.canCreateUser,
                requiredPermission: 'user:invite',
                onPressed: _showCreateUserSlideout,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Users table + pagination
          Expanded(
            child: users.isEmpty
                ? const Center(child: Text('No users yet'))
                : LumaDataTable<AdminUserRecord>(
                          showCheckboxes: widget.userService.canManageUsers,
                          selected: _selected,
                          onSelectionChanged: (s) =>
                              setState(() => _selected = s),
                          canSelect: (u, _) => selfId != u.id,
                          onRowTap: widget.userService.canEditUser
                              ? _showUserSlideout
                              : null,
                          bulkActionBar: (sel) => _BulkActionBar(
                            count: sel.length,
                            onClear: () => setState(() => _selected = {}),
                            actions: [
                              OutlinedButton.icon(
                                icon: Icon(Icons.lock_outlined,
                                    size: 16, color: cs.error),
                                label: Text('Lock',
                                    style: TextStyle(color: cs.error)),
                                onPressed: _bulkLock,
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.lock_open_outlined,
                                    size: 16),
                                label: const Text('Unlock'),
                                onPressed: _bulkUnlock,
                              ),
                            ],
                          ),
                          columns: [
                            LumaColumn<AdminUserRecord>(
                              label: 'Name',
                              cellBuilder: (u, _) => Row(
                                children: [
                                  UserAvatar(
                                    avatarSeed: u.avatarSeed,
                                    displayName: u.displayName,
                                    size: 32,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                u.displayName,
                                                style: theme.textTheme.bodyMedium
                                                    ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w600),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (selfId == u.id) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 1),
                                                decoration: BoxDecoration(
                                                  color:
                                                      cs.primaryContainer,
                                                  borderRadius:
                                                      LumaRadius.radiusLg,
                                                ),
                                                child: Text('You',
                                                    style: theme
                                                        .textTheme.labelSmall
                                                        ?.copyWith(
                                                            color: cs
                                                                .onPrimaryContainer)),
                                              ),
                                            ],
                                          ],
                                        ),
                                        Text(
                                          handles[u.id] ?? '',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                  color:
                                                      cs.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            LumaColumn<AdminUserRecord>(
                              label: 'Email',
                              cellBuilder: (u, _) => Text(
                                u.email,
                                style: theme.textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            LumaColumn<AdminUserRecord>(
                              label: 'Status',
                              width: 200,
                              cellBuilder: (u, _) {
                                final badges = <Widget>[];
                                if (u.isOwner) {
                                  badges.add(_Badge(
                                      label: 'Owner',
                                      color: cs.primaryContainer,
                                      textColor: cs.onPrimaryContainer));
                                }
                                if (u.mfaEnabled) {
                                  badges.add(_Badge(
                                      label: 'MFA',
                                      color: cs.secondaryContainer,
                                      textColor: cs.onSecondaryContainer));
                                }
                                if (u.isLocked) {
                                  badges.add(_Badge(
                                      label: 'Locked',
                                      color: cs.errorContainer,
                                      textColor: cs.onErrorContainer));
                                }
                                if (u.forcePasswordChange) {
                                  badges.add(_Badge(
                                      label: 'Pwd change',
                                      color: cs.tertiaryContainer,
                                      textColor: cs.onTertiaryContainer));
                                }
                                if (badges.isEmpty) {
                                  badges.add(_Badge(
                                      label: 'Active',
                                      color: cs.secondaryContainer,
                                      textColor: cs.onSecondaryContainer));
                                }
                                return Wrap(spacing: 4, children: badges);
                              },
                            ),
                            LumaColumn<AdminUserRecord>(
                              label: '',
                              width: 100,
                              cellBuilder: (u, _) => Align(
                                alignment: Alignment.centerRight,
                                child: PermButton(
                                  label: 'Manage',
                                  enabled: widget.userService.canEditUser,
                                  requiredPermission: 'user:edit',
                                  onPressed: () => _showUserSlideout(u),
                                ),
                              ),
                            ),
                          ],
                          rows: pageUsers,
                        ),
          ),

          // Invitations section (collapsible)
          if (_showInvites && _invites != null) ...[
            const SizedBox(height: 16),
            Divider(color: cs.outlineVariant),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Invitations',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                ..._invFilterChips(cs),
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: _buildInviteList(),
            ),
          ],
        ],
      ),
    ),
        ),
        LumaPagination(
          currentPage: _currentPage,
          totalPages: totalPages,
          onPageChanged: (p) =>
              setState(() { _currentPage = p; _selected = {}; }),
        ),
      ],
    );
  }

  List<Widget> _invFilterChips(ColorScheme cs) {
    Widget chip(String? value, String label) {
      return Padding(
        padding: const EdgeInsets.only(left: 4),
        child: FilterChip(
          label: Text(label),
          selected: _invFilter == value,
          onSelected: (_) => setState(() => _invFilter = value),
          visualDensity: VisualDensity.compact,
        ),
      );
    }
    return [
      chip(null, 'Pending'),
      chip('all', 'All'),
      chip('expired', 'Expired'),
      chip('accepted', 'Accepted'),
      chip('revoked', 'Revoked'),
    ];
  }

  Widget _buildInviteList() {
    final visible = _filteredInvites();
    if (visible.isEmpty) {
      return Center(
        child: Text('No invitations to show.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: visible.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => _InvitationRow(
        inv: visible[i],
        onRevoke: () => _revokeWithConfirm(visible[i]),
        onReinvite: () =>
            _showInviteSlideout(visible[i].email, visible[i].id),
      ),
    );
  }
}

// ── Invite badge button ───────────────────────────────────────────────────────

class _InviteBadgeButton extends StatelessWidget {
  final int count;
  final bool isActive;
  final VoidCallback onTap;

  const _InviteBadgeButton({
    required this.count,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: LumaRadius.radiusMd,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? cs.primaryContainer : null,
          borderRadius: LumaRadius.radiusMd,
          border: Border.all(
              color: isActive ? cs.primary : cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mail_outlined,
                size: 16,
                color: isActive
                    ? cs.onPrimaryContainer
                    : cs.onSurfaceVariant),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: LumaRadius.radiusLg,
                ),
                child: Text(
                  '$count',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onPrimary, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Bulk action bar ───────────────────────────────────────────────────────────

class _BulkActionBar extends StatelessWidget {
  final int count;
  final VoidCallback onClear;
  final List<Widget> actions;

  const _BulkActionBar({
    required this.count,
    required this.onClear,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withAlpha(60),
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withAlpha(128)),
        ),
      ),
      child: Row(
        children: [
          Text('$count selected',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          ...actions,
          const Spacer(),
          TextButton(
            onPressed: onClear,
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

// ── User detail content (slideout body) ──────────────────────────────────────

class _UserDetailContent extends StatefulWidget {
  final AdminUserRecord user;
  final UserService userService;
  final bool isSelf;
  final VoidCallback onChanged;

  const _UserDetailContent({
    required this.user,
    required this.userService,
    required this.isSelf,
    required this.onChanged,
  });

  @override
  State<_UserDetailContent> createState() => _UserDetailContentState();
}

class _UserDetailContentState extends State<_UserDetailContent> {
  bool _loading = false;
  PasswordResetLinkResult? _resetLink;

  List<CustomRoleRecord>? _userRoles;
  List<CustomRoleRecord>? _allRoles;
  String? _addRoleId;
  bool _addingRole = false;

  List<GroupRecord>? _userGroups;
  List<GroupRecord>? _allGroups;
  String? _addGroupId;
  bool _addingGroup = false;

  @override
  void initState() {
    super.initState();
    _loadCustomRoles();
    if (widget.userService.canManageGroups) _loadGroups();
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load role assignments')),
        );
      }
    }
  }

  Future<void> _loadGroups() async {
    try {
      final all = await widget.userService.listGroups();
      if (!mounted) return;
      final userId = widget.user.id;
      final mine = all
          .where((g) =>
              g.members.any((m) => m.memberType == 'user' && m.memberId == userId))
          .toList();
      setState(() {
        _allGroups = all;
        _userGroups = mine;
      });
    } catch (_) {
      // non-critical — groups section just won't show
    }
  }

  Future<void> _addToGroup() async {
    if (_addGroupId == null) return;
    setState(() => _addingGroup = true);
    try {
      await widget.userService.addGroupMember(
        _addGroupId!, 'user', widget.user.id);
      setState(() => _addGroupId = null);
      await _loadGroups();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Something went wrong. Please try again.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _addingGroup = false);
    }
  }

  Future<void> _removeFromGroup(String groupId) async {
    try {
      await widget.userService.removeGroupMember(
        groupId, 'user', widget.user.id);
      await _loadGroups();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Something went wrong. Please try again.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    }
  }

  Future<void> _removeCustomRole(String roleId) async {
    try {
      await widget.userService.removeCustomRoleFromUser(widget.user.id, roleId);
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
      await widget.userService.assignCustomRoleToUser(widget.user.id, _addRoleId!);
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
      widget.onChanged();
      if (mounted) Navigator.of(context).pop();
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
    setState(() { _loading = true; _resetLink = null; });
    try {
      final result = await widget.userService
          .adminCreatePasswordResetLink(widget.user.id);
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final u = widget.user;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Avatar + email header
          Row(
            children: [
              UserAvatar(
                avatarSeed: u.avatarSeed,
                displayName: u.displayName,
                size: 48,
              ),
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
            ],
          ),
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
                        message: 'Allow ${u.displayName} to log in again?',
                        confirmLabel: 'Unlock',
                        confirmColor: cs.primary,
                        action: () => widget.userService.unlockUser(u.id),
                      ),
            )
          else
            OutlinedButton.icon(
              icon: Icon(Icons.lock_outlined,
                  color: widget.isSelf ? null : cs.error),
              label: Text('Lock account',
                  style: TextStyle(color: widget.isSelf ? null : cs.error)),
              onPressed: widget.isSelf || _loading
                  ? null
                  : () => _confirm(
                        title: 'Lock account',
                        message:
                            'This will immediately revoke all sessions for '
                            '${u.displayName} and prevent them from logging in.',
                        confirmLabel: 'Lock',
                        confirmColor: cs.error,
                        action: () => widget.userService.lockUser(u.id),
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
                      action: () =>
                          widget.userService.adminForcePasswordChange(u.id),
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
                style: TextStyle(color: widget.isSelf ? null : cs.error)),
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
                color: (widget.isSelf || u.totpCount == 0 || _loading)
                    ? null
                    : cs.error),
            label: Text(
              'Remove authenticator apps (${u.totpCount})',
              style: TextStyle(
                  color: (widget.isSelf || u.totpCount == 0 || _loading)
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
                color: (widget.isSelf || u.passkeyCount == 0 || _loading)
                    ? null
                    : cs.error),
            label: Text(
              'Remove passkeys (${u.passkeyCount})',
              style: TextStyle(
                  color: (widget.isSelf || u.passkeyCount == 0 || _loading)
                      ? null
                      : cs.error),
            ),
            onPressed: (widget.isSelf || u.passkeyCount == 0 || _loading)
                ? null
                : () => _confirm(
                      title: 'Remove passkeys',
                      message:
                          'Revoke all ${u.passkeyCount} passkey(s) for '
                          '${u.displayName}? '
                          'They will lose MFA if no authenticator apps remain.',
                      confirmLabel: 'Remove',
                      confirmColor: cs.error,
                      action: () =>
                          widget.userService.adminRevokeAllPasskeys(u.id),
                    ),
          ),

          const SizedBox(height: 24),

          // ── Directory visibility ──────────────────────────────────
          _SectionHeader(label: 'Directory visibility'),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hide from directory search'),
            subtitle: const Text(
              'When enabled, this user will not appear in search results for non-admin users.',
            ),
            value: u.hideFromSearch,
            onChanged: widget.isSelf || _loading
                ? null
                : (hide) async {
                    setState(() => _loading = true);
                    try {
                      await widget.userService
                          .setUserHideFromSearch(u.id, hide: hide);
                      widget.onChanged();
                      if (mounted) Navigator.of(context).pop();
                    } catch (e) {
                      if (mounted) {
                        setState(() => _loading = false);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: const Text(
                              'Something went wrong. Please try again.'),
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ));
                      }
                    }
                  },
          ),

          // ── Groups ──────────────────────────────────────────────
          if (widget.userService.canManageGroups && _allGroups != null) ...[
            const SizedBox(height: 24),
            _SectionHeader(label: 'Groups'),
            const SizedBox(height: 8),
            if (_userGroups!.isEmpty)
              Text('Not a member of any groups.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant))
            else
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _userGroups!.map((g) {
                  return Chip(
                    label: Text(g.name),
                    deleteIcon: g.noMemberControl
                        ? null
                        : const Icon(Icons.close, size: 16),
                    onDeleted:
                        g.noMemberControl ? null : () => _removeFromGroup(g.id),
                  );
                }).toList(),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _addGroupId,
                    decoration: const InputDecoration(
                      labelText: 'Add to group',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _allGroups!
                        .where((g) =>
                            !g.noMemberControl &&
                            _userGroups!.every((ug) => ug.id != g.id))
                        .map((g) => DropdownMenuItem(
                              value: g.id,
                              child: Text(g.name),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _addGroupId = v),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: (_addGroupId == null || _addingGroup)
                      ? null
                      : _addToGroup,
                  child: _addingGroup
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Add'),
                ),
              ],
            ),
          ],

          const SizedBox(height: 24),

          // ── Custom Roles ──────────────────────────────────────────
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
                          .where((r) => _userRoles!.every((ur) => ur.id != r.id))
                          .map((r) => DropdownMenuItem(
                                value: r.id,
                                child: Text(r.name),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _addRoleId = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: (_addRoleId == null || _addingRole)
                        ? null
                        : _assignCustomRole,
                    child: _addingRole
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Assign'),
                  ),
                ],
              ),
            ],
          ],

          const SizedBox(height: 24),

          // ── Effective permissions ──────────────────────────────────
          _SectionHeader(label: 'Effective permissions'),
          const SizedBox(height: 4),
          if (_userRoles == null)
            const SizedBox(
              height: 24,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_userRoles!.isEmpty)
            Text(
              'No custom roles assigned — no additional permissions granted.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            )
          else ...[
            Text(
              'Based on directly assigned custom roles.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            PermissionMatrix(
              permMap: resolveEffectivePermissions(_userRoles!),
              readOnly: true,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Invitation row ────────────────────────────────────────────────────────────

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
            style: TextStyle(color: Theme.of(context).colorScheme.error),
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
    if (inv.isAccepted && inv.acceptedAt != null) {
      return 'Joined ${_fmtDate(inv.acceptedAt!)}';
    }
    if (inv.isRevoked && inv.revokedAt != null) {
      return 'Revoked ${_fmtDate(inv.revokedAt!)}';
    }
    if (inv.isExpired) {
      return 'Expired ${_fmtDate(inv.expiresAt)}';
    }
    return 'Expires ${_fmtDate(inv.expiresAt)}';
  }

  String _fmtDate(DateTime dt) {
    final l = dt.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-'
        '${l.day.toString().padLeft(2, '0')}';
  }
}

// ── Invite content (slideout body) ───────────────────────────────────────────

class _InviteContent extends StatefulWidget {
  final UserService userService;
  final String? initialEmail;
  final String? revokeId;

  const _InviteContent({
    required this.userService,
    this.initialEmail,
    this.revokeId,
  });

  @override
  State<_InviteContent> createState() => _InviteContentState();
}

class _InviteContentState extends State<_InviteContent> {
  late final TextEditingController _emailController;
  bool _creating = false;
  String? _joinUrl;
  String? _error;
  bool _copied = false;
  String? _createdInvId;

  bool get _hasInitialEmail =>
      widget.initialEmail != null && widget.initialEmail!.isNotEmpty;
  bool get _isResend => widget.revokeId != null;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
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
    setState(() { _creating = true; _error = null; });
    try {
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
        _error = e.toString().replaceFirst('Exception: ', '');
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
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
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isResend ? 'Generate new link' : 'Create invite'),
            ),
          ] else ...[
            const SizedBox(height: 24),
            Text(
              'Invite URL',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                      borderRadius: LumaRadius.radiusMd,
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
                  icon: Icon(_copied ? Icons.check : Icons.copy_outlined),
                  tooltip: _copied ? 'Copied!' : 'Copy',
                  onPressed: _copyUrl,
                ),
                IconButton(
                  icon: _creating
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_outlined),
                  tooltip: 'Regenerate link',
                  onPressed: _creating ? null : _create,
                ),
              ],
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
    );
  }
}

// ── Create user slideout content ──────────────────────────────────────────────

class _CreateUserContent extends StatefulWidget {
  final UserService userService;
  final ValueNotifier<String> titleNotifier;
  final Widget Function(AdminUserRecord user) onCreated;

  const _CreateUserContent({
    required this.userService,
    required this.titleNotifier,
    required this.onCreated,
  });

  @override
  State<_CreateUserContent> createState() => _CreateUserContentState();
}

class _CreateUserContentState extends State<_CreateUserContent> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _forceChange = false;
  bool _loading = false;
  String? _error;
  Widget? _detailView;

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
    setState(() { _loading = true; _error = null; });
    try {
      final user = await widget.userService.adminCreateUser(
        email: _emailCtrl.text.trim(),
        displayName: _nameCtrl.text.trim(),
        password: _pwdCtrl.text,
        forcePasswordChange: _forceChange,
      );
      if (!mounted) return;
      widget.titleNotifier.value = user.displayName;
      setState(() => _detailView = widget.onCreated(user));
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_detailView != null) return _detailView!;

    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _emailCtrl,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Display name (optional)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _pwdCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
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
              decoration:
                  const InputDecoration(labelText: 'Confirm password'),
              validator: (v) =>
                  v != _pwdCtrl.text ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Require password change on first login'),
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
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create user'),
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
        borderRadius: LumaRadius.radiusMd,
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
                        height: 20, width: 20,
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
