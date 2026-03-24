import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'webauthn_interop.dart' as webauthn;

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

/// Returns a stable, per-browser fingerprint stored in localStorage.
/// Generated once on first call, then reused across sessions so that
/// setup, login, and MFA all reference the same device record.
String getDeviceFingerprint() {
  const key = 'luma_device_fp';
  try {
    final storage = globalContext['localStorage'] as JSObject?;
    if (storage == null) return _generateUUID();

    final existing =
        (storage.callMethod<JSAny?>('getItem'.toJS, key.toJS) as JSString?)
            ?.toDart;
    if (existing != null && existing.isNotEmpty) return existing;

    final fp = _generateUUID();
    storage.callMethod<JSAny?>('setItem'.toJS, key.toJS, fp.toJS);
    return fp;
  } catch (_) {
    return _generateUUID();
  }
}

/// Generates a v4 UUID using Dart's secure random number generator.
String _generateUUID() {
  math.Random random;
  try {
    random = math.Random.secure();
  } catch (_) {
    // Fallback if secure random is not available on this platform.
    random = math.Random(DateTime.now().millisecondsSinceEpoch);
  }

  // Generate 16 random bytes
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));

  // Protocol v4 requires setting specific bits in byte 6 and 8
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  // Convert to hex string
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).toList();

  return '${hex.sublist(0, 4).join('')}-${hex.sublist(4, 6).join('')}-${hex.sublist(6, 8).join('')}-${hex.sublist(8, 10).join('')}-${hex.sublist(10, 16).join('')}';
}

/// Manages authentication state for the Luma web app.
///
/// Access token lives in memory only. The refresh cookie (HttpOnly, managed by
/// the browser) re-establishes sessions on reload.
class AuthService extends ChangeNotifier {
  final String _baseUrl;

  String? _accessToken;
  String _setupState = 'unknown'; // "unknown" | "unclaimed" | "active"
  String _instanceName = '';
  bool _isInitialized = false;

  // MFA challenge state — set when login returns mfa_required.
  String? _mfaToken;
  List<String> _mfaMethods = [];

  // Force-change state — set when login returns password_change_required.
  String? _forceChangeToken;

  // Recovery token pending — set after registration/setup until the user
  // acknowledges the code on the recovery-code screen.
  String? _pendingRecoveryToken;

  // Session expiry flag — set when an API call fails because the refresh
  // token is also expired. Consumed once by the login screen to show a SnackBar.
  bool _sessionJustExpired = false;

  /// Called when the session is cleared (logout, expiry) so dependent services
  /// can drop cached state. Set from main.dart to avoid circular imports.
  VoidCallback? onSessionCleared;

  /// Called immediately after a new session is established (login, MFA verify,
  /// passkey sign-in, registration, setup activation). Triggers profile and
  /// vault loading. Set from main.dart to avoid circular imports.
  VoidCallback? onLogin;

  AuthService(this._baseUrl);

  String? get accessToken => _accessToken;
  bool get isLoggedIn => _accessToken != null;
  String get setupState => _setupState;
  String get instanceName => _instanceName;
  bool get isInitialized => _isInitialized;

  /// True when login succeeded but a second factor is required.
  bool get mfaPending => _mfaToken != null;
  List<String> get mfaMethods => _mfaMethods;

  /// True when login requires a password change before issuing a session.
  bool get hasPasswordChangePending => _forceChangeToken != null;

  /// The short-lived token used to authorize the force-change reset request.
  String? get forceChangeToken => _forceChangeToken;

  /// True when the user just registered and must acknowledge their recovery code.
  bool get recoveryTokenPending => _pendingRecoveryToken != null;

  /// The one-time recovery token that was generated during registration.
  String? get pendingRecoveryToken => _pendingRecoveryToken;

  /// Called from the recovery-code screen after the user has saved the code.
  void acknowledgeRecoveryToken() {
    _pendingRecoveryToken = null;
    notifyListeners();
  }

  /// True when the session was cleared due to expiry (not explicit logout).
  /// Consumed once by the login screen initState.
  bool get sessionJustExpired => _sessionJustExpired;

  /// Clears the expiry flag — call after showing the snackbar.
  void clearSessionExpiredFlag() => _sessionJustExpired = false;

  /// Clears the session and marks it as expired so the login screen
  /// can show a contextual message. Called by ApiClient on refresh failure.
  void clearSessionAsExpired() {
    _sessionJustExpired = true;
    clearSession();
  }

  /// Called from main.dart before runApp. Probes auth service state and attempts
  /// silent token refresh if the instance is active.
  Future<void> initialize() async {
    try {
      final resp = await http.get(Uri.parse('$_baseUrl/api/luma/setup/status'));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        _setupState = (data['state'] as String?) ?? 'unknown';
        _instanceName = (data['instance_name'] as String?) ?? '';
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

  /// Queries which MFA methods are available for the given email.
  /// Does not require a password — used to decide which login step to show.
  Future<IdentifyResult> identify(String email) async {
    final resp = await http.post(
      Uri.parse('$_baseUrl/api/luma/auth/identify'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email}),
    );

    if (resp.statusCode != 200) {
      // On any error, fall back to password-only flow.
      return IdentifyResult(hasPasskey: false, hasTOTP: false, hasMFA: false);
    }

    final data = json.decode(resp.body) as Map<String, dynamic>;
    return IdentifyResult(
      hasPasskey: data['has_passkey'] == true,
      hasTOTP: data['has_totp'] == true,
      hasMFA: data['has_mfa'] == true,
    );
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
        'fingerprint': getDeviceFingerprint(),
      }),
    );

    if (resp.statusCode != 200) {
      if (resp.statusCode == 429) {
        throw AuthException('Too many attempts. Please wait a few minutes.');
      }
      if (resp.statusCode == 403) {
        throw AuthException('Account locked. Contact an administrator.');
      }
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

    // Password change required — store the change token and redirect.
    if (data['password_change_required'] == true) {
      _forceChangeToken = data['change_token'] as String?;
      notifyListeners();
      return;
    }

    _accessToken = data['access_token'] as String?;
    _mfaToken = null;
    _mfaMethods = [];
    onLogin?.call();
    notifyListeners();
  }

  /// Resets the password using a one-time token (admin reset or force-change).
  /// Issues a new session on success.
  Future<void> resetPassword(String token, String newPassword) async {
    final resp = await http.post(
      Uri.parse('$_baseUrl/api/luma/auth/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'token': token,
        'new_password': newPassword,
        'platform': 'web',
        'device_name': detectBrowserName(),
        'fingerprint': getDeviceFingerprint(),
      }),
    );
    if (resp.statusCode != 200) {
      final data = json.decode(resp.body) as Map<String, dynamic>;
      throw AuthException(
          (data['message'] ?? data['error'] ?? 'Password reset failed')
              .toString());
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    _accessToken = data['access_token'] as String?;
    _forceChangeToken = null;
    onLogin?.call();
    notifyListeners();
  }

  /// Resets the password using the 64-digit account recovery token.
  /// Issues a new session on success. The user must provide a new password
  /// as part of the recovery flow.
  Future<void> resetWithAccountRecovery(
      String email, String token, String newPassword) async {
    final resp = await http.post(
      Uri.parse('$_baseUrl/api/luma/auth/recovery/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'email': email,
        'token': token,
        'new_password': newPassword,
        'platform': 'web',
        'device_name': detectBrowserName(),
        'fingerprint': getDeviceFingerprint(),
      }),
    );
    if (resp.statusCode != 200) {
      final data = json.decode(resp.body) as Map<String, dynamic>;
      throw AuthException(
          (data['message'] ?? data['error'] ?? 'Recovery failed').toString());
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    _accessToken = data['access_token'] as String?;
    _mfaToken = null;
    _mfaMethods = [];
    onLogin?.call();
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
    onLogin?.call();
    notifyListeners();
  }

  /// Verifies MFA using a passkey (WebAuthn assertion).
  /// Called from the MFA screen when the user chooses to use a passkey.
  /// Throws [AuthException] on failure.
  Future<void> verifyMFAWithPasskey() async {
    if (_mfaToken == null) {
      throw AuthException('No MFA challenge pending');
    }

    // Step 1: Begin the passkey login ceremony.
    final beginResp = await http.post(
      Uri.parse('$_baseUrl/api/luma/auth/passkeys/login/begin'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'mfa_token': _mfaToken}),
    );
    if (beginResp.statusCode != 200) {
      throw AuthException('Failed to start passkey login');
    }
    final assertionOptions =
        json.decode(beginResp.body) as Map<String, dynamic>;

    // Step 2: Prompt the browser authenticator.
    final credential = await webauthn.getCredential(assertionOptions);

    // Step 3: Send assertion + mfa_token to finish.
    final finishBody = <String, dynamic>{
      ...credential,
      'mfa_token': _mfaToken,
    };
    final finishResp = await http.post(
      Uri.parse('$_baseUrl/api/luma/auth/passkeys/login/finish'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(finishBody),
    );
    if (finishResp.statusCode != 200) {
      throw AuthException('Passkey verification failed');
    }

    final data = json.decode(finishResp.body) as Map<String, dynamic>;
    _accessToken = data['access_token'] as String?;
    _mfaToken = null;
    _mfaMethods = [];
    onLogin?.call();
    notifyListeners();
  }

  /// Signs in with a passkey alone (passwordless).
  /// Calls the dedicated passwordless passkey endpoints — no password required.
  /// Throws [AuthException] on failure.
  Future<void> signInWithPasskey(String email) async {
    // Step 1: Begin the passkey login ceremony with just the email.
    final beginResp = await http.post(
      Uri.parse('$_baseUrl/api/luma/auth/passkeys/passwordless/begin'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email}),
    );
    if (beginResp.statusCode != 200) {
      throw AuthException('Failed to start passkey login');
    }
    final assertionOptions =
        json.decode(beginResp.body) as Map<String, dynamic>;

    // Step 2: Prompt the browser authenticator.
    final credential = await webauthn.getCredential(assertionOptions);

    // Step 3: Send assertion + device info to finish (no mfa_token needed).
    final finishBody = <String, dynamic>{
      ...credential,
      'email': email,
      'fingerprint': getDeviceFingerprint(),
      'device_name': detectBrowserName(),
      'platform': 'web',
    };
    final finishResp = await http.post(
      Uri.parse('$_baseUrl/api/luma/auth/passkeys/passwordless/finish'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(finishBody),
    );
    if (finishResp.statusCode != 200) {
      throw AuthException('Passkey verification failed');
    }

    final data2 = json.decode(finishResp.body) as Map<String, dynamic>;
    _accessToken = data2['access_token'] as String?;
    _mfaToken = null;
    _mfaMethods = [];
    onLogin?.call();
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
      await http.post(
        Uri.parse('$_baseUrl/api/luma/auth/logout'),
        headers: {
          if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        },
      );
    } catch (_) {}
    _accessToken = null;
    onSessionCleared?.call();
    notifyListeners();
  }

  /// Fetches invitation metadata from the join endpoint.
  /// Returns {invitation_id, email, note} on success.
  /// Throws [AuthException] if the token is invalid or expired.
  Future<Map<String, dynamic>> lookupInvite(String token) async {
    final resp = await http.get(
      Uri.parse('$_baseUrl/api/luma/auth/join?token=$token'),
    );
    if (resp.statusCode != 200) {
      throw AuthException('Invitation not found or expired');
    }
    return json.decode(resp.body) as Map<String, dynamic>;
  }

  /// Registers a new user via invitation and stores the access token.
  /// Throws [AuthException] on failure.
  Future<void> register({
    required String invitationId,
    required String email,
    required String password,
    required String displayName,
  }) async {
    final resp = await http.post(
      Uri.parse('$_baseUrl/api/luma/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'invitation_id': invitationId,
        'email': email,
        'password': password,
        'display_name': displayName,
        'platform': 'web',
        'device_name': detectBrowserName(),
        'fingerprint': getDeviceFingerprint(),
      }),
    );
    if (resp.statusCode != 201) {
      if (resp.statusCode == 400) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        throw AuthException(
            (data['message'] ?? data['error'] ?? 'Registration failed')
                .toString());
      }
      throw AuthException('Registration failed');
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    _accessToken = data['access_token'] as String?;
    _pendingRecoveryToken = data['recovery_token'] as String?;
    onLogin?.call();
    notifyListeners();
  }

  /// Sets the access token and marks the instance as active.
  /// Used after setup completes — the owner endpoint already returns a token.
  /// Pass [recoveryToken] to trigger the recovery-code acknowledgement screen.
  void activateSession(String accessToken, {String? recoveryToken}) {
    _accessToken = accessToken;
    _setupState = 'active';
    _pendingRecoveryToken = recoveryToken;
    onLogin?.call();
    notifyListeners();
  }

  /// Clears the in-memory token without calling the server.
  /// Called by ApiClient after a failed refresh.
  void clearSession() {
    _accessToken = null;
    _mfaToken = null;
    _mfaMethods = [];
    _forceChangeToken = null;
    _pendingRecoveryToken = null;
    onSessionCleared?.call();
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

/// The result of calling [AuthService.identify] — tells the login screen
/// which authentication step to present.
class IdentifyResult {
  final bool hasPasskey;
  final bool hasTOTP;
  final bool hasMFA;

  const IdentifyResult({
    required this.hasPasskey,
    required this.hasTOTP,
    required this.hasMFA,
  });
}
