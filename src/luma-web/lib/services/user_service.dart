import 'dart:convert';
import 'package:flutter/foundation.dart';

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
    if (resp.statusCode != 200) {
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
