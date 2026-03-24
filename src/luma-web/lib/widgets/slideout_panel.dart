import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Width at which the slideout covers the full viewport.
const _breakpoint = 640.0;

/// Default panel width on large screens.
const _panelWidth = 480.0;

/// Shows a slideout panel that slides in from the right edge of the screen.
///
/// On viewports wider than 640px the panel is 480px wide with a scrim behind.
/// On narrow viewports the panel covers the full width.
///
/// Provide [title] for a static title, or [titleNotifier] for a title that
/// can change after the panel is open (e.g. create → detail transition).
Future<T?> showSlideoutPanel<T>({
  required BuildContext context,
  String? title,
  ValueNotifier<String>? titleNotifier,
  required Widget Function(BuildContext) bodyBuilder,
  List<Widget>? actions,
}) {
  assert(title != null || titleNotifier != null, 'Provide title or titleNotifier');
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, _, __) => _SlideoutShell(
      title: title,
      titleNotifier: titleNotifier,
      actions: actions,
      bodyBuilder: bodyBuilder,
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class _SlideoutShell extends StatelessWidget {
  final String? title;
  final ValueNotifier<String>? titleNotifier;
  final List<Widget>? actions;
  final Widget Function(BuildContext) bodyBuilder;

  const _SlideoutShell({
    this.title,
    this.titleNotifier,
    this.actions,
    required this.bodyBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isFullWidth = screenWidth < _breakpoint;
    final panelWidth = isFullWidth ? screenWidth : _panelWidth;
    final titleStyle = Theme.of(context)
        .textTheme
        .titleMedium
        ?.copyWith(fontWeight: FontWeight.w600);

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        elevation: 0,
        color: colorScheme.surface,
        child: Container(
          width: panelWidth,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            boxShadow: LumaShadow.xl,
            border: isFullWidth
                ? null
                : Border(
                    left: BorderSide(
                      color: colorScheme.outlineVariant,
                    ),
                  ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: colorScheme.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: titleNotifier != null
                          ? ValueListenableBuilder<String>(
                              valueListenable: titleNotifier!,
                              builder: (_, value, __) => Text(
                                value,
                                style: titleStyle,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                          : Text(
                              title ?? '',
                              style: titleStyle,
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                    if (actions != null) ...actions!,
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // Body
              Expanded(
                child: bodyBuilder(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
