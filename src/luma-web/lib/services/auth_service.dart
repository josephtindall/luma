import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Detects the browser name from the user agent string.
///
/// Check order matters — Brave and Edge include "Chrome" in their UA.
String detectBrowserName() {
  try {
    final nav = globalContext['navigator'] as JSObject?;
    if (nav == null) return 'Browser';
    final ua = (nav['userAgent'] as JSString?)?.toDart ?? '';
    if (ua.contains('Brave')) return 'Brave';
    if (ua.contains('Edg/')) return 'Edge';
    if (ua.contains('Chrome/')) return 'Chrome';
    if (ua.contains('Firefox/')) return 'Firefox';
    if (ua.contains('Safari/')) return 'Safari';
    return 'Browser';
  } catch (_) {
    return 'Browser';
  }
}

/// Manages authentication state for the Luma web app.
///
/// Access token lives in memory only. The refresh cookie (HttpOnly, managed by
/// the browser) re-establishes sessions on reload.
class AuthService extends ChangeNotifier {
  final String _baseUrl;

  String? _accessToken;
  String _setupState = 'unknown'; // "unknown" | "unclaimed" | "active"
  bool _isInitialized = false;

  // MFA challenge state — set when login returns mfa_required.
  String? _mfaToken;
  List<String> _mfaMethods = [];

  AuthService(this._baseUrl);

  String? get accessToken => _accessToken;
  bool get isLoggedIn => _accessToken != null;
  String get setupState => _setupState;
  bool get isInitialized => _isInitialized;

  /// True when login succeeded but a second factor is required.
  bool get mfaPending => _mfaToken != null;
  List<String> get mfaMethods => _mfaMethods;

  /// Called from main.dart before runApp. Probes auth service state and attempts
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

  /// Logs in with email + password. On success, either stores the access token
  /// or sets [mfaPending] if a second factor is required.
  /// Throws [AuthException] on failure.
  Future<void> login(String email, String password) async {
    final resp = await http.post(
      Uri.parse('$_baseUrl/api/luma/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'email': email,
        'password': password,
        'platform': 'web',
        'device_name': detectBrowserName(),
      }),
    );

    if (resp.statusCode != 200) {
      throw AuthException('Invalid credentials');
    }

    final data = json.decode(resp.body) as Map<String, dynamic>;

    // MFA required — store the challenge token for the verification screen.
    if (data['mfa_required'] == true) {
      _mfaToken = data['mfa_token'] as String?;
      final methods = data['methods'];
      _mfaMethods = (methods is List) ? methods.cast<String>() : [];
      notifyListeners();
      return;
    }

    _accessToken = data['access_token'] as String?;
    _mfaToken = null;
    _mfaMethods = [];
    notifyListeners();
  }

  /// Verifies the MFA code against the pending challenge.
  /// Called from the MFA verification screen after [mfaPending] is true.
  /// Throws [AuthException] on failure.
  Future<void> verifyMFA(String code) async {
    if (_mfaToken == null) {
      throw AuthException('No MFA challenge pending');
    }

    final resp = await http.post(
      Uri.parse('$_baseUrl/api/luma/auth/mfa/verify'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'mfa_token': _mfaToken,
        'code': code,
      }),
    );

    if (resp.statusCode != 200) {
      throw AuthException('Invalid code');
    }

    final data = json.decode(resp.body) as Map<String, dynamic>;
    _accessToken = data['access_token'] as String?;
    _mfaToken = null;
    _mfaMethods = [];
    notifyListeners();
  }

  /// Clears the pending MFA challenge — returns to the login screen.
  void cancelMFA() {
    _mfaToken = null;
    _mfaMethods = [];
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

  /// Sets the access token and marks the instance as active.
  /// Used after setup completes — the owner endpoint already returns a token.
  void activateSession(String accessToken) {
    _accessToken = accessToken;
    _setupState = 'active';
    notifyListeners();
  }

  /// Clears the in-memory token without calling the server.
  /// Called by ApiClient after a failed refresh.
  void clearSession() {
    _accessToken = null;
    _mfaToken = null;
    _mfaMethods = [];
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
