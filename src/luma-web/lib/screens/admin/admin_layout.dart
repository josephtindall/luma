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
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = colorScheme.outlineVariant.withAlpha(128);

    final tabs = [
      if (userService.canManageUsers)
        _AdminTab(label: 'Users', route: '/admin/users'),
      if (userService.canManageInvitations)
        _AdminTab(label: 'Invitations', route: '/admin/invites'),
      if (userService.canManageGroups) _AdminTab(label: 'Groups', route: '/admin/groups'),
      if (userService.canManageRoles) _AdminTab(label: 'Roles', route: '/admin/roles'),
      if (userService.canManageVaults)
        _AdminTab(label: 'Vaults', route: '/admin/vaults'),
      if (userService.canManageInstanceSettings)
        _AdminTab(label: 'Settings', route: '/admin/settings'),
      if (userService.canViewAuditLog)
        _AdminTab(label: 'Events', route: '/admin/events'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top tab bar
        Container(
          height: 48,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: tabs.map((tab) {
              final isActive = path == tab.route ||
                  path.startsWith('${tab.route}/');
              return _AdminTabButton(
                label: tab.label,
                isActive: isActive,
                onTap: () => context.go(tab.route),
              );
            }).toList(),
          ),
        ),
        // Child screen
        Expanded(child: child),
      ],
    );
  }
}

class _AdminTab {
  final String label;
  final String route;
  const _AdminTab({required this.label, required this.route});
}

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
