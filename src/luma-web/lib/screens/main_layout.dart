import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:web/web.dart' as web;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_service.dart';
import '../services/theme_notifier.dart';
import '../services/user_service.dart';
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

  const MainLayout({
    super.key,
    required this.child,
    required this.auth,
    required this.userService,
    required this.themeNotifier,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  late bool _isSidebarExpanded;
  bool _isHoveringLogo = false;

  /// Key on the RepaintBoundary wrapping the Scaffold — used to capture the
  /// screen before switching themes.
  final _repaintKey = GlobalKey();
  final _themeButtonKey = GlobalKey();

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
    return RepaintBoundary(
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
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
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
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
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
                  const SizedBox(width: 4),
                  // User badge → sign-out flyout
                  _buildTopRightUserMenu(),
                  const SizedBox(width: 4),
                  // Settings gear
                  Tooltip(
                    message: 'Settings',
                    child: IconButton(
                      icon: const Icon(Icons.settings_outlined, size: 20),
                      onPressed: () => context.go('/settings'),
                      style: IconButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
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
                          onTap: () {},
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
            MenuItemButton(
              leadingIcon: const Icon(Icons.logout),
              child: const Text('Sign out'),
              onPressed: () {
                widget.userService.clear();
                widget.auth.logout();
              },
            ),
          ],
          builder: (context, controller, _) {
            return Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UserAvatar(avatarSeed: seed, displayName: name, size: 28),
                      const SizedBox(width: 8),
                      Text(
                        name,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
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
            borderRadius: BorderRadius.circular(8),
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
              borderRadius: BorderRadius.circular(6),
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
