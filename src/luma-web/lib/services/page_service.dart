import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_client.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class VaultSummary {
  final String id;
  final String slug;
  final String name;
  final String type;
  final bool isPrivate;

  const VaultSummary({
    required this.id,
    required this.slug,
    required this.name,
    required this.type,
    this.isPrivate = true,
  });

  factory VaultSummary.fromJson(Map<String, dynamic> j) => VaultSummary(
        id: j['id'] as String? ?? '',
        slug: j['slug'] as String? ?? '',
        name: j['name'] as String? ?? '',
        type: j['type'] as String? ?? '',
        isPrivate: j['is_private'] as bool? ?? true,
      );
}

class UserSearchResult {
  final String id;
  final String email;
  final String displayName;

  const UserSearchResult({
    required this.id,
    required this.email,
    required this.displayName,
  });

  factory UserSearchResult.fromJson(Map<String, dynamic> j) => UserSearchResult(
        id: j['id'] as String? ?? '',
        email: j['email'] as String? ?? '',
        displayName: j['display_name'] as String? ?? '',
      );
}

class GroupSearchResult {
  final String id;
  final String name;

  const GroupSearchResult({required this.id, required this.name});

  factory GroupSearchResult.fromJson(Map<String, dynamic> j) =>
      GroupSearchResult(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
      );
}

class VaultGroupMemberDetail {
  final String vaultId;
  final String groupId;
  final String groupName;
  final String roleId;
  final DateTime addedAt;

  const VaultGroupMemberDetail({
    required this.vaultId,
    required this.groupId,
    required this.groupName,
    required this.roleId,
    required this.addedAt,
  });

  factory VaultGroupMemberDetail.fromJson(Map<String, dynamic> j) =>
      VaultGroupMemberDetail(
        vaultId: j['vault_id'] as String? ?? '',
        groupId: j['group_id'] as String? ?? '',
        groupName: j['group_name'] as String? ?? '',
        roleId: j['role_id'] as String? ?? '',
        addedAt:
            DateTime.tryParse(j['added_at'] as String? ?? '') ?? DateTime.now(),
      );
}

class VaultMemberDetail {
  final String vaultId;
  final String userId;
  final String email;
  final String displayName;
  final String avatarSeed;
  final String roleId;
  final DateTime addedAt;

  const VaultMemberDetail({
    required this.vaultId,
    required this.userId,
    required this.email,
    required this.displayName,
    required this.avatarSeed,
    required this.roleId,
    required this.addedAt,
  });

  factory VaultMemberDetail.fromJson(Map<String, dynamic> j) =>
      VaultMemberDetail(
        vaultId: j['vault_id'] as String? ?? '',
        userId: j['user_id'] as String? ?? '',
        email: j['email'] as String? ?? '',
        displayName: j['display_name'] as String? ?? '',
        avatarSeed: j['avatar_seed'] as String? ?? '',
        roleId: j['role_id'] as String? ?? '',
        addedAt: DateTime.tryParse(j['added_at'] as String? ?? '') ??
            DateTime.now(),
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

  Future<VaultSummary> createVault(String name, {bool isPrivate = true}) async {
    final resp = await _api.post('/api/luma/vaults', {
      'name': name,
      'is_private': isPrivate,
    });
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

  Future<void> updateVault(
    String vaultId, {
    String? name,
    bool? isPrivate,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (isPrivate != null) body['is_private'] = isPrivate;
    final resp = await _api.patch('/api/luma/vaults/$vaultId', body);
    if (resp.statusCode != 200) {
      throw Exception('Failed to update vault: ${resp.statusCode}');
    }
    final updated = VaultSummary.fromJson(
      json.decode(resp.body) as Map<String, dynamic>,
    );
    vaults = vaults.map((v) => v.id == vaultId ? updated : v).toList();
    notifyListeners();
  }

  Future<List<VaultMemberDetail>> listVaultMembers(String vaultId) async {
    final resp = await _api.get('/api/luma/vaults/$vaultId/members');
    if (resp.statusCode != 200) {
      throw Exception('Failed to list members: ${resp.statusCode}');
    }
    final decoded = json.decode(resp.body);
    final items = decoded is List ? decoded : [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(VaultMemberDetail.fromJson)
        .toList();
  }

  Future<void> addVaultMember(
    String vaultId,
    String userId,
    String roleId,
  ) async {
    final resp = await _api.post('/api/luma/vaults/$vaultId/members', {
      'user_id': userId,
      'role_id': roleId,
    });
    if (resp.statusCode != 201) {
      throw Exception('Failed to add member: ${resp.statusCode}');
    }
  }

  Future<void> updateMemberRole(
    String vaultId,
    String userId,
    String roleId,
  ) async {
    final resp = await _api.patch(
      '/api/luma/vaults/$vaultId/members/$userId',
      {'role_id': roleId},
    );
    if (resp.statusCode != 204) {
      throw Exception('Failed to update member role: ${resp.statusCode}');
    }
  }

  Future<void> removeVaultMember(String vaultId, String userId) async {
    final resp = await _api.delete('/api/luma/vaults/$vaultId/members/$userId');
    if (resp.statusCode != 204) {
      throw Exception('Failed to remove member: ${resp.statusCode}');
    }
  }

  Future<void> archiveVault(String vaultId) async {
    final resp = await _api.delete('/api/luma/vaults/$vaultId');
    if (resp.statusCode != 204) {
      throw Exception('Failed to archive vault: ${resp.statusCode}');
    }
    vaults = vaults.where((v) => v.id != vaultId).toList();
    pagesByVault.remove(vaultId);
    notifyListeners();
  }

  Future<List<UserSearchResult>> searchUsers(String query) async {
    final encoded = Uri.encodeQueryComponent(query);
    final resp = await _api.get('/api/luma/users?search=$encoded');
    if (resp.statusCode != 200) return [];
    final data = json.decode(resp.body);
    if (data is! List) return [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(UserSearchResult.fromJson)
        .toList();
  }

  Future<List<GroupSearchResult>> searchGroups(String query) async {
    final encoded = Uri.encodeQueryComponent(query);
    final resp = await _api.get('/api/luma/groups?search=$encoded');
    if (resp.statusCode != 200) return [];
    final data = json.decode(resp.body);
    if (data is! List) return [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(GroupSearchResult.fromJson)
        .toList();
  }

  Future<List<VaultGroupMemberDetail>> listVaultGroupMembers(
      String vaultId) async {
    final resp = await _api.get('/api/luma/vaults/$vaultId/groups');
    if (resp.statusCode != 200) return [];
    final data = json.decode(resp.body);
    if (data is! List) return [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(VaultGroupMemberDetail.fromJson)
        .toList();
  }

  Future<void> addVaultGroupMember(
      String vaultId, String groupId, String roleId) async {
    final resp = await _api.post('/api/luma/vaults/$vaultId/groups', {
      'group_id': groupId,
      'role_id': roleId,
    });
    if (resp.statusCode != 201) {
      throw Exception('Failed to add group member: ${resp.statusCode}');
    }
  }

  Future<void> updateGroupMemberRole(
      String vaultId, String groupId, String roleId) async {
    final resp = await _api.patch(
      '/api/luma/vaults/$vaultId/groups/$groupId',
      {'role_id': roleId},
    );
    if (resp.statusCode != 204) {
      throw Exception('Failed to update group role: ${resp.statusCode}');
    }
  }

  Future<void> removeVaultGroupMember(String vaultId, String groupId) async {
    final resp =
        await _api.delete('/api/luma/vaults/$vaultId/groups/$groupId');
    if (resp.statusCode != 204) {
      throw Exception('Failed to remove group member: ${resp.statusCode}');
    }
  }

  /// Returns permission flags for the current user on the given vault.
  /// Returns all-false map on error so callers can degrade gracefully.
  Future<Map<String, bool>> fetchVaultPermissions(String vaultId) async {
    try {
      final resp =
          await _api.get('/api/luma/vaults/$vaultId/my-permissions');
      if (resp.statusCode != 200) return _noPerms;
      final data = json.decode(resp.body) as Map<String, dynamic>;
      return {
        'can_edit': data['can_edit'] as bool? ?? false,
        'can_archive': data['can_archive'] as bool? ?? false,
        'can_manage_members': data['can_manage_members'] as bool? ?? false,
        'can_manage_roles': data['can_manage_roles'] as bool? ?? false,
      };
    } catch (_) {
      return _noPerms;
    }
  }

  static const _noPerms = {
    'can_edit': false,
    'can_archive': false,
    'can_manage_members': false,
    'can_manage_roles': false,
  };

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
