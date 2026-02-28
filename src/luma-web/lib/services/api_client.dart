import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// HTTP client for Luma API calls.
///
/// Attaches Authorization: Bearer on every request. On 401, attempts one
/// silent refresh. If that fails, clears the session and throws
/// [SessionExpiredException] so the router can redirect to /login.
class ApiClient {
  final String _baseUrl;
  final AuthService _authService;

  ApiClient(this._authService)
      : _baseUrl = const String.fromEnvironment(
          'API_URL',
          defaultValue: 'http://localhost:8002',
        );

  Future<http.Response> get(String path) => _send('GET', path, null);
  Future<http.Response> post(String path, Map<String, dynamic> body) =>
      _send('POST', path, body);
  Future<http.Response> put(String path, Map<String, dynamic> body) =>
      _send('PUT', path, body);
  Future<http.Response> delete(String path) => _send('DELETE', path, null);

  Future<http.Response> _send(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) async {
    var resp = await _doRequest(method, path, body);

    if (resp.statusCode == 401) {
      final refreshed = await _authService.refresh();
      if (!refreshed) {
        _authService.clearSession();
        throw const SessionExpiredException();
      }
      resp = await _doRequest(method, path, body);
      if (resp.statusCode == 401) {
        _authService.clearSession();
        throw const SessionExpiredException();
      }
    }

    return resp;
  }

  Future<http.Response> _doRequest(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) async {
    final uri = Uri.parse('$_baseUrl$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    final token = _authService.accessToken;
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    switch (method) {
      case 'GET':
        return http.get(uri, headers: headers);
      case 'POST':
        return http.post(uri, headers: headers,
            body: body != null ? json.encode(body) : null);
      case 'PUT':
        return http.put(uri, headers: headers,
            body: body != null ? json.encode(body) : null);
      case 'DELETE':
        return http.delete(uri, headers: headers);
      default:
        throw ArgumentError('Unknown HTTP method: $method');
    }
  }
}
