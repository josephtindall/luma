import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/user_service.dart';
import '../../theme/tokens.dart';

class AdminLayout extends StatelessWidget {
  final Widget child;
  final UserService userService;

  const AdminLayout({super.key, required this.child, required this.userService});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: userService,
      builder: (context, _) => _AdminShell(
        userService: userService,
        child: child,
      ),
    );
  }
}

class _AdminShell extends StatefulWidget {
  final UserService userService;
  final Widget child;

  const _AdminShell({required this.userService, required this.child});

  @override
  State<_AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<_AdminShell> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _overlayLink = LayerLink();
  OverlayEntry? _overlay;

  List<_AdminSearchResult> _buildSearchItems() {
    final us = widget.userService;
    return [
      if (us.canManageUsers) ...[
        _AdminSearchResult(
          label: 'Users',
          subtitle: 'Manage user accounts and permissions',
          route: '/admin/users',
          icon: Icons.people_outlined,
        ),
        if (us.canCreateUser)
          _AdminSearchResult(
            label: 'Create user',
            subtitle: 'Add a new user account',
            route: '/admin/users',
            icon: Icons.person_add_outlined,
          ),
      ],
      if (us.canManageInvitations)
        _AdminSearchResult(
          label: 'Invite user',
          subtitle: 'Send a user invitation',
          route: '/admin/users',
          icon: Icons.mail_outlined,
        ),
      if (us.canManageGroups) ...[
        _AdminSearchResult(
          label: 'Groups',
          subtitle: 'Organize users into teams',
          route: '/admin/groups',
          icon: Icons.group_outlined,
        ),
        if (us.canCreateGroup)
          _AdminSearchResult(
            label: 'Create group',
            subtitle: 'Add a new group',
            route: '/admin/groups',
            icon: Icons.group_add_outlined,
          ),
      ],
      if (us.canManageRoles) ...[
        _AdminSearchResult(
          label: 'Roles',
          subtitle: 'Configure permission roles',
          route: '/admin/roles',
          icon: Icons.admin_panel_settings_outlined,
        ),
        if (us.canCreateRole)
          _AdminSearchResult(
            label: 'Create role',
            subtitle: 'Add a new permission role',
            route: '/admin/roles',
            icon: Icons.add_moderator_outlined,
          ),
      ],
      if (us.canManageVaults)
        _AdminSearchResult(
          label: 'Vaults',
          subtitle: 'Manage all vaults in the instance',
          route: '/admin/vaults',
          icon: Icons.folder_outlined,
        ),
      if (us.canManageInstanceSettings)
        _AdminSearchResult(
          label: 'Settings',
          subtitle: 'Configure instance settings',
          route: '/admin/settings',
          icon: Icons.settings_outlined,
        ),
      if (us.canViewAuditLog) ...[
        _AdminSearchResult(
          label: 'Events',
          subtitle: 'View audit log and system events',
          route: '/admin/events',
          icon: Icons.history_outlined,
        ),
        if (us.canExportAuditLog)
          _AdminSearchResult(
            label: 'Export audit log',
            subtitle: 'Download events as CSV',
            route: '/admin/events',
            icon: Icons.download_outlined,
          ),
      ],
    ];
  }

  void _showOverlay() {
    _removeOverlay();
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return;

    final allItems = _buildSearchItems();
    final matches = allItems.where((item) {
      return item.label.toLowerCase().contains(query) ||
          (item.subtitle?.toLowerCase().contains(query) ?? false);
    }).toList();

    if (matches.isEmpty) return;

    final overlay = Overlay.of(context);
    _overlay = OverlayEntry(
      builder: (_) => _SearchOverlay(
        link: _overlayLink,
        results: matches,
        onSelect: (result) {
          _removeOverlay();
          _searchCtrl.clear();
          _searchFocus.unfocus();
          context.go(result.route);
        },
        onDismiss: _removeOverlay,
      ),
    );
    overlay.insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  @override
  void dispose() {
    _removeOverlay();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final borderColor = cs.outlineVariant.withAlpha(128);

    final tabs = [
      if (widget.userService.canManageUsers)
        _AdminTab(label: 'Users', route: '/admin/users'),
      if (widget.userService.canManageGroups)
        _AdminTab(label: 'Groups', route: '/admin/groups'),
      if (widget.userService.canManageRoles)
        _AdminTab(label: 'Roles', route: '/admin/roles'),
      if (widget.userService.canManageVaults)
        _AdminTab(label: 'Vaults', route: '/admin/vaults'),
      if (widget.userService.canManageInstanceSettings)
        _AdminTab(label: 'Settings', route: '/admin/settings'),
      if (widget.userService.canViewAuditLog)
        _AdminTab(label: 'Events', route: '/admin/events'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Section header ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Administration',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      'Manage users, groups, roles, and system settings.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              CompositedTransformTarget(
                link: _overlayLink,
                child: SizedBox(
                  width: 280,
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    decoration: InputDecoration(
                      hintText: 'Search admin\u2026',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () {
                                _searchCtrl.clear();
                                _removeOverlay();
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                    onChanged: (_) {
                      setState(() {});
                      _showOverlay();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── Tab bar ────────────────────────────────────────────────
        Container(
          height: 48,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: tabs.map((tab) {
              final isActive =
                  path == tab.route || path.startsWith('${tab.route}/');
              return _AdminTabButton(
                label: tab.label,
                isActive: isActive,
                onTap: () => context.go(tab.route),
              );
            }).toList(),
          ),
        ),

        // ── Child screen ───────────────────────────────────────────
        Expanded(child: widget.child),
      ],
    );
  }
}

// ── Search overlay ────────────────────────────────────────────────────────────

class _SearchOverlay extends StatelessWidget {
  final LayerLink link;
  final List<_AdminSearchResult> results;
  final void Function(_AdminSearchResult) onSelect;
  final VoidCallback onDismiss;

  const _SearchOverlay({
    required this.link,
    required this.results,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Stack(
      children: [
        // Dismiss area
        GestureDetector(
          onTap: onDismiss,
          behavior: HitTestBehavior.translucent,
          child: const SizedBox.expand(),
        ),
        CompositedTransformFollower(
          link: link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 4),
          child: Material(
            elevation: 4,
            borderRadius: LumaRadius.radiusMd,
            color: cs.surface,
            surfaceTintColor: Colors.transparent,
            child: Container(
              width: 320,
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                borderRadius: LumaRadius.radiusMd,
                border: Border.all(color: cs.outlineVariant),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: results.length,
                separatorBuilder: (_, __) => const SizedBox.shrink(),
                itemBuilder: (_, i) {
                  final r = results[i];
                  return InkWell(
                    onTap: () => onSelect(r),
                    borderRadius: LumaRadius.radiusSm,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Icon(r.icon, size: 18, color: cs.onSurfaceVariant),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.label,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w500)),
                                if (r.subtitle != null)
                                  Text(r.subtitle!,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                              color: cs.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Data types ────────────────────────────────────────────────────────────────

class _AdminSearchResult {
  final String label;
  final String? subtitle;
  final String route;
  final IconData icon;

  const _AdminSearchResult({
    required this.label,
    this.subtitle,
    required this.route,
    required this.icon,
  });
}

class _AdminTab {
  final String label;
  final String route;
  const _AdminTab({required this.label, required this.route});
}

// ── Tab button ────────────────────────────────────────────────────────────────

class _AdminTabButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _AdminTabButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: isActive ? colorScheme.primary : colorScheme.onSurfaceVariant,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
        );

    return InkWell(
      onTap: onTap,
      borderRadius: LumaRadius.radiusXs,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: Text(label, style: textStyle),
      ),
    );
  }
}
