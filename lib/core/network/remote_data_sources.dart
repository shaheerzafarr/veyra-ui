import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import 'api_client.dart';
import 'token_storage.dart';
import '../../security/models/e2ee_models.dart';

class AuthRemoteDataSource {
  AuthRemoteDataSource(this._api, this._tokens);
  final ApiClient _api;
  final TokenStorage _tokens;

  Future<String?> register({
    required String invitationCode,
    required String email,
    required String username,
    required String displayName,
    required String password,
  }) async {
    final result =
        await _api.postJson('/auth/register', authenticated: false, body: {
      'invitation_code': invitationCode,
      'email': email,
      'username': username,
      'display_name': displayName,
      'password': password,
    });
    return result['development_verification_code'] as String?;
  }

  Future<void> verifyEmail(String email, String code) => _api.postJson(
        '/auth/verify-email',
        authenticated: false,
        body: {'email': email, 'code': code},
      );

  Future<void> login(
      {required String email,
      required String password,
      required String deviceUuid}) async {
    final result =
        await _api.postJson('/auth/login', authenticated: false, body: {
      'email': email,
      'password': password,
      'device_uuid': deviceUuid,
      'device_name': Platform.localHostname.isEmpty
          ? 'Veyra device'
          : Platform.localHostname,
      'platform': Platform.operatingSystem,
      'app_version': '0.1.0',
    });
    await _tokens.writeTokens(
      accessToken: result['access_token'] as String,
      refreshToken: result['refresh_token'] as String,
    );
  }

  Future<void> logout() async {
    final refresh = await _tokens.readRefreshToken();
    try {
      if (refresh != null) {
        await _api.postJson('/auth/logout',
            authenticated: false, body: {'refresh_token': refresh});
      }
    } finally {
      await _tokens.clear();
    }
  }
}

class UserRemoteDataSource {
  UserRemoteDataSource(this._api);
  final ApiClient _api;

  Future<Map<String, dynamic>> me() => _api.getJson('/users/me');
  Future<Map<String, dynamic>> updateMe(Map<String, dynamic> changes) =>
      _api.patchJson('/users/me', body: changes);
  Future<Map<String, dynamic>> usernameAvailability(String username) => _api
      .getJson('/users/username-availability', query: {'username': username});
  Future<List<Map<String, dynamic>>> search(String query,
      {int offset = 0}) async {
    final result = await _api
        .getJson('/users/search', query: {'q': query, 'offset': '$offset'});
    return (result['items'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> profile(String id) => _api.getJson('/users/$id');
  Future<void> block(String id) => _api.postJson('/users/$id/block');
  Future<void> unblock(String id) => _api.deleteJson('/users/$id/block');
}

class RequestRemoteDataSource {
  RequestRemoteDataSource(this._api);
  final ApiClient _api;

  Future<List<Map<String, dynamic>>> incoming() => _page('/requests/incoming');
  Future<List<Map<String, dynamic>>> outgoing() => _page('/requests/outgoing');
  Future<Map<String, dynamic>> create(String recipientId, String message) =>
      _api.postJson('/requests', body: {
        'recipient_user_id': recipientId,
        'introductory_message': message,
      });
  Future<Map<String, dynamic>> accept(String id) =>
      _api.postJson('/requests/$id/accept');
  Future<void> decline(String id) => _api.postJson('/requests/$id/decline');
  Future<void> cancel(String id) => _api.postJson('/requests/$id/cancel');

  Future<List<Map<String, dynamic>>> _page(String path) async {
    final result = await _api.getJson(path);
    return (result['items'] as List).cast<Map<String, dynamic>>();
  }
}

class DeviceRemoteDataSource {
  DeviceRemoteDataSource(this._api);
  final ApiClient _api;
  Future<List<Map<String, dynamic>>> list() async =>
      ((await _api.getJson('/devices'))['items'] as List)
          .cast<Map<String, dynamic>>();
  Future<void> revoke(String id) => _api.deleteJson('/devices/$id');
}

class CryptoRemoteDataSource {
  CryptoRemoteDataSource(this._api);
  final ApiClient _api;

  Future<int> availablePreKeyCount() async {
    final value = await _api.getJson('/devices/me/prekeys/status');
    return value['available'] as int;
  }

  Future<void> publish(DevicePublicBundle bundle) async {
    await _api.postJson('/devices/me/keys', body: {
      'protocol_version': bundle.protocolVersion,
      'registration_id': bundle.registrationId,
      'identity_public_key': base64Encode(bundle.identityPublicKey),
      'signed_prekey_id': bundle.signedPreKeyId,
      'signed_prekey_public': base64Encode(bundle.signedPreKeyPublic),
      'signed_prekey_signature': base64Encode(bundle.signedPreKeySignature),
    });
    if (bundle.oneTimePreKeys.isEmpty) return;
    await _api.postJson('/devices/me/prekeys', body: {
      'prekeys': bundle.oneTimePreKeys
          .map((key) => {
                'prekey_id': key.preKeyId,
                'public_key': base64Encode(key.publicKey),
                'kyber_prekey_id': key.kyberPreKeyId,
                'kyber_public_key': base64Encode(key.kyberPublicKey),
                'kyber_signature': base64Encode(key.kyberSignature),
              })
          .toList(),
    });
  }

  Future<DevicePublicBundle> fetchBundle(DeviceAddress remote) async {
    final value = await _api.getJson(
      '/users/${remote.userId}/devices/${remote.deviceId}/prekey-bundle',
    );
    final oneTime = value['one_time_prekey'] as Map<String, dynamic>?;
    if (oneTime == null) {
      throw StateError('Recipient has no available secure pre-key');
    }
    return DevicePublicBundle(
      protocolVersion: value['protocol_version'] as int,
      registrationId: value['registration_id'] as int,
      identityPublicKey: base64Decode(value['identity_public_key'] as String),
      signedPreKeyId: value['signed_prekey_id'] as int,
      signedPreKeyPublic: base64Decode(value['signed_prekey_public'] as String),
      signedPreKeySignature:
          base64Decode(value['signed_prekey_signature'] as String),
      oneTimePreKeys: [
        PublicOneTimePreKey(
          preKeyId: oneTime['prekey_id'] as int,
          publicKey: base64Decode(oneTime['public_key'] as String),
          kyberPreKeyId: oneTime['kyber_prekey_id'] as int,
          kyberPublicKey: base64Decode(oneTime['kyber_public_key'] as String),
          kyberSignature: base64Decode(oneTime['kyber_signature'] as String),
        ),
      ],
    );
  }
}

class ConversationRemoteDataSource {
  ConversationRemoteDataSource(this._api);
  final ApiClient _api;

  Future<List<Map<String, dynamic>>> list() async =>
      ((await _api.getJson('/conversations'))['items'] as List)
          .cast<Map<String, dynamic>>();
}

class DeviceIdentity {
  DeviceIdentity(this._tokens);
  final TokenStorage _tokens;
  Future<String> getOrCreate() async {
    final existing = await _tokens.readDeviceId();
    if (existing != null) return existing;
    final created = const Uuid().v4();
    await _tokens.writeDeviceId(created);
    return created;
  }
}
