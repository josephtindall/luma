import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../models/custom_role.dart';
import '../models/group.dart';
import '../models/instance_settings.dart';
import '../models/user.dart';
import 'api_client.dart';

class UserService extends ChangeNotifier {
  final ApiClient _api;

  UserProfile? _profile;
  UserPreferences? _preferences;
  bool _hasAdminAccess = false;
  Map<String, bool> _adminCaps = {};
  String _contentWidth = 'wide';
  bool _showGithubButton = true;
  bool _showDonateButton = true;

  UserService(this._api);

  UserProfile? get profile => _profile;
  UserPreferences? get preferences => _preferences;
  bool get hasAdminAccess => _hasAdminAccess;
  String get contentWidth => _contentWidth;
  bool get showGithubButton => _showGithubButton;
  bool get showDonateButton => _showDonateButton;

  // Fine-grained admin tab visibility — populated by _loadAdminCapabilities().
  bool get canManageUsers => _adminCaps['user:read'] == true;
  bool get canManageInvitations => _adminCaps['invitation:list'] == true;
  bool get canManageInstanceSettings => _adminCaps['instance:read'] == true;
  bool get canManageGroups => _adminCaps['group:read'] == true;
  bool get canManageRoles => _adminCaps['role:read'] == true;
  bool get isAdminOwner => _adminCaps['is_owner'] == true;
  bool get canViewAuditLog => _adminCaps['audit:read-all'] == true;
  bool get canExportAuditLog => _adminCaps['audit:export-all'] == true;
  bool get hasAnyAdminAccess => _adminCaps.isNotEmpty;

  Future<void> loadProfile() async {
    final resp = await _api.get('/api/luma/user/me');
    if (resp.statusCode == 200) {
      _profile = UserProfile.fromJson(_unwrapUser(json.decode(resp.body)));
      await Future.wait([_loadAdminCapabilities(), _loadPublicSettings()]);
      notifyListeners();
    }
  }

  Future<void> _loadPublicSettings() async {
    try {
      final resp = await _api.get('/api/luma/instance/ui');
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        _contentWidth = data['content_width'] as String? ?? 'wide';
        _showGithubButton = data['show_github_button'] as bool? ?? true;
        _showDonateButton = data['show_donate_button'] as bool? ?? true;
      }
    } catch (_) {
      _contentWidth = 'wide';
      _showGithubButton = true;
      _showDonateButton = true;
    }
  }

  Future<void> _loadAdminCapabilities() async {
    if (_profile == null) {
      _hasAdminAccess = false;
      _adminCaps = {};
      return;
    }
    try {
      final resp = await _api.get('/api/luma/admin/capabilities');
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        _adminCaps = data.map((k, v) => MapEntry(k, v == true));
        _hasAdminAccess = _adminCaps.values.any((v) => v);
      } else {
        _adminCaps = {};
        _hasAdminAccess = false;
      }
    } catch (_) {
      _adminCaps = {};
      _hasAdminAccess = false;
    }
  }

  Future<void> updateProfile({
    required String displayName,
    required String email,
  }) async {
    final resp = await _api.put('/api/luma/user/me/profile', {
      'display_name': displayName,
      'email': email,
    });
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to update profile');
    }
    // Reload profile to ensure we have the latest data, in case the
    // update response doesn't include the full user object.
    await loadProfile();
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final resp = await _api.post('/api/luma/user/me/password', {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to change password');
    }
  }

  Future<void> loadPreferences() async {
    final resp = await _api.get('/api/luma/user/me/preferences');
    if (resp.statusCode == 200) {
      _preferences = UserPreferences.fromJson(
        _unwrapPreferences(json.decode(resp.body)),
      );
      notifyListeners();
    }
  }

  Future<void> updatePreferences({
    String? theme,
    String? timezone,
    String? dateFormat,
    String? timeFormat,
    String? language,
    bool? compactMode,
    bool? notifyOnLogin,
    bool? notifyOnRevoke,
  }) async {
    final body = <String, dynamic>{};
    if (theme != null) body['theme'] = theme;
    if (timezone != null) body['timezone'] = timezone;
    if (dateFormat != null) body['date_format'] = dateFormat;
    if (timeFormat != null) body['time_format'] = timeFormat;
    if (language != null) body['language'] = language;
    if (compactMode != null) body['compact_mode'] = compactMode;
    if (notifyOnLogin != null) body['notify_on_login'] = notifyOnLogin;
    if (notifyOnRevoke != null) body['notify_on_revoke'] = notifyOnRevoke;

    final resp = await _api.patch('/api/luma/user/me/preferences', body);
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      final respBody = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(respBody['error'] ?? 'Failed to update preferences');
    }
    // Reload preferences to get the confirmed server state.
    await loadPreferences();
  }

  Future<List<Device>> loadDevices() async {
    final resp = await _api.get('/api/luma/user/me/devices');
    if (resp.statusCode != 200) {
      throw Exception('Failed to load devices');
    }
    final data = json.decode(resp.body);
    final items = _unwrapList(data, ['devices', 'data']);
    return items
        .map((e) => Device.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> revokeDevice(String deviceId) async {
    final resp = await _api.delete('/api/luma/user/me/devices/$deviceId');
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw Exception('Failed to revoke device');
    }
  }

  Future<AuditPage> loadAudit({
    int limit = 10,
    int offset = 0,
    String? search,
    String? eventFilter,
    String exclude = 'token_refreshed',
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      if (search != null && search.isNotEmpty) 'search': search,
      if (eventFilter != null && eventFilter.isNotEmpty) 'event': eventFilter,
      if (exclude.isNotEmpty) 'exclude': exclude,
    };
    final uri = Uri.parse('/api/luma/user/me/audit')
        .replace(queryParameters: params)
        .toString();
    final resp = await _api.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('Failed to load audit log');
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    return AuditPage.fromJson(data);
  }

  Future<AuditPage> loadAdminAudit({
    int limit = 30,
    int offset = 0,
    String? search,
    String? eventFilter,
    DateTime? after,
    DateTime? before,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      if (search != null && search.isNotEmpty) 'search': search,
      if (eventFilter != null && eventFilter.isNotEmpty) 'event': eventFilter,
      if (after != null) 'after': after.toUtc().toIso8601String(),
      if (before != null) 'before': before.toUtc().toIso8601String(),
    };
    final uri = Uri.parse('/api/luma/admin/events')
        .replace(queryParameters: params)
        .toString();
    final resp = await _api.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('Failed to load audit log');
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    return AuditPage.fromJson(data);
  }

  // ── TOTP management ─────────────────────────────────────────────────────

  /// Lists all enrolled TOTP authenticator apps.
  Future<List<TOTPApp>> loadTOTPApps() async {
    final resp = await _api.get('/api/luma/user/me/mfa/totp');
    if (resp.statusCode != 200) {
      throw Exception('Failed to load authenticator apps');
    }
    final data = json.decode(resp.body);
    final items = _unwrapList(data, ['totp', 'data']);
    return items
        .map((e) => TOTPApp.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Starts TOTP enrollment. Returns {id, secret, otpauth_uri}.
  Future<Map<String, String>> setupTOTP(String name) async {
    final resp = await _api.post('/api/luma/user/me/mfa/totp/setup', {
      'name': name,
    });
    if (resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to set up TOTP');
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    return {
      'id': data['id'] as String? ?? '',
      'secret': data['secret'] as String? ?? '',
      'otpauth_uri': data['otpauth_uri'] as String? ?? '',
    };
  }

  /// Confirms TOTP setup with the secret ID and a verification code.
  Future<void> confirmTOTP(String id, String code) async {
    final resp = await _api.post('/api/luma/user/me/mfa/totp/confirm', {
      'id': id,
      'code': code,
    });
    if (resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Invalid code');
    }
    await loadProfile();
  }

  // ── Recovery Codes ──────────────────────────────────────────────────────

  /// Generates a new batch of recovery codes, invalidating any existing ones.
  Future<List<String>> generateRecoveryCodes() async {
    final resp = await _api.post('/api/luma/user/me/mfa/recovery-codes', {});
    if (resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to generate recovery codes');
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    final codes = data['codes'] as List<dynamic>? ?? [];
    return codes.map((c) => c.toString()).toList();
  }

  /// Returns the number of unused recovery codes remaining.
  Future<int> getRecoveryCodesCount() async {
    final resp = await _api.get('/api/luma/user/me/mfa/recovery-codes/count');
    if (resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to load recovery codes count');
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    return data['count'] as int? ?? 0;
  }

  /// Removes a specific TOTP app. Requires password confirmation.
  Future<void> removeTOTPApp(String id, String password) async {
    final resp = await _api.deleteWithBody('/api/luma/user/me/mfa/totp/$id', {
      'password': password,
    });
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to remove authenticator app');
    }
    await loadProfile();
  }

  // ── Passkey management ─────────────────────────────────────────────────

  Future<List<Passkey>> loadPasskeys() async {
    final resp = await _api.get('/api/luma/user/me/passkeys');
    if (resp.statusCode != 200) {
      throw Exception('Failed to load passkeys');
    }
    final data = json.decode(resp.body);
    final items = _unwrapList(data, ['passkeys', 'data']);
    return items
        .map((e) => Passkey.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> revokePasskey(String passkeyId, String password) async {
    final resp =
        await _api.deleteWithBody('/api/luma/user/me/passkeys/$passkeyId', {
      'password': password,
    });
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to revoke passkey');
    }
    await loadProfile();
  }

  /// Begins passkey registration. Returns the PublicKeyCredentialCreationOptions
  /// JSON to pass to navigator.credentials.create().
  Future<Map<String, dynamic>> beginPasskeyRegistration(String name) async {
    final resp = await _api.post('/api/luma/user/me/passkeys/register/begin', {
      'name': name,
    });
    if (resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to begin passkey registration');
    }
    return json.decode(resp.body) as Map<String, dynamic>;
  }

  /// Completes passkey registration with the browser's credential response.
  Future<void> finishPasskeyRegistration(
      Map<String, dynamic> credential) async {
    final resp = await _api.post(
      '/api/luma/user/me/passkeys/register/finish',
      credential,
    );
    if (resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(
          body['error'] ?? 'Failed to complete passkey registration');
    }
    await loadProfile(); // refresh mfaEnabled state
  }

  // ── Admin: instance settings (owner only) ──────────────────────────────

  Future<InstanceSettings> getInstanceSettings() async {
    final resp = await _api.get('/api/luma/admin/instance-settings');
    if (resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to load instance settings');
    }
    return InstanceSettings.fromJson(
        json.decode(resp.body) as Map<String, dynamic>);
  }

  Future<InstanceSettings> updateInstanceSettings(
      InstanceSettings settings) async {
    final resp = await _api.patch(
        '/api/luma/admin/instance-settings', settings.toJson());
    if (resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to update instance settings');
    }
    final updated =
        InstanceSettings.fromJson(json.decode(resp.body) as Map<String, dynamic>);
    _contentWidth = updated.contentWidth;
    _showGithubButton = updated.showGithubButton;
    _showDonateButton = updated.showDonateButton;
    notifyListeners();
    return updated;
  }

  // ── Admin: user management (owner only) ────────────────────────────────

  Future<List<AdminUserRecord>> listAdminUsers() async {
    final resp = await _api.get('/api/luma/admin/users');
    if (resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to load users');
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    final items = (data['users'] as List<dynamic>? ?? []);
    return items
        .map((e) => AdminUserRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> lockUser(String userId) async {
    final resp = await _api.post('/api/luma/admin/users/$userId/lock', {});
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to lock user');
    }
  }

  Future<void> unlockUser(String userId) async {
    final resp = await _api.delete('/api/luma/admin/users/$userId/lock');
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to unlock user');
    }
  }

  Future<void> revokeUserSessions(String userId) async {
    final resp = await _api.delete('/api/luma/admin/users/$userId/sessions');
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to revoke sessions');
    }
  }

  /// Creates a new user directly (without invitation).
  Future<AdminUserRecord> adminCreateUser({
    required String email,
    required String displayName,
    required String password,
    required bool forcePasswordChange,
  }) async {
    final resp = await _api.post('/api/luma/admin/users', {
      'email': email,
      'display_name': displayName,
      'password': password,
      'force_password_change': forcePasswordChange,
    });
    if (resp.statusCode != 201) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to create user');
    }
    return AdminUserRecord.fromJson(
        json.decode(resp.body) as Map<String, dynamic>);
  }

  /// Forces the user to change their password on next login.
  Future<void> adminForcePasswordChange(String userId) async {
    final resp = await _api
        .post('/api/luma/admin/users/$userId/force-password-change', {});
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to set force password change');
    }
  }

  /// Creates a one-time password reset link for a user (admin-generated).
  Future<PasswordResetLinkResult> adminCreatePasswordResetLink(
      String userId) async {
    final resp =
        await _api.post('/api/luma/admin/users/$userId/password-reset', {});
    if (resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to create password reset link');
    }
    return PasswordResetLinkResult.fromJson(
        json.decode(resp.body) as Map<String, dynamic>);
  }

  /// Removes all TOTP authenticator apps for a user.
  Future<void> adminDeleteAllTOTP(String userId) async {
    final resp = await _api.delete('/api/luma/admin/users/$userId/mfa/totp');
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to remove authenticator apps');
    }
  }

  /// Revokes all passkeys for a user.
  Future<void> adminRevokeAllPasskeys(String userId) async {
    final resp = await _api.delete('/api/luma/admin/users/$userId/passkeys');
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to revoke passkeys');
    }
  }

  /// Returns all invitations (all statuses) for the owner's admin view.
  Future<List<InvitationRecord>> listInvitations() async {
    final resp = await _api.get('/api/luma/admin/invitations');
    if (resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to load invitations');
    }
    final data = json.decode(resp.body);
    final List<dynamic> items;
    if (data is List) {
      items = data;
    } else if (data is Map<String, dynamic>) {
      items = _unwrapList(data, ['invitations', 'data']);
    } else {
      items = [];
    }
    return items
        .map((e) => InvitationRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Revokes a pending invitation by ID.
  Future<void> revokeInvitation(String id) async {
    final resp = await _api.delete('/api/luma/admin/invitations/$id');
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to revoke invitation');
    }
  }

  /// Creates an invitation for [email] and returns the result including
  /// the raw token (extracted from the auth service's join_url).
  Future<InvitationCreateResult> createInvitation(String email) async {
    final resp = await _api.post('/api/luma/admin/invitations', {
      'email': email,
    });
    if (resp.statusCode != 201) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to create invitation');
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    // The auth service embeds the raw token in join_url.
    // We extract it and let the Flutter client build the correct Luma URL.
    final rawJoinUrl = data['join_url'] as String? ?? '';
    final token = Uri.tryParse(rawJoinUrl)?.queryParameters['token'] ?? '';
    return InvitationCreateResult(
      id: data['id'] as String? ?? '',
      token: token,
      expiresAt: DateTime.tryParse(data['expires_at'] as String? ?? '') ??
          DateTime.now().add(const Duration(days: 7)),
    );
  }

  // ── Admin: groups ────────────────────────────────────────────────────────

  Future<List<GroupRecord>> listGroups() async {
    final resp = await _api.get('/api/luma/admin/groups');
    if (resp.statusCode != 200) {
      throw Exception('Failed to load groups');
    }
    final data = json.decode(resp.body);
    final items = data is List ? data : (data as Map<String, dynamic>)['groups'] ?? data;
    return (items as List<dynamic>)
        .map((e) => GroupRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<GroupRecord> getGroup(String id) async {
    final resp = await _api.get('/api/luma/admin/groups/$id');
    if (resp.statusCode != 200) throw Exception('Failed to load group');
    return GroupRecord.fromJson(json.decode(resp.body) as Map<String, dynamic>);
  }

  Future<GroupRecord> createGroup(String name, {String? description}) async {
    final body = <String, dynamic>{'name': name};
    if (description != null && description.isNotEmpty) body['description'] = description;
    final resp = await _api.post('/api/luma/admin/groups', body);
    if (resp.statusCode != 201) {
      final b = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(b['message'] ?? 'Failed to create group');
    }
    return GroupRecord.fromJson(json.decode(resp.body) as Map<String, dynamic>);
  }

  Future<GroupRecord> renameGroup(String id, String name, {String? description, bool clearDescription = false}) async {
    final body = <String, dynamic>{'name': name};
    if (clearDescription) {
      body['description'] = null;
    } else if (description != null && description.isNotEmpty) {
      body['description'] = description;
    }
    final resp = await _api.patch('/api/luma/admin/groups/$id', body);
    if (resp.statusCode != 200) {
      final b = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(b['message'] ?? 'Failed to rename group');
    }
    return GroupRecord.fromJson(json.decode(resp.body) as Map<String, dynamic>);
  }

  Future<void> deleteGroup(String id) async {
    final resp = await _api.delete('/api/luma/admin/groups/$id');
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['message'] ?? 'Failed to delete group');
    }
  }

  Future<void> addGroupMember(
      String groupId, String memberType, String memberId) async {
    final resp = await _api.post('/api/luma/admin/groups/$groupId/members', {
      'member_type': memberType,
      'member_id': memberId,
    });
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['message'] ?? 'Failed to add member');
    }
  }

  Future<void> removeGroupMember(
      String groupId, String memberType, String memberId) async {
    final resp = await _api
        .delete('/api/luma/admin/groups/$groupId/members/$memberType/$memberId');
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['message'] ?? 'Failed to remove member');
    }
  }

  Future<void> assignRoleToGroup(String groupId, String roleId) async {
    final resp = await _api
        .post('/api/luma/admin/groups/$groupId/roles/$roleId', {});
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['message'] ?? 'Failed to assign role');
    }
  }

  Future<void> removeRoleFromGroup(String groupId, String roleId) async {
    final resp =
        await _api.delete('/api/luma/admin/groups/$groupId/roles/$roleId');
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['message'] ?? 'Failed to remove role');
    }
  }

  // ── Admin: custom roles ──────────────────────────────────────────────────

  Future<List<CustomRoleRecord>> listCustomRoles() async {
    final resp = await _api.get('/api/luma/admin/custom-roles');
    if (resp.statusCode != 200) throw Exception('Failed to load custom roles');
    final data = json.decode(resp.body);
    final items =
        data is List ? data : (data as Map<String, dynamic>)['roles'] ?? data;
    return (items as List<dynamic>)
        .map((e) => CustomRoleRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CustomRoleRecord> getCustomRole(String id) async {
    final resp = await _api.get('/api/luma/admin/custom-roles/$id');
    if (resp.statusCode != 200) throw Exception('Failed to load custom role');
    return CustomRoleRecord.fromJson(
        json.decode(resp.body) as Map<String, dynamic>);
  }

  Future<CustomRoleRecord> createCustomRole(String name, {int? priority, String? description}) async {
    final body = <String, dynamic>{'name': name};
    if (priority != null) body['priority'] = priority;
    if (description != null && description.isNotEmpty) body['description'] = description;
    final resp = await _api.post('/api/luma/admin/custom-roles', body);
    if (resp.statusCode != 201) {
      final b = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(b['message'] ?? 'Failed to create role');
    }
    return CustomRoleRecord.fromJson(
        json.decode(resp.body) as Map<String, dynamic>);
  }

  Future<CustomRoleRecord> updateCustomRole(String id, String name,
      {int? priority, bool clearPriority = false, String? description, bool clearDescription = false}) async {
    final body = <String, dynamic>{'name': name};
    if (clearPriority) {
      body['priority'] = null;
    } else if (priority != null) {
      body['priority'] = priority;
    }
    if (clearDescription) {
      body['description'] = null;
    } else if (description != null && description.isNotEmpty) {
      body['description'] = description;
    }
    final resp = await _api.patch('/api/luma/admin/custom-roles/$id', body);
    if (resp.statusCode != 200) {
      final b = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(b['message'] ?? 'Failed to update role');
    }
    return CustomRoleRecord.fromJson(
        json.decode(resp.body) as Map<String, dynamic>);
  }

  Future<void> deleteCustomRole(String id) async {
    final resp = await _api.delete('/api/luma/admin/custom-roles/$id');
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['message'] ?? 'Failed to delete role');
    }
  }

  Future<void> setCustomRolePermission(
      String roleId, String action, String effect) async {
    final resp = await _api.put(
      '/api/luma/admin/custom-roles/$roleId/permissions/$action',
      {'effect': effect},
    );
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['message'] ?? 'Failed to set permission');
    }
  }

  Future<void> removeCustomRolePermission(String roleId, String action) async {
    final resp = await _api
        .delete('/api/luma/admin/custom-roles/$roleId/permissions/$action');
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['message'] ?? 'Failed to remove permission');
    }
  }

  // ── Admin: user custom role assignments ──────────────────────────────────

  Future<List<CustomRoleRecord>> getUserCustomRoles(String userId) async {
    final resp =
        await _api.get('/api/luma/admin/users/$userId/custom-roles');
    if (resp.statusCode != 200) throw Exception('Failed to load user roles');
    final data = json.decode(resp.body);
    final List<dynamic> items = data is List<dynamic> ? data : [];
    return items
        .map((e) => CustomRoleRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> assignCustomRoleToUser(String userId, String roleId) async {
    final resp = await _api
        .post('/api/luma/admin/users/$userId/custom-roles/$roleId', {});
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['message'] ?? 'Failed to assign role');
    }
  }

  Future<void> removeCustomRoleFromUser(String userId, String roleId) async {
    final resp = await _api
        .delete('/api/luma/admin/users/$userId/custom-roles/$roleId');
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['message'] ?? 'Failed to remove role');
    }
  }

  void clear() {
    _profile = null;
    _preferences = null;
    _hasAdminAccess = false;
    _adminCaps = {};
    _contentWidth = 'wide';
    _showGithubButton = true;
    _showDonateButton = true;
    notifyListeners();
  }

  /// Unwrap a user response — could be flat `{id, email, ...}` or
  /// wrapped in `{user: {id, email, ...}}`.
  static Map<String, dynamic> _unwrapUser(dynamic data) {
    if (data is Map<String, dynamic>) {
      if (data.containsKey('user') && data['user'] is Map<String, dynamic>) {
        return data['user'] as Map<String, dynamic>;
      }
      return data;
    }
    return {};
  }

  /// Unwrap a preferences response — could be flat or wrapped.
  static Map<String, dynamic> _unwrapPreferences(dynamic data) {
    if (data is Map<String, dynamic>) {
      if (data.containsKey('preferences') &&
          data['preferences'] is Map<String, dynamic>) {
        return data['preferences'] as Map<String, dynamic>;
      }
      return data;
    }
    return {};
  }

  // ---------------------------------------------------------------------------
  // Account recovery token
  // ---------------------------------------------------------------------------

  /// Returns whether the current user has a recovery token stored.
  Future<bool> getRecoveryTokenStatus() async {
    final resp = await _api.get('/api/luma/auth/recovery/status');
    if (resp.statusCode != 200) throw Exception('Failed to get recovery token status');
    final data = json.decode(resp.body) as Map<String, dynamic>;
    return data['has_token'] as bool? ?? false;
  }

  /// Generates (or regenerates) a recovery token for the current user.
  /// [currentPassword] is required only when a token already exists.
  /// Returns the raw 64-digit recovery token.
  Future<String> generateRecoveryToken({String? currentPassword}) async {
    final body = <String, dynamic>{};
    if (currentPassword != null && currentPassword.isNotEmpty) {
      body['current_password'] = currentPassword;
    }
    final resp = await _api.post('/api/luma/auth/recovery/generate', body);
    if (resp.statusCode != 200) {
      final data = json.decode(resp.body) as Map<String, dynamic>?;
      throw Exception(data?['message'] ?? data?['error'] ?? 'Failed to generate recovery token');
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    return data['token'] as String;
  }

  /// Extract a list from a response that might be a bare array or an object
  /// with the list under one of the given keys.
  static List<dynamic> _unwrapList(dynamic data, List<String> keys) {
    if (data is List) return data;
    if (data is Map<String, dynamic>) {
      for (final key in keys) {
        if (data.containsKey(key) && data[key] is List) {
          return data[key] as List;
        }
      }
    }
    return [];
  }
}
