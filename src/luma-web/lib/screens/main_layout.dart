import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:web/web.dart' as web;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_service.dart';
import '../services/page_service.dart';
import '../services/theme_notifier.dart';
import '../services/user_service.dart';
import '../theme/tokens.dart';
import '../widgets/luma_logo.dart';
import '../widgets/user_avatar.dart';

// ── Sidebar localStorage helpers ──────────────────────────────────────────────

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

// ── MainLayout ────────────────────────────────────────────────────────────────

class MainLayout extends StatefulWidget {
  final Widget child;
  final AuthService auth;
  final UserService userService;
  final ThemeNotifier themeNotifier;
  final PageService pageService;

  const MainLayout({
    super.key,
    required this.child,
    required this.auth,
    required this.userService,
    required this.themeNotifier,
    required this.pageService,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  late bool _isSidebarExpanded;
  bool _isHoveringLogo = false;
  final Set<String> _expandedVaults = {};

  /// Key on the RepaintBoundary wrapping the Scaffold — used to capture the
  /// screen before switching themes.
  final _repaintKey = GlobalKey();
  final _themeButtonKey = GlobalKey();
  final _userFooterKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _isSidebarExpanded = _loadSidebarState();
  }

  void _showDonateDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Support Luma'),
        content: const Text(
          'Thanks for using Luma! If you found this product helpful, '
          'please consider making a donation to support development.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('No, thanks'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              web.window
                  .open('https://github.com/sponsors/josephtindall', '_blank');
            },
            child: const Text('Yes, donate'),
          ),
        ],
      ),
    );
  }

  void _toggleSidebar() {
    setState(() {
      _isSidebarExpanded = !_isSidebarExpanded;
      _isHoveringLogo = false;
    });
    _saveSidebarState(_isSidebarExpanded);
  }

  /// Circle-mask theme transition:
  /// 1. Capture the current screen (old theme) as a raster image.
  /// 2. Immediately switch the theme so the real app renders the new theme.
  /// 3. Show an overlay that draws the old-theme screenshot with a growing
  ///    transparent hole — the hole reveals the live new-theme content beneath.
  Future<void> _doThemeTransition(
    BuildContext btnContext,
    ThemePreference next,
    Offset origin,
  ) async {
    if (widget.themeNotifier.preference == next) return;

    // Capture OverlayState and pixelRatio BEFORE any await so we never use
    // a potentially-deactivated BuildContext after an async gap.
    final overlayState = Overlay.of(btnContext);
    final pixelRatio = MediaQuery.devicePixelRatioOf(btnContext);

    final boundary = _repaintKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;

    if (boundary == null) {
      widget.themeNotifier.set(next);
      return;
    }

    ui.Image snapshot;
    try {
      snapshot = await boundary.toImage(pixelRatio: pixelRatio);
    } catch (_) {
      if (mounted) widget.themeNotifier.set(next);
      return;
    }

    if (!mounted) {
      snapshot.dispose();
      return;
    }

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _RevealOverlay(
        snapshot: snapshot,
        pixelRatio: pixelRatio,
        origin: origin,
        onComplete: () {
          entry.remove();
          snapshot.dispose();
        },
      ),
    );

    // Insert overlay (shows old theme screenshot over everything),
    // then immediately switch theme so the content beneath updates.
    // The growing hole in the overlay progressively reveals it.
    overlayState.insert(entry);
    widget.themeNotifier.set(next);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final surfaceColor = colorScheme.surface;
    final borderColor = colorScheme.outlineVariant.withAlpha(128);

    // RepaintBoundary lets us capture a pixel snapshot for the transition.
    return CallbackShortcuts(
      bindings: {
        // Meta+Shift+Q (Win) / Alt+Shift+Q → Sign out
        const SingleActivator(
          LogicalKeyboardKey.keyQ,
          meta: true,
          shift: true,
        ): _signOut,
        const SingleActivator(
          LogicalKeyboardKey.keyQ,
          alt: true,
          shift: true,
        ): _signOut,
        // Alt+S → Account settings
        const SingleActivator(
          LogicalKeyboardKey.keyS,
          alt: true,
        ): _goToSettings,
        // Meta+S → Account settings (macOS)
        const SingleActivator(
          LogicalKeyboardKey.keyS,
          meta: true,
        ): _goToSettings,
      },
      child: Focus(
        autofocus: true,
        child: RepaintBoundary(
      key: _repaintKey,
      child: Scaffold(
        body: Column(
          children: [
            // ── Top Navigation Bar ──────────────────────────────────────────
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: surfaceColor,
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildTopLeftBranding(),
                  const Spacer(),
                  // GitHub + Donate buttons (conditionally shown)
                  ListenableBuilder(
                    listenable: widget.userService,
                    builder: (context, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.userService.showGithubButton)
                          Tooltip(
                            message: 'View on GitHub',
                            child: IconButton(
                              icon: const Icon(Icons.code, size: 20),
                              onPressed: () => web.window.open(
                                'https://github.com/josephtindall/luma',
                                '_blank',
                              ),
                              style: IconButton.styleFrom(
                                shape: const RoundedRectangleBorder(
                                  borderRadius: LumaRadius.radiusMd,
                                ),
                              ),
                            ),
                          ),
                        if (widget.userService.showDonateButton)
                          Tooltip(
                            message: 'Donate to Support Development',
                            child: IconButton(
                              icon: const Icon(Icons.favorite_border, size: 20),
                              onPressed: () => _showDonateDialog(context),
                              style: IconButton.styleFrom(
                                shape: const RoundedRectangleBorder(
                                  borderRadius: LumaRadius.radiusMd,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Theme toggle (3-segment pill)
                  _ThemeToggleButton(
                    themeNotifier: widget.themeNotifier,
                    buttonKey: _themeButtonKey,
                    onSelected: _doThemeTransition,
                  ),
                ],
              ),
            ),
            // ── Lower content ───────────────────────────────────────────────
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
                          icon: Icons.grid_view_outlined,
                          activeIcon: Icons.grid_view,
                          label: 'All Items',
                          isSelected: GoRouterState.of(context)
                              .uri
                              .path == '/home',
                          onTap: () => context.go('/home'),
                        ),
                        const Divider(height: 1, indent: 12, endIndent: 12),
                        const SizedBox(height: 4),
                        Expanded(
                          child: ListenableBuilder(
                            listenable: widget.pageService,
                            builder: (context, _) => _buildVaultTree(context),
                          ),
                        ),
                        const Divider(height: 1, indent: 12, endIndent: 12),
                        _buildNavItem(
                          icon: Icons.delete_outline,
                          activeIcon: Icons.delete,
                          label: 'Trash',
                          isSelected: false,
                          onTap: () {},
                        ),
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
                        const SizedBox(height: 8),
                        // ── User footer ─────────────────────────────────
                        const Divider(height: 1, indent: 12, endIndent: 12),
                        _buildSidebarUserFooter(),
                      ],
                    ),
                  ),
                  // Main Content
                  ListenableBuilder(
                    listenable: widget.userService,
                    builder: (ctx, _) {
                      final cw = widget.userService.contentWidth;
                      final Widget content = ClipRect(child: widget.child);
                      if (cw == 'max') return Expanded(child: content);
                      final maxWidth = cw == 'narrow' ? 920.0 : 1360.0;
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
      ),
    ),
    ),
    );
  }

  Future<void> _createPageInVault(String vaultId) async {
    setState(() => _expandedVaults.add(vaultId));
    try {
      final page = await widget.pageService.createPage(vaultId);
      if (mounted) context.go('/pages/${page.shortId}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create page: $e')),
        );
      }
    }
  }

  Future<void> _showCreateVaultDialog() async {
    final controller = TextEditingController();
    bool isPrivate = true;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('New Vault'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Vault name',
                  hintText: 'e.g. Work',
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
              ),
              SwitchListTile(
                title: const Text('Private'),
                subtitle: const Text('Only members can access'),
                value: isPrivate,
                onChanged: (v) => setDialogState(() => isPrivate = v),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) return;
    try {
      final vault = await widget.pageService.createVault(
        result,
        isPrivate: isPrivate,
      );
      if (mounted) context.go('/vaults/${vault.slug}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create vault: $e')),
        );
      }
    }
  }

  Widget _buildVaultTree(BuildContext context) {
    if (!_isSidebarExpanded) {
      final currentPath = GoRouterState.of(context).uri.path;
      return Align(
        alignment: Alignment.topLeft,
        child: _buildNavItem(
          icon: Icons.description_outlined,
          activeIcon: Icons.description,
          label: 'Pages',
          isSelected: currentPath.startsWith('/vaults') ||
              currentPath.startsWith('/pages'),
          onTap: _toggleSidebar,
        ),
      );
    }

    if (widget.pageService.isLoadingVaults) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final items = <Widget>[];

    // Section header: "Vaults" label + "New Vault" button.
    items.add(Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Vaults',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                letterSpacing: 0.8,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            tooltip: 'New vault',
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              minimumSize: const Size(28, 28),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: _showCreateVaultDialog,
          ),
        ],
      ),
    ));

    for (final vault in widget.pageService.vaults) {
      final isExpanded = _expandedVaults.contains(vault.id);
      items.add(_buildVaultRow(context, vault, isExpanded));
      if (isExpanded) {
        final pages = widget.pageService.pagesByVault[vault.id] ?? [];
        for (final page in pages) {
          items.add(_buildPageItem(context, page));
        }
      }
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: items,
    );
  }

  Widget _buildVaultRow(
      BuildContext context, VaultSummary vault, bool isExpanded) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: LumaRadius.radiusMd,
        child: InkWell(
          borderRadius: LumaRadius.radiusMd,
          hoverColor: colorScheme.surfaceContainerHighest,
          onTap: () {
            setState(() => _expandedVaults.add(vault.id));
            widget.pageService.loadPagesForVault(vault.id);
            context.go('/vaults/${vault.slug}');
          },
          child: Container(
            height: 40,
            padding: const EdgeInsets.only(left: 8, right: 4),
            child: Row(
              children: [
                Icon(Icons.folder_outlined,
                    size: 18, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    vault.name,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: colorScheme.onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  iconSize: 16,
                  tooltip: 'New page',
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: const Size(28, 28),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: () => _createPageInVault(vault.id),
                ),
                IconButton(
                  icon: Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(28, 28),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedVaults.remove(vault.id);
                      } else {
                        _expandedVaults.add(vault.id);
                        widget.pageService.loadPagesForVault(vault.id);
                      }
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageItem(BuildContext context, PageSummary page) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected =
        GoRouterState.of(context).uri.path == '/pages/${page.shortId}';
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 12, top: 2, bottom: 2),
      child: Material(
        color: isSelected ? colorScheme.secondaryContainer : Colors.transparent,
        borderRadius: LumaRadius.radiusMd,
        child: InkWell(
          borderRadius: LumaRadius.radiusMd,
          hoverColor: colorScheme.surfaceContainerHighest,
          onTap: () => context.go('/pages/${page.shortId}'),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Icon(
                  Icons.article_outlined,
                  size: 16,
                  color: isSelected
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    page.title,
                    style: theme.textTheme.bodySmall?.copyWith(
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
    );
  }

  Widget _buildTopLeftBranding() {
    final instanceName = widget.auth.instanceName.isNotEmpty
        ? widget.auth.instanceName
        : 'Luma';
    if (_isSidebarExpanded) {
      return Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            child: const LumaLogo(size: 28),
          ),
          const SizedBox(width: 4),
          Text(
            instanceName,
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
              borderRadius: LumaRadius.radiusMd,
              color: _isHoveringLogo
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : Colors.transparent,
            ),
            child: _isHoveringLogo
                ? const Icon(Icons.menu, size: 24)
                : const LumaLogo(size: 28),
          ),
        ),
      );
    }
  }

  void _signOut() {
    widget.userService.clear();
    widget.auth.logout();
  }

  void _goToSettings() {
    context.go('/settings');
  }

  void _showUserFlyout() {
    final renderBox =
        _userFooterKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final screenSize = MediaQuery.of(context).size;
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = colorScheme.outlineVariant.withAlpha(128);

    // Position the menu to the right of the user footer, aligned to bottom.
    final leftEdge = position.dx + size.width + 8;
    final menuPosition = RelativeRect.fromLTRB(
      leftEdge,
      position.dy - 8,
      screenSize.width - leftEdge - 220, // keep menu near the sidebar
      0,
    );

    final isMac = Theme.of(context).platform == TargetPlatform.macOS;
    final settingsHint = isMac ? '⌘S' : 'Alt+S';
    final signOutHint = isMac ? '⌥⇧Q' : 'Win+⇧+Q';

    showMenu<String>(
      context: context,
      position: menuPosition,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: LumaRadius.radiusLg,
        side: BorderSide(color: borderColor),
      ),
      surfaceTintColor: Colors.transparent,
      color: colorScheme.surface,
      constraints: const BoxConstraints(minWidth: 220),
      items: [
        PopupMenuItem<String>(
          value: 'settings',
          height: 44,
          child: Row(
            children: [
              Icon(Icons.settings_outlined,
                  size: 18, color: colorScheme.onSurface),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Account settings',
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
              Text(
                settingsHint,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'signout',
          height: 44,
          child: Row(
            children: [
              Icon(Icons.logout, size: 18, color: colorScheme.onSurface),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Sign out',
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
              Text(
                signOutHint,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'settings') {
        _goToSettings();
      } else if (value == 'signout') {
        _signOut();
      }
    });
  }

  Widget _buildSidebarUserFooter() {
    final colorScheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: widget.userService,
      builder: (context, _) {
        final profile = widget.userService.profile;
        final name = profile?.displayName ?? 'Account';
        final email = profile?.email ?? '';
        final seed = profile?.avatarSeed ?? '';

        if (!_isSidebarExpanded) {
          // Collapsed: just an avatar button
          return Padding(
            key: _userFooterKey,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Tooltip(
                message: name,
                child: InkWell(
                  borderRadius: LumaRadius.radiusMd,
                  onTap: _showUserFlyout,
                  child: UserAvatar(
                    avatarSeed: seed,
                    displayName: name,
                    size: 36,
                  ),
                ),
              ),
            ),
          );
        }

        // Expanded: full user row
        return Material(
          key: _userFooterKey,
          color: Colors.transparent,
          child: InkWell(
            onTap: _showUserFlyout,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              child: Row(
                children: [
                  UserAvatar(
                    avatarSeed: seed,
                    displayName: name,
                    size: 36,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        if (email.isNotEmpty)
                          Text(
                            email,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.unfold_more,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
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
        borderRadius: LumaRadius.radiusMd,
        child: InkWell(
          borderRadius: LumaRadius.radiusMd,
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

// ── Theme Toggle Panel ────────────────────────────────────────────────────────

/// A 3-button segmented pill: [System] [Light] [Dark].
/// Each button is always visible; the active one is highlighted.
class _ThemeToggleButton extends StatelessWidget {
  final ThemeNotifier themeNotifier;
  final GlobalKey buttonKey;
  final void Function(BuildContext context, ThemePreference next, Offset origin)
      onSelected;

  const _ThemeToggleButton({
    required this.themeNotifier,
    required this.buttonKey,
    required this.onSelected,
  });

  void _select(BuildContext context, ThemePreference next) {
    if (themeNotifier.preference == next) return;
    // Use the tapped segment's center as the ripple origin.
    final box = context.findRenderObject() as RenderBox?;
    Offset origin = Offset(MediaQuery.sizeOf(context).width / 2, 28);
    if (box != null) {
      origin = box.localToGlobal(box.size.center(Offset.zero));
    }
    onSelected(context, next, origin);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeNotifier,
      builder: (context, _) {
        final current = themeNotifier.preference;
        final colorScheme = Theme.of(context).colorScheme;

        return Container(
          key: buttonKey,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: LumaRadius.radiusMd,
          ),
          padding: const EdgeInsets.all(3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Segment(
                icon: Icons.brightness_auto_outlined,
                label: 'System',
                selected: current == ThemePreference.system,
                onTap: (ctx) => _select(ctx, ThemePreference.system),
              ),
              _Segment(
                icon: Icons.light_mode_outlined,
                label: 'Light',
                selected: current == ThemePreference.light,
                onTap: (ctx) => _select(ctx, ThemePreference.light),
              ),
              _Segment(
                icon: Icons.dark_mode_outlined,
                label: 'Dark',
                selected: current == ThemePreference.dark,
                onTap: (ctx) => _select(ctx, ThemePreference.dark),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Segment extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final void Function(BuildContext context) onTap;

  const _Segment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => widget.onTap(context),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            width: 32,
            height: 30,
            decoration: BoxDecoration(
              color: widget.selected
                  ? colorScheme.surface
                  : _hovering
                      ? colorScheme.surfaceContainerHighest
                      : Colors.transparent,
              borderRadius: LumaRadius.radiusSm,
              boxShadow: widget.selected
                  ? [
                      BoxShadow(
                        color: colorScheme.shadow.withValues(alpha: 0.12),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              widget.icon,
              size: 16,
              color: widget.selected || _hovering
                  ? colorScheme.onSurface
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Circle-mask reveal overlay ────────────────────────────────────────────────
//
// Technique:
//   1. A raster snapshot of the OLD theme is captured before the switch.
//   2. The new theme is applied immediately so the real app renders it.
//   3. This overlay draws the old-theme snapshot as a full-screen cover.
//   4. A growing transparent hole (BlendMode.clear inside a saveLayer) is
//      punched in the snapshot, progressively revealing the live new-theme
//      content beneath.
//   5. When the hole covers the whole screen the overlay is removed.

class _RevealOverlay extends StatefulWidget {
  final ui.Image snapshot;
  final double pixelRatio;
  final Offset origin;
  final VoidCallback onComplete;

  const _RevealOverlay({
    required this.snapshot,
    required this.pixelRatio,
    required this.origin,
    required this.onComplete,
  });

  @override
  State<_RevealOverlay> createState() => _RevealOverlayState();
}

class _RevealOverlayState extends State<_RevealOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _progress = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onComplete();
    });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final o = widget.origin;

    // Radius needed to fully cover the screen from the origin point.
    final maxRadius = [
      o.distance,
      (o - Offset(size.width, 0)).distance,
      (o - Offset(0, size.height)).distance,
      (o - Offset(size.width, size.height)).distance,
    ].reduce(math.max);

    return AnimatedBuilder(
      animation: _progress,
      builder: (_, __) => CustomPaint(
        painter: _RevealPainter(
          snapshot: widget.snapshot,
          pixelRatio: widget.pixelRatio,
          origin: o,
          holeRadius: _progress.value * maxRadius,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _RevealPainter extends CustomPainter {
  final ui.Image snapshot;
  final double pixelRatio;
  final Offset origin;
  final double holeRadius;

  const _RevealPainter({
    required this.snapshot,
    required this.pixelRatio,
    required this.origin,
    required this.holeRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // saveLayer is required so that BlendMode.clear erases within the layer
    // (making those pixels transparent) rather than clearing the canvas itself.
    canvas.saveLayer(Offset.zero & size, Paint());

    // Draw the old-theme screenshot, scaling from physical → logical pixels.
    canvas.save();
    canvas.scale(1.0 / pixelRatio);
    canvas.drawImage(snapshot, Offset.zero, Paint());
    canvas.restore();

    // Punch a growing transparent circle — the app beneath shows through.
    if (holeRadius > 0) {
      canvas.drawCircle(
        origin,
        holeRadius,
        Paint()..blendMode = BlendMode.clear,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_RevealPainter old) =>
      old.holeRadius != holeRadius ||
      old.origin != origin ||
      old.snapshot != snapshot;
}
