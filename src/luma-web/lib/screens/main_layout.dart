import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../widgets/user_avatar.dart';

bool _loadSidebarState() {
  try {
    final storage = globalContext['localStorage'] as JSObject?;
    if (storage == null) return false;
    final raw = (storage.callMethod<JSAny?>(
            'getItem'.toJS, 'luma_sidebar_expanded'.toJS) as JSString?)
        ?.toDart;
    return raw == 'true';
  } catch (_) {
    return false;
  }
}

void _saveSidebarState(bool expanded) {
  try {
    final storage = globalContext['localStorage'] as JSObject?;
    if (storage == null) return;
    storage.callMethod<JSAny?>(
        'setItem'.toJS, 'luma_sidebar_expanded'.toJS, expanded.toString().toJS);
  } catch (_) {}
}

class MainLayout extends StatefulWidget {
  final Widget child;
  final AuthService auth;
  final UserService userService;

  const MainLayout({
    super.key,
    required this.child,
    required this.auth,
    required this.userService,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  late bool _isSidebarExpanded;
  bool _isHoveringLogo = false;

  @override
  void initState() {
    super.initState();
    _isSidebarExpanded = _loadSidebarState();
  }

  void _toggleSidebar() {
    setState(() {
      _isSidebarExpanded = !_isSidebarExpanded;
      _isHoveringLogo = false; // Fixes stuck hover state on toggle
    });
    _saveSidebarState(_isSidebarExpanded);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final surfaceColor = colorScheme.surface;
    final borderColor = colorScheme.outlineVariant.withAlpha(128);

    return Scaffold(
      body: Column(
        children: [
          // Top Navigation Bar
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: surfaceColor,
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // Left side: Logo or Hamburger
                _buildTopLeftBranding(),
                const Spacer(),
                // Right side: User Profile
                _buildTopRightUserMenu(),
              ],
            ),
          ),
          // Lower content
          Expanded(
            child: Row(
              children: [
                // Collapsible Sidebar
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  width: _isSidebarExpanded ? 240 : 68,
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    border: Border(right: BorderSide(color: borderColor)),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      _buildNavItem(
                        icon: Icons.folder_outlined,
                        activeIcon: Icons.folder,
                        label: 'My Space',
                        isSelected: GoRouterState.of(context)
                            .uri
                            .path
                            .startsWith('/home'),
                        onTap: () => context.go('/home'),
                      ),
                      _buildNavItem(
                        icon: Icons.people_outline,
                        activeIcon: Icons.people,
                        label: 'Shared',
                        isSelected: false,
                        onTap: () {
                          // Not implemented yet
                        },
                      ),
                      const Spacer(),
                      ListenableBuilder(
                        listenable: widget.userService,
                        builder: (context, _) {
                          if (!widget.userService.hasAdminAccess) {
                            return const SizedBox.shrink();
                          }
                          return _buildNavItem(
                            icon: Icons.admin_panel_settings_outlined,
                            activeIcon: Icons.admin_panel_settings,
                            label: 'Admin',
                            isSelected: GoRouterState.of(context)
                                .uri
                                .path
                                .startsWith('/admin'),
                            onTap: () => context.go('/admin/users'),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                // Main Content — width constrained by instance setting.
                ListenableBuilder(
                  listenable: widget.userService,
                  builder: (ctx, _) {
                    final cw = widget.userService.contentWidth;
                    final Widget content = ClipRect(child: widget.child);
                    if (cw == 'max') {
                      return Expanded(child: content);
                    }
                    final maxWidth = cw == 'narrow' ? 740.0 : 1140.0;
                    return Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxWidth),
                          child: content,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopLeftBranding() {
    if (_isSidebarExpanded) {
      return Row(
        children: [
          const Icon(Icons.lens_blur, size: 24),
          const SizedBox(width: 8),
          Text(
            'Luma',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(width: 24),
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: _toggleSidebar,
            tooltip: 'Collapse menu',
          ),
        ],
      );
    } else {
      // Collapsed: Logo that turns into Hamburger on hover
      return MouseRegion(
        onEnter: (_) => setState(() => _isHoveringLogo = true),
        onExit: (_) => setState(() => _isHoveringLogo = false),
        child: GestureDetector(
          onTap: _toggleSidebar,
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: _isHoveringLogo
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : Colors.transparent,
            ),
            child: _isHoveringLogo
                ? const Icon(Icons.menu, size: 24)
                : const Icon(Icons.lens_blur, size: 24),
          ),
        ),
      );
    }
  }

  Widget _buildTopRightUserMenu() {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = colorScheme.outlineVariant.withAlpha(128);

    return ListenableBuilder(
      listenable: widget.userService,
      builder: (context, _) {
        final profile = widget.userService.profile;
        final name = profile?.displayName ?? 'Account';
        final email = profile?.email;
        final seed = profile?.avatarSeed ?? '';

        return MenuAnchor(
          alignmentOffset: const Offset(0, 8),
          style: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(colorScheme.surface),
            elevation: const WidgetStatePropertyAll(4),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: borderColor),
            )),
          ),
          menuChildren: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  UserAvatar(avatarSeed: seed, displayName: name, size: 40),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  )),
                      if (email != null)
                        Text(email,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    )),
                    ],
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            MenuItemButton(
              leadingIcon: const Icon(Icons.settings_outlined),
              child: const Text('Settings'),
              onPressed: () => context.go('/settings'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.logout),
              child: const Text('Log out'),
              onPressed: () {
                widget.userService.clear();
                widget.auth.logout();
              },
            ),
          ],
          builder: (context, controller, _) {
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    UserAvatar(
                      avatarSeed: seed,
                      displayName: name,
                      size: 28,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      name,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: isSelected ? colorScheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          hoverColor: colorScheme.surfaceContainerHighest,
          child: Tooltip(
            message: _isSidebarExpanded ? '' : label,
            preferBelow: false,
            child: Container(
              height: 44,
              alignment: Alignment.centerLeft,
              child: ClipRect(
                child: OverflowBox(
                  maxWidth: 216,
                  minWidth: 216,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      // Pushes the icon inward by 12, making its center hit 12+10=22.
                      // Since the narrowed container width is 44 (68 total - 24 padding),
                      // the icon falls perfectly in the center. Unchanging width = no jump.
                      const SizedBox(width: 12),
                      Icon(
                        isSelected ? activeIcon : icon,
                        size: 20,
                        color: isSelected
                            ? colorScheme.onSecondaryContainer
                            : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isSelected
                                ? colorScheme.onSecondaryContainer
                                : colorScheme.onSurface,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
