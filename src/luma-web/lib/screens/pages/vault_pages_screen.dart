import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/page_service.dart';

class VaultPagesScreen extends StatefulWidget {
  final String slug;
  final PageService pageService;

  const VaultPagesScreen({
    super.key,
    required this.slug,
    required this.pageService,
  });

  @override
  State<VaultPagesScreen> createState() => _VaultPagesScreenState();
}

class _VaultPagesScreenState extends State<VaultPagesScreen> {
  bool _loading = false;
  String? _error;
  bool _canManageMembers = false;

  VaultSummary? get _vault {
    try {
      return widget.pageService.vaults.firstWhere((v) => v.slug == widget.slug);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(VaultPagesScreen old) {
    super.didUpdateWidget(old);
    if (old.slug != widget.slug) _ensureLoaded();
  }

  Future<void> _ensureLoaded() async {
    final vaultId = _vault?.id;
    if (vaultId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Future.wait([
        if (!widget.pageService.pagesByVault.containsKey(vaultId))
          widget.pageService.loadPagesForVault(vaultId),
        widget.pageService
            .fetchVaultPermissions(vaultId)
            .then((p) {
          if (mounted) {
            setState(() => _canManageMembers = p['can_manage_members'] == true);
          }
        }),
      ]);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createPage() async {
    final vaultId = _vault?.id;
    if (vaultId == null) return;
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

  @override
  Widget build(BuildContext context) {
    final vault = _vault;
    if (vault == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Vault')),
        body: const Center(child: Text('Vault not found.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(vault.name),
        actions: [
          if (_canManageMembers)
            IconButton(
              tooltip: 'Vault settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.go('/vaults/${widget.slug}/settings'),
            ),
          IconButton(
            tooltip: 'New page',
            icon: const Icon(Icons.add),
            onPressed: _createPage,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.pageService,
        builder: (context, _) {
          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_error != null) {
            return Center(
              child: Text(
                'Could not load pages: $_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            );
          }
          final pages = widget.pageService.pagesByVault[vault.id] ?? [];
          if (pages.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.article_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No pages yet.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: _createPage,
                    child: const Text('Create first page'),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: pages.length,
            itemBuilder: (context, i) {
              final page = pages[i];
              return ListTile(
                leading: const Icon(Icons.article_outlined),
                title: Text(page.title),
                onTap: () => context.go('/pages/${page.shortId}'),
                trailing: const Icon(Icons.chevron_right),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New page',
        onPressed: _createPage,
        child: const Icon(Icons.add),
      ),
    );
  }
}
