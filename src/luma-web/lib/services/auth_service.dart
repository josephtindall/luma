import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Manages authentication state for the Luma web app.
///
/// Access token lives in memory only. The refresh cookie (HttpOnly, managed by
/// the browser) re-establishes sessions on reload.
class AuthService extends ChangeNotifier {
  final String _baseUrl;

  String? _accessToken;
  String _setupState = 'unknown'; // "unknown" | "unclaimed" | "active"
  bool _isInitialized = false;

  AuthService(this._baseUrl);

  String? get accessToken => _accessToken;
  bool get isLoggedIn => _accessToken != null;
  String get setupState => _setupState;
  bool get isInitialized => _isInitialized;

  /// Called from main.dart before runApp. Probes Haven state and attempts
  /// silent token refresh if the instance is active.
  Future<void> initialize() async {
    try {
      final resp = await http.get(Uri.parse('$_baseUrl/api/luma/setup/status'));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        _setupState = (data['state'] as String?) ?? 'unknown';
      }
    } catch (_) {
      _setupState = 'unknown';
    }

    if (_setupState == 'active') {
      await _silentRefresh();
    }

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> _silentRefresh() async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/api/luma/auth/refresh'),
      );
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        _accessToken = data['access_token'] as String?;
      }
    } catch (_) {
      _accessToken = null;
    }
  }

  /// Logs in with email + password. Stores the access token on success.
  /// Throws [AuthException] on failure.
  Future<void> login(String email, String password) async {
    final resp = await http.post(
      Uri.parse('$_baseUrl/api/luma/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'email': email,
        'password': password,
        'platform': 'web',
        'device_name': 'Browser',
      }),
    );

    if (resp.statusCode != 200) {
      throw AuthException('Invalid credentials');
    }

    final data = json.decode(resp.body) as Map<String, dynamic>;
    _accessToken = data['access_token'] as String?;
    notifyListeners();
  }

  /// Attempts a silent token refresh. Returns true on success.
  Future<bool> refresh() async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/api/luma/auth/refresh'),
      );
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        _accessToken = data['access_token'] as String?;
        notifyListeners();
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Logs out, clearing the session on the server and in memory.
  Future<void> logout() async {
    try {
      await http.post(Uri.parse('$_baseUrl/api/luma/auth/logout'));
    } catch (_) {}
    _accessToken = null;
    notifyListeners();
  }

  /// Clears the in-memory token without calling the server.
  /// Called by ApiClient after a failed refresh.
  void clearSession() {
    _accessToken = null;
    notifyListeners();
  }
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

class SessionExpiredException implements Exception {
  const SessionExpiredException();
}
