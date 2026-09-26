import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'token_storage.dart';

class ApiClient {
  ApiClient(
      {required this.baseUrl,
      required TokenStorage tokens,
      http.Client? client})
      : _tokens = tokens,
        _client = client ?? http.Client();

  final String baseUrl;
  final TokenStorage _tokens;
  final http.Client _client;
  static const _timeout = Duration(seconds: 15);
  Future<void>? _refreshing;

  Future<String?> websocketAccessToken({bool refresh = false}) async {
    if (refresh) await _refreshTokens();
    return _tokens.readAccessToken();
  }

  Future<Map<String, dynamic>> getJson(String path,
          {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<Map<String, dynamic>> postJson(String path,
          {Map<String, dynamic>? body, bool authenticated = true}) =>
      _send('POST', path, body: body, authenticated: authenticated);

  Future<Map<String, dynamic>> patchJson(String path,
          {required Map<String, dynamic> body}) =>
      _send('PATCH', path, body: body);

  Future<Map<String, dynamic>> deleteJson(String path) => _send('DELETE', path);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool authenticated = true,
    bool mayRefresh = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (authenticated) {
      final token = await _tokens.readAccessToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 401 && authenticated && mayRefresh) {
        await _refreshTokens();
        return await _send(
          method,
          path,
          body: body,
          query: query,
          mayRefresh: false,
        );
      }
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = decoded is Map<String, dynamic>
            ? decoded['detail']?.toString()
            : null;
        throw ApiException(
            _kind(response.statusCode), detail ?? 'Something went wrong',
            statusCode: response.statusCode);
      }
      return decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{'items': decoded};
    } on SocketException {
      throw const ApiException(
          ApiErrorKind.noInternet, 'No internet connection');
    } on TimeoutException {
      throw const ApiException(
          ApiErrorKind.unavailable, 'Veyra is temporarily unavailable');
    } on FormatException {
      throw const ApiException(
          ApiErrorKind.unknown, 'The server returned an invalid response');
    }
  }

  Future<void> _refreshTokens() async {
    if (_refreshing != null) return _refreshing;
    final completer = Completer<void>();
    _refreshing = completer.future;
    try {
      final refresh = await _tokens.readRefreshToken();
      if (refresh == null) {
        throw const ApiException(
            ApiErrorKind.expiredSession, 'Please sign in again');
      }
      final result = await postJson('/auth/refresh',
          body: {'refresh_token': refresh}, authenticated: false);
      await _tokens.writeTokens(
          accessToken: result['access_token'] as String,
          refreshToken: result['refresh_token'] as String);
      completer.complete();
    } catch (error, stack) {
      await _tokens.clear();
      completer.completeError(error, stack);
      rethrow;
    } finally {
      _refreshing = null;
    }
  }

  ApiErrorKind _kind(int status) => switch (status) {
        401 => ApiErrorKind.invalidCredentials,
        409 => ApiErrorKind.conflict,
        422 => ApiErrorKind.validation,
        429 => ApiErrorKind.rateLimited,
        >= 500 => ApiErrorKind.unavailable,
        _ => ApiErrorKind.unknown,
      };
}
