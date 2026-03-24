import 'package:flutter/material.dart';

/// A button that disables itself and shows a lock icon with a tooltip when
/// the caller lacks the required permission.
///
/// Set [filled] to keep a FilledButton style for primary actions (e.g. header
/// "Create" buttons). Default is OutlinedButton for row actions ("Manage").
class PermButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final String requiredPermission;
  final VoidCallback onPressed;
  final bool filled;

  const PermButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.requiredPermission,
    required this.onPressed,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    if (enabled) {
      if (filled) {
        return FilledButton(onPressed: onPressed, child: Text(label));
      }
      return OutlinedButton(onPressed: onPressed, child: Text(label));
    }

    // Disabled: show lock icon regardless of filled/outlined so the locked
    // state is visually consistent across all buttons.
    return Tooltip(
      message: 'Requires $requiredPermission',
      child: OutlinedButton.icon(
        icon: Icon(
          Icons.lock_outline,
          size: 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        label: Text(label),
        onPressed: null,
      ),
    );
  }
}
