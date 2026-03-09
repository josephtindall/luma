import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/user_service.dart';

class AdminLayout extends StatelessWidget {
  final Widget child;
  final UserService userService;

  const AdminLayout({super.key, required this.child, required this.userService});

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = colorScheme.outlineVariant.withAlpha(128);
    final isOwner = userService.profile?.isOwner == true;

    final tabs = [
      _AdminTab(label: 'Users', route: '/admin/users'),
      _AdminTab(label: 'Invitations', route: '/admin/invites'),
      if (isOwner) _AdminTab(label: 'Groups', route: '/admin/groups'),
      if (isOwner) _AdminTab(label: 'Roles', route: '/admin/roles'),
      _AdminTab(label: 'Settings', route: '/admin/settings'),
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
                  (tab.route != '/admin/users' && path.startsWith(tab.route));
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
      borderRadius: BorderRadius.circular(4),
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
