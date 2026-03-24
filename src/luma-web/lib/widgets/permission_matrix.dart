import 'package:flutter/material.dart';

import '../models/custom_role.dart';
import '../theme/tokens.dart';

/// Canonical action groups for the permissions UI.
const actionGroups = <String, List<String>>{
  'Administration': ['admin:access'],
  'Pages': [
    'page:read',
    'page:create',
    'page:edit',
    'page:delete',
    'page:archive',
    'page:version',
    'page:restore-version',
    'page:share',
    'page:transclude',
  ],
  'Tasks': [
    'task:read',
    'task:create',
    'task:edit',
    'task:delete',
    'task:assign',
    'task:close',
    'task:comment',
  ],
  'Flows': [
    'flow:read',
    'flow:create',
    'flow:edit',
    'flow:delete',
    'flow:publish',
    'flow:execute',
    'flow:comment',
  ],
  'Vaults': [
    'vault:read',
    'vault:create',
    'vault:edit',
    'vault:delete',
    'vault:archive',
    'vault:manage-members',
    'vault:manage-roles',
  ],
  'Users': [
    'user:read',
    'user:invite',
    'user:edit',
    'user:delete',
    'user:lock',
    'user:unlock',
    'user:revoke-sessions',
  ],
  'Audit': [
    'audit:read-own',
    'audit:read-all',
    'audit:export-all',
    'audit:read-pii',
  ],
  'Instance': [
    'instance:read',
    'instance:configure',
    'instance:backup',
    'instance:restore',
  ],
  'Notifications': [
    'notification:read',
    'notification:configure-own',
    'notification:configure-all',
  ],
  'Invitations': ['invitation:create', 'invitation:revoke', 'invitation:list'],
  'Groups': [
    'group:read',
    'group:create',
    'group:rename',
    'group:delete',
    'group:add-member',
    'group:remove-member',
    'group:assign-role',
    'group:unassign-role',
  ],
  'Roles': [
    'role:read',
    'role:create',
    'role:update',
    'role:delete',
    'role:set-permission',
    'role:remove-permission',
    'role:assign-user',
    'role:unassign-user',
  ],
};

/// Resolves effective permissions from a list of roles.
///
/// Priority: deny > allow_cascade > allow > (unset).
Map<String, String> resolveEffectivePermissions(List<CustomRoleRecord> roles) {
  final result = <String, String>{};
  for (final role in roles) {
    for (final p in role.permissions) {
      final current = result[p.action] ?? '';
      if (p.effect == 'deny') {
        result[p.action] = 'deny';
      } else if (p.effect == 'allow_cascade' && current != 'deny') {
        result[p.action] = 'allow_cascade';
      } else if (p.effect == 'allow' && current.isEmpty) {
        result[p.action] = 'allow';
      }
    }
  }
  return result;
}

/// Renders the full permission groups grid.
///
/// When [readOnly] is true, toggles are disabled (view-only).
/// When [onSet] is provided and [readOnly] is false, toggles call [onSet].
class PermissionMatrix extends StatelessWidget {
  final Map<String, String> permMap;
  final bool readOnly;
  final Future<void> Function(String action, String effect)? onSet;

  const PermissionMatrix({
    super.key,
    required this.permMap,
    this.readOnly = true,
    this.onSet,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                readOnly
                    ? 'Aggregated from assigned roles'
                    : 'Cascade = allow_cascade, inherited through group nesting',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            const EffectLegend(),
          ],
        ),
        const SizedBox(height: 12),
        ...actionGroups.entries.map((entry) {
          return PermissionGroup(
            groupName: entry.key,
            actions: entry.value,
            permMap: permMap,
            readOnly: readOnly,
            onSet: onSet ?? (_, __) async {},
          );
        }),
      ],
    );
  }
}

// ── Permission group + row ────────────────────────────────────────────────────

class PermissionGroup extends StatefulWidget {
  final String groupName;
  final List<String> actions;
  final Map<String, String> permMap;
  final bool readOnly;
  final Future<void> Function(String action, String effect) onSet;

  const PermissionGroup({
    super.key,
    required this.groupName,
    required this.actions,
    required this.permMap,
    required this.readOnly,
    required this.onSet,
  });

  @override
  State<PermissionGroup> createState() => _PermissionGroupState();
}

class _PermissionGroupState extends State<PermissionGroup> {
  late bool _expanded;

  int get _setCount =>
      widget.actions.where((a) => widget.permMap.containsKey(a)).length;

  @override
  void initState() {
    super.initState();
    _expanded = widget.actions.any((a) => widget.permMap.containsKey(a));
  }

  Future<void> _grantAll() async {
    await Future.wait(
      widget.actions
          .where((a) => widget.permMap[a] != 'allow')
          .map((a) => widget.onSet(a, 'allow')),
    );
  }

  Future<void> _clearAll() async {
    await Future.wait(
      widget.actions
          .where((a) => widget.permMap.containsKey(a))
          .map((a) => widget.onSet(a, '')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final setCount = _setCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: LumaRadius.radiusMd,
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  borderRadius: LumaRadius.radiusMd,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_right,
                          size: 16,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.groupName,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (!_expanded && setCount > 0) ...[
                          const SizedBox(width: 8),
                          _InfoChip(
                            label: '$setCount of ${widget.actions.length}',
                            color: colorScheme.primaryContainer,
                            textColor: colorScheme.onPrimaryContainer,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (!widget.readOnly) ...[
                _GroupAction(
                  label: 'All',
                  tooltip: 'Grant all permissions in this group',
                  onTap: _grantAll,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 2),
                _GroupAction(
                  label: 'Clear',
                  tooltip: 'Remove all permissions in this group',
                  onTap: _clearAll,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        if (_expanded) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: colorScheme.outlineVariant,
                  width: 2,
                ),
              ),
            ),
            child: Column(
              children: widget.actions
                  .map((action) => _PermissionRow(
                        action: action,
                        effect: widget.permMap[action] ?? '',
                        readOnly: widget.readOnly,
                        onSet: widget.onSet,
                      ))
                  .toList(),
            ),
          ),
        ] else
          const SizedBox(height: 4),
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final String action;
  final String effect;
  final bool readOnly;
  final Future<void> Function(String action, String effect) onSet;

  const _PermissionRow({
    required this.action,
    required this.effect,
    required this.readOnly,
    required this.onSet,
  });

  String get _label {
    final idx = action.indexOf(':');
    final suffix = idx >= 0 ? action.substring(idx + 1) : action;
    return suffix
        .split('-')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasEffect = effect.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: hasEffect
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                    fontWeight: hasEffect ? FontWeight.w500 : FontWeight.normal,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          _EffectToggle(
            effect: effect,
            readOnly: readOnly,
            onChanged: (newEffect) => onSet(action, newEffect),
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
  }
}

class _EffectToggle extends StatelessWidget {
  final String effect;
  final bool readOnly;
  final void Function(String) onChanged;
  final ColorScheme colorScheme;

  const _EffectToggle({
    required this.effect,
    required this.readOnly,
    required this.onChanged,
    required this.colorScheme,
  });

  static const _options = [
    ('', '—', 'Not set'),
    ('allow', '✓', 'Allow'),
    ('allow_cascade', '↓', 'Cascade'),
    ('deny', '✕', 'Deny'),
  ];

  Color _activeColor(String val) {
    switch (val) {
      case 'allow':
        return const Color(0xFF039855);
      case 'allow_cascade':
        return const Color(0xFF1570EF);
      case 'deny':
        return colorScheme.error;
      default:
        return colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: _options.map((opt) {
        final (val, label, tooltip) = opt;
        final isSelected = effect == val;
        final fgColor = isSelected
            ? _activeColor(val)
            : colorScheme.onSurfaceVariant.withAlpha(80);
        final bgColor =
            isSelected ? _activeColor(val).withAlpha(30) : Colors.transparent;
        final borderColor = isSelected
            ? _activeColor(val).withAlpha(160)
            : colorScheme.outline.withAlpha(60);

        return Tooltip(
          message: tooltip,
          waitDuration: const Duration(milliseconds: 600),
          child: GestureDetector(
            onTap: readOnly ? null : () => onChanged(val),
            child: Container(
              width: 30,
              height: 26,
              margin: const EdgeInsets.only(left: 3),
              decoration: BoxDecoration(
                color: bgColor,
                border: Border.all(color: borderColor, width: 1),
                borderRadius: LumaRadius.radiusSm,
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: fgColor,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class EffectLegend extends StatelessWidget {
  const EffectLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('—', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        const SizedBox(width: 4),
        Text('✓ Allow', style: TextStyle(fontSize: 11, color: const Color(0xFF039855))),
        const SizedBox(width: 4),
        Text('↓ Cascade', style: TextStyle(fontSize: 11, color: const Color(0xFF1570EF))),
        const SizedBox(width: 4),
        Text('✕ Deny', style: TextStyle(fontSize: 11, color: cs.error)),
      ],
    );
  }
}

class _GroupAction extends StatelessWidget {
  final String label;
  final String tooltip;
  final Future<void> Function() onTap;
  final Color color;

  const _GroupAction({
    required this.label,
    required this.tooltip,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: LumaRadius.radiusXs,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;

  const _InfoChip({required this.label, required this.color, required this.textColor});

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
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: textColor),
      ),
    );
  }
}
