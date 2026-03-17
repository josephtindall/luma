import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_client.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class VaultSummary {
  final String id;
  final String slug;
  final String name;
  final String type;

  const VaultSummary({
    required this.id,
    required this.slug,
    required this.name,
    required this.type,
  });

  factory VaultSummary.fromJson(Map<String, dynamic> j) => VaultSummary(
        id: j['id'] as String? ?? '',
        slug: j['slug'] as String? ?? '',
        name: j['name'] as String? ?? '',
        type: j['type'] as String? ?? '',
      );
}

class PageSummary {
  final String id;
  final String shortId;
  final String vaultId;
  final String title;
  final bool isArchived;

  const PageSummary({
    required this.id,
    required this.shortId,
    required this.vaultId,
    required this.title,
    required this.isArchived,
  });

  factory PageSummary.fromJson(Map<String, dynamic> j) => PageSummary(
        id: j['id'] as String? ?? '',
        shortId: j['short_id'] as String? ?? '',
        vaultId: j['vault_id'] as String? ?? '',
        title: j['title'] as String? ?? 'Untitled',
        isArchived: j['is_archived'] as bool? ?? false,
      );
}

class PageDetail {
  final String id;
  final String shortId;
  final String vaultId;
  final String title;
  final Map<String, dynamic> content;
  final bool isArchived;

  const PageDetail({
    required this.id,
    required this.shortId,
    required this.vaultId,
    required this.title,
    required this.content,
    required this.isArchived,
  });

  factory PageDetail.fromJson(Map<String, dynamic> j) => PageDetail(
        id: j['id'] as String? ?? '',
        shortId: j['short_id'] as String? ?? '',
        vaultId: j['vault_id'] as String? ?? '',
        title: j['title'] as String? ?? 'Untitled',
        content: j['content'] as Map<String, dynamic>? ?? const {},
        isArchived: j['is_archived'] as bool? ?? false,
      );
}

// ── PageService ───────────────────────────────────────────────────────────────

class PageService extends ChangeNotifier {
  final ApiClient _api;

  List<VaultSummary> vaults = [];
  final Map<String, List<PageSummary>> pagesByVault = {};
  bool isLoadingVaults = false;

  PageService(this._api);

  // Loads all vaults the current user is a member of.
  // The Go handler returns a bare JSON array (not wrapped in an object).
  Future<void> loadVaults() async {
    isLoadingVaults = true;
    notifyListeners();
    try {
      final resp = await _api.get('/api/luma/vaults');
      if (resp.statusCode != 200) return;
      final decoded = json.decode(resp.body);
      List<dynamic> items;
      if (decoded is List) {
        items = decoded;
      } else if (decoded is Map) {
        // Defensive: handle both bare array and potential {"vaults":[...]} wrapper.
        items = (decoded['vaults'] as List<dynamic>?) ??
            (decoded.values.firstWhere((v) => v is List, orElse: () => <dynamic>[]) as List);
      } else {
        items = [];
      }
      vaults = items
          .whereType<Map<String, dynamic>>()
          .map(VaultSummary.fromJson)
          .toList();
    } finally {
      isLoadingVaults = false;
      notifyListeners();
    }
  }

  // Loads pages for a vault. No-op if already loaded; call refreshPagesForVault
  // to force a reload.
  Future<void> loadPagesForVault(String vaultId) async {
    if (pagesByVault.containsKey(vaultId)) return;
    await _fetchPages(vaultId);
  }

  Future<void> refreshPagesForVault(String vaultId) => _fetchPages(vaultId);

  Future<void> _fetchPages(String vaultId) async {
    final resp = await _api.get('/api/luma/pages?vault_id=$vaultId');
    if (resp.statusCode != 200) return;
    final decoded = json.decode(resp.body);
    List<dynamic> items;
    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map) {
      items = (decoded['pages'] as List<dynamic>?) ?? [];
    } else {
      items = [];
    }
    pagesByVault[vaultId] = items
        .whereType<Map<String, dynamic>>()
        .where((m) => m['is_archived'] != true)
        .map(PageSummary.fromJson)
        .toList();
    notifyListeners();
  }

  Future<PageDetail> getPage(String shortId) async {
    final resp = await _api.get('/api/luma/pages/$shortId');
    if (resp.statusCode != 200) {
      throw Exception('Failed to load page ($shortId): ${resp.statusCode}');
    }
    return PageDetail.fromJson(json.decode(resp.body) as Map<String, dynamic>);
  }

  // Creates a new page in the given vault, updates the local cache, and returns the detail.
  Future<PageDetail> createPage(String vaultId) async {
    final resp = await _api.post(
      '/api/luma/pages',
      {'vault_id': vaultId, 'title': 'Untitled'},
    );
    if (resp.statusCode != 201) {
      throw Exception('Failed to create page: ${resp.statusCode}');
    }
    final page = PageDetail.fromJson(json.decode(resp.body) as Map<String, dynamic>);
    // Insert at front of the vault's page list.
    final list = pagesByVault.putIfAbsent(vaultId, () => []);
    list.insert(
      0,
      PageSummary(
        id: page.id,
        shortId: page.shortId,
        vaultId: page.vaultId,
        title: page.title,
        isArchived: page.isArchived,
      ),
    );
    notifyListeners();
    return page;
  }

  Future<VaultSummary> createVault(String name) async {
    final resp = await _api.post('/api/luma/vaults', {'name': name});
    if (resp.statusCode != 201) {
      throw Exception('Failed to create vault: ${resp.statusCode}');
    }
    final vault = VaultSummary.fromJson(
      json.decode(resp.body) as Map<String, dynamic>,
    );
    vaults = [vault, ...vaults];
    notifyListeners();
    return vault;
  }

  Future<void> savePage(
    String shortId, {
    required String title,
    required Map<String, dynamic> content,
  }) async {
    final resp = await _api.put(
      '/api/luma/pages/$shortId',
      {'title': title, 'content': content},
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to save page: ${resp.statusCode}');
    }
    // Update the title in the local page summaries.
    for (final list in pagesByVault.values) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].shortId == shortId) {
          list[i] = PageSummary(
            id: list[i].id,
            shortId: list[i].shortId,
            vaultId: list[i].vaultId,
            title: title,
            isArchived: list[i].isArchived,
          );
          notifyListeners();
          return;
        }
      }
    }
  }

  void clear() {
    vaults = [];
    pagesByVault.clear();
    notifyListeners();
  }
}
