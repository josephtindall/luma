import 'dart:convert';
import 'package:flutter/material.dart';

import '../../services/api_client.dart';

class HomeScreen extends StatelessWidget {
  final ApiClient api;

  const HomeScreen({
    super.key,
    required this.api,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _VaultList(api: api),
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
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
        }
        final vaults = snap.data ?? [];
        if (vaults.isEmpty) {
          return const Center(
            child: Text('Select a vault to get started.'),
          );
        }
        return ListView.builder(
          itemCount: vaults.length,
          itemBuilder: (context, i) {
            final v = vaults[i];
            return ListTile(
              title: Text(v.name),
              subtitle: Text(v.type),
              onTap: () {
                // TODO(phase2): navigate into vault
              },
            );
          },
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
