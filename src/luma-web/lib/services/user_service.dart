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

  UserService(this._api);

  UserProfile? get profile => _profile;
  UserPreferences? get preferences => _preferences;

  Future<void> loadProfile() async {
    final resp = await _api.get('/api/luma/user/me');
    if (resp.statusCode == 200) {
      _profile = UserProfile.fromJson(_unwrapUser(json.decode(resp.body)));
      notifyListeners();
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

  Future<List<AuditEvent>> loadAudit() async {
    final resp = await _api.get('/api/luma/user/me/audit');
    if (resp.statusCode != 200) {
      throw Exception('Failed to load audit log');
    }
    final data = json.decode(resp.body);
    final items = _unwrapList(data, ['events', 'audit', 'data']);
    return items
        .map((e) => AuditEvent.fromJson(e as Map<String, dynamic>))
        .toList();
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
    return InstanceSettings.fromJson(
        json.decode(resp.body) as Map<String, dynamic>);
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

  Future<GroupRecord> createGroup(String name) async {
    final resp = await _api.post('/api/luma/admin/groups', {'name': name});
    if (resp.statusCode != 201) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['message'] ?? 'Failed to create group');
    }
    return GroupRecord.fromJson(json.decode(resp.body) as Map<String, dynamic>);
  }

  Future<GroupRecord> renameGroup(String id, String name) async {
    final resp = await _api.patch('/api/luma/admin/groups/$id', {'name': name});
    if (resp.statusCode != 200) {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(body['message'] ?? 'Failed to rename group');
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

  Future<CustomRoleRecord> createCustomRole(String name, {int? priority}) async {
    final body = <String, dynamic>{'name': name};
    if (priority != null) body['priority'] = priority;
    final resp = await _api.post('/api/luma/admin/custom-roles', body);
    if (resp.statusCode != 201) {
      final b = json.decode(resp.body) as Map<String, dynamic>;
      throw Exception(b['message'] ?? 'Failed to create role');
    }
    return CustomRoleRecord.fromJson(
        json.decode(resp.body) as Map<String, dynamic>);
  }

  Future<CustomRoleRecord> updateCustomRole(String id, String name,
      {int? priority, bool clearPriority = false}) async {
    final body = <String, dynamic>{'name': name};
    if (clearPriority) {
      body['priority'] = null;
    } else if (priority != null) {
      body['priority'] = priority;
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
