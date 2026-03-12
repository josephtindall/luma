import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// Thrown when the server returns 403 Forbidden.
class PermissionDeniedException implements Exception {
  const PermissionDeniedException();
  @override
  String toString() => 'You do not have permission to access this.';
}

/// HTTP client for Luma API calls.
///
/// Attaches Authorization: Bearer on every request. On 401, attempts one
/// silent refresh. If that fails, clears the session and throws
/// [SessionExpiredException] so the router can redirect to /login.
/// On 403, throws [PermissionDeniedException].
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
  Future<http.Response> patch(String path, Map<String, dynamic> body) =>
      _send('PATCH', path, body);
  Future<http.Response> delete(String path) => _send('DELETE', path, null);
  Future<http.Response> deleteWithBody(
          String path, Map<String, dynamic> body) =>
      _send('DELETE', path, body);

  Future<http.Response> _send(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) async {
    var resp = await _doRequest(method, path, body);

    if (resp.statusCode == 401) {
      final refreshed = await _authService.refresh();
      if (!refreshed) {
        _authService.clearSessionAsExpired();
        throw const SessionExpiredException();
      }
      resp = await _doRequest(method, path, body);
      if (resp.statusCode == 401) {
        _authService.clearSessionAsExpired();
        throw const SessionExpiredException();
      }
    }

    if (resp.statusCode == 403) {
      throw const PermissionDeniedException();
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
        return http.post(uri,
            headers: headers, body: body != null ? json.encode(body) : null);
      case 'PUT':
        return http.put(uri,
            headers: headers, body: body != null ? json.encode(body) : null);
      case 'PATCH':
        return http.patch(uri,
            headers: headers, body: body != null ? json.encode(body) : null);
      case 'DELETE':
        if (body != null) {
          final request = http.Request('DELETE', uri)
            ..headers.addAll(headers)
            ..body = json.encode(body);
          final streamed = await request.send();
          return http.Response.fromStream(streamed);
        }
        return http.delete(uri, headers: headers);
      default:
        throw ArgumentError('Unknown HTTP method: $method');
    }
  }
}
