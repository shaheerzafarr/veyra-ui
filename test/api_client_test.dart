import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veyra/core/network/api_client.dart';
import 'package:veyra/core/network/api_exception.dart';
import 'package:veyra/core/network/remote_data_sources.dart';
import 'package:veyra/core/network/token_storage.dart';

class MemoryTokenStorage implements TokenStorage {
  String? accessToken;
  String? refreshToken;
  String? deviceId;

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
  }

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<String?> readDeviceId() async => deviceId;

  @override
  Future<void> writeDeviceId(String value) async => deviceId = value;

  @override
  Future<void> writeTokens(
      {required String accessToken, required String refreshToken}) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }
}

void main() {
  test('registration, verification and login use the centralized client',
      () async {
    final tokens = MemoryTokenStorage();
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/auth/register') {
        return http.Response(
          jsonEncode({
            'user_id': '00000000-0000-0000-0000-000000000001',
            'verification_required': true,
            'development_verification_code': '123456',
          }),
          201,
        );
      }
      if (request.url.path == '/auth/verify-email') {
        return http.Response(jsonEncode({'detail': 'Email verified'}), 200);
      }
      return http.Response(
        jsonEncode({
          'access_token': 'access',
          'refresh_token': 'refresh',
          'token_type': 'bearer',
          'expires_in': 900,
        }),
        200,
      );
    });
    final remote = AuthRemoteDataSource(
      ApiClient(baseUrl: 'http://test', tokens: tokens, client: client),
      tokens,
    );

    final code = await remote.register(
      invitationCode: 'invite-code',
      email: 'alice@example.com',
      username: 'alice',
      displayName: 'Alice',
      password: 'correct-horse-battery-staple',
    );
    await remote.verifyEmail('alice@example.com', code!);
    await remote.login(
      email: 'alice@example.com',
      password: 'correct-horse-battery-staple',
      deviceUuid: 'device-uuid',
    );

    expect(requests.map((item) => item.url.path),
        ['/auth/register', '/auth/verify-email', '/auth/login']);
    expect(tokens.accessToken, 'access');
    expect(tokens.refreshToken, 'refresh');
  });

  test('401 refreshes once, rotates tokens and retries the request', () async {
    final tokens = MemoryTokenStorage()
      ..accessToken = 'expired'
      ..refreshToken = 'old-refresh';
    var meCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/auth/refresh') {
        return http.Response(
          jsonEncode({
            'access_token': 'new-access',
            'refresh_token': 'new-refresh',
            'token_type': 'bearer',
            'expires_in': 900,
          }),
          200,
        );
      }
      meCalls++;
      if (meCalls == 1) {
        return http.Response(jsonEncode({'detail': 'Expired'}), 401);
      }
      expect(request.headers['Authorization'], 'Bearer new-access');
      return http.Response(jsonEncode({'id': 'user-id'}), 200);
    });
    final api =
        ApiClient(baseUrl: 'http://test', tokens: tokens, client: client);

    expect((await api.getJson('/users/me'))['id'], 'user-id');
    expect(meCalls, 2);
    expect(tokens.refreshToken, 'new-refresh');
  });

  test('rate-limit responses map to a typed client error', () async {
    final tokens = MemoryTokenStorage()..accessToken = 'access';
    final api = ApiClient(
      baseUrl: 'http://test',
      tokens: tokens,
      client: MockClient((_) async =>
          http.Response(jsonEncode({'detail': 'Too many requests'}), 429)),
    );

    await expectLater(
      api.getJson('/users/search', query: {'q': 'alice'}),
      throwsA(isA<ApiException>()
          .having((error) => error.kind, 'kind', ApiErrorKind.rateLimited)),
    );
  });
}
