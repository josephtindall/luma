import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/user_service.dart';

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
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
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
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          '${vaults.length} total \u00b7 Manage all vaults in the instance.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
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
                const Center(child: Text('No vaults found.'))
              else
                Expanded(
                  child: SingleChildScrollView(
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Name')),
                        DataColumn(label: Text('Slug')),
                        DataColumn(label: Text('Visibility')),
                        DataColumn(label: Text('Created')),
                        DataColumn(label: Text('')),
                      ],
                      rows: vaults.map((v) {
                        return DataRow(cells: [
                          DataCell(Text(v.name)),
                          DataCell(Text(v.slug)),
                          DataCell(
                            Chip(
                              label: Text(v.isPrivate ? 'Private' : 'Shared'),
                              backgroundColor: v.isPrivate
                                  ? Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                  : Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                              side: BorderSide.none,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          DataCell(Text(_formatDate(v.createdAt))),
                          DataCell(
                            TextButton(
                              onPressed: () =>
                                  context.go('/admin/vaults/${v.id}/settings'),
                              child: const Text('Manage'),
                            ),
                          ),
                        ]);
                      }).toList(),
                    ),
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
