import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/tokens.dart';

class SettingsLayout extends StatelessWidget {
  final Widget child;

  const SettingsLayout({super.key, required this.child});

  static const _tabs = [
    _SettingsTab(label: 'Profile', route: '/settings/profile'),
    _SettingsTab(label: 'Security', route: '/settings/security'),
    _SettingsTab(label: 'Activity', route: '/settings/activity'),
  ];

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = colorScheme.outlineVariant.withAlpha(128);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tab bar
        Container(
          height: 48,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: _tabs.map((tab) {
              final isActive = path.startsWith(tab.route);
              return _SettingsTabButton(
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

class _SettingsTab {
  final String label;
  final String route;
  const _SettingsTab({required this.label, required this.route});
}

class _SettingsTabButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _SettingsTabButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color:
              isActive ? colorScheme.primary : colorScheme.onSurfaceVariant,
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
