import 'dart:convert';
import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../services/auth_service.dart';

class HomeScreen extends StatelessWidget {
  final ApiClient api;
  final AuthService auth;

  const HomeScreen({super.key, required this.api, required this.auth});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 240,
            child: _Sidebar(auth: auth),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _VaultList(api: api),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final AuthService auth;

  const _Sidebar({required this.auth});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _VaultNav(auth: auth),
        ),
        const Divider(height: 1),
        _SidebarFooter(auth: auth),
      ],
    );
  }
}

class _VaultNav extends StatelessWidget {
  final AuthService auth;

  const _VaultNav({required this.auth});

  @override
  Widget build(BuildContext context) {
    // Vault list is loaded by _VaultList; the nav here shows the section headers.
    // The actual vault items are populated once _VaultList fetches them.
    return _VaultSidebarContent(auth: auth);
  }
}

class _VaultSidebarContent extends StatefulWidget {
  final AuthService auth;

  const _VaultSidebarContent({required this.auth});

  @override
  State<_VaultSidebarContent> createState() => _VaultSidebarContentState();
}

class _VaultSidebarContentState extends State<_VaultSidebarContent> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _SectionHeader('My Space'),
        // Personal vault entry — populated by the parent FutureBuilder via
        // InheritedWidget in a full implementation. For the bare minimum,
        // show a placeholder that resolves once data loads.
        _PlaceholderVaultTile('Personal Vault'),
        const SizedBox(height: 8),
        _SectionHeader('Shared'),
        _PlaceholderVaultTile('No shared vaults yet'),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

class _PlaceholderVaultTile extends StatelessWidget {
  final String label;

  const _PlaceholderVaultTile(this.label);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  final AuthService auth;

  const _SidebarFooter({required this.auth});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.account_circle_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              // Display name is not yet available from AuthService in this bare
              // minimum; show a placeholder. A later iteration adds GET /api/haven/users/me.
              'Account',
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, size: 18),
            tooltip: 'Sign out',
            onPressed: () => auth.logout(),
          ),
        ],
      ),
    );
  }
}

class _VaultList extends StatefulWidget {
  final ApiClient api;

  const _VaultList({required this.api});

  @override
  State<_VaultList> createState() => _VaultListState();
}

class _VaultListState extends State<_VaultList> {
  late final Future<List<_Vault>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadVaults();
  }

  Future<List<_Vault>> _loadVaults() async {
    final resp = await widget.api.get('/api/luma/vaults');
    if (resp.statusCode != 200) {
      throw Exception('Failed to load vaults (${resp.statusCode})');
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    final items = (data['vaults'] as List<dynamic>? ?? []);
    return items
        .map((e) => _Vault.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_Vault>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Text(
              'Could not load vaults: ${snap.error}',
              style:
                  TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
        }
        final vaults = snap.data ?? [];
        if (vaults.isEmpty) {
          return const Center(
            child: Text('Select a vault to get started.'),
          );
        }
        return const Center(
          child: Text('Select a vault to get started.'),
        );
      },
    );
  }
}

class _Vault {
  final String id;
  final String name;
  final String type;

  const _Vault({required this.id, required this.name, required this.type});

  factory _Vault.fromJson(Map<String, dynamic> json) {
    return _Vault(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
    );
  }
}
