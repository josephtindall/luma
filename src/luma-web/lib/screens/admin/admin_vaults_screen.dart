import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/user_service.dart';
import '../../theme/tokens.dart';
import '../../widgets/data_table.dart';

class AdminVaultsScreen extends StatefulWidget {
  final UserService userService;

  const AdminVaultsScreen({super.key, required this.userService});

  @override
  State<AdminVaultsScreen> createState() => _AdminVaultsScreenState();
}

class _AdminVaultsScreenState extends State<AdminVaultsScreen> {
  late Future<List<AdminVaultRecord>> _vaultsFuture;

  @override
  void initState() {
    super.initState();
    _vaultsFuture = widget.userService.listAllVaults();
  }

  void _reload() {
    setState(() {
      _vaultsFuture = widget.userService.listAllVaults();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return FutureBuilder<List<AdminVaultRecord>>(
      future: _vaultsFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Could not load vaults: ${snap.error}',
                  style: TextStyle(color: cs.error),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _reload, child: const Text('Retry')),
              ],
            ),
          );
        }

        final vaults = snap.data ?? [];

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Vaults',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          '${vaults.length} total \u00b7 Manage all vaults in the instance.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                    onPressed: _reload,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (vaults.isEmpty)
                const Expanded(
                    child: Center(child: Text('No vaults found.')))
              else
                Expanded(
                  child: LumaDataTable<AdminVaultRecord>(
                    onRowTap: (v) =>
                        context.go('/admin/vaults/${v.id}/settings'),
                    columns: [
                      LumaColumn<AdminVaultRecord>(
                        label: 'Name',
                        cellBuilder: (v, _) => Text(
                          v.name,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      LumaColumn<AdminVaultRecord>(
                        label: 'Slug',
                        width: 160,
                        cellBuilder: (v, _) => Text(
                          v.slug,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                      ),
                      LumaColumn<AdminVaultRecord>(
                        label: 'Visibility',
                        width: 120,
                        cellBuilder: (v, _) => _VisibilityBadge(
                            isPrivate: v.isPrivate),
                      ),
                      LumaColumn<AdminVaultRecord>(
                        label: 'Created',
                        width: 120,
                        cellBuilder: (v, _) => Text(
                          _formatDate(v.createdAt),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      LumaColumn<AdminVaultRecord>(
                        label: '',
                        width: 100,
                        cellBuilder: (v, _) => Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => context
                                .go('/admin/vaults/${v.id}/settings'),
                            child: const Text('Manage'),
                          ),
                        ),
                      ),
                    ],
                    rows: vaults,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

class _VisibilityBadge extends StatelessWidget {
  final bool isPrivate;

  const _VisibilityBadge({required this.isPrivate});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isPrivate
            ? cs.surfaceContainerHighest
            : cs.primaryContainer,
        borderRadius: LumaRadius.radiusLg,
      ),
      child: Text(
        isPrivate ? 'Private' : 'Shared',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isPrivate
                  ? cs.onSurfaceVariant
                  : cs.onPrimaryContainer,
            ),
      ),
    );
  }
}
