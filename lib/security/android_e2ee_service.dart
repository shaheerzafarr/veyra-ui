import 'package:flutter/services.dart';

import 'dart:convert';

import 'e2ee_service.dart';
import 'models/e2ee_models.dart';

/// One isolated Flutter-to-Kotlin boundary backed by pinned official libsignal.
class AndroidE2eeService implements E2eeService {
  AndroidE2eeService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.veyra/e2ee');

  final MethodChannel _channel;

  Future<T> _invoke<T>(String method, [Map<String, Object?>? arguments]) async {
    try {
      final value = await _channel.invokeMethod<T>(method, arguments);
      if (value == null) {
        throw const E2eeException(E2eeFailureCode.notInitialized);
      }
      return value;
    } on PlatformException catch (error) {
      throw E2eeException(
        E2eeFailureCode.fromWireName(error.code),
        sanitizedMessage: error.message,
      );
    }
  }

  @override
  Future<void> initialize(DeviceAddress local) async {
    await _invoke<bool>('initialize', {
      'localUserId': local.userId,
      'localDeviceId': local.deviceId,
    });
  }

  @override
  Future<bool> hasIdentity() => _invoke<bool>('hasIdentity');

  @override
  Future<DevicePublicBundle> getPublicBundle() async {
    final value = await _invoke<Map<Object?, Object?>>('getPublicBundle');
    final preKeys = (value['prekeys'] as List<Object?>? ?? const [])
        .cast<Map<Object?, Object?>>()
        .map((item) => PublicOneTimePreKey(
              preKeyId: item['prekeyId'] as int,
              publicKey: base64Decode(item['publicKey'] as String),
              kyberPreKeyId: item['kyberPrekeyId'] as int,
              kyberPublicKey: base64Decode(item['kyberPublicKey'] as String),
              kyberSignature: base64Decode(item['kyberSignature'] as String),
            ))
        .toList();
    return DevicePublicBundle(
      protocolVersion: value['protocolVersion'] as int,
      registrationId: value['registrationId'] as int,
      identityPublicKey: base64Decode(value['identityPublicKey'] as String),
      signedPreKeyId: value['signedPrekeyId'] as int,
      signedPreKeyPublic: base64Decode(value['signedPrekeyPublic'] as String),
      signedPreKeySignature:
          base64Decode(value['signedPrekeySignature'] as String),
      oneTimePreKeys: preKeys,
    );
  }

  @override
  Future<void> markPreKeysPublished(List<int> ids) async {
    await _invoke<bool>('markPreKeysPublished', {'ids': ids});
  }

  @override
  Future<void> replenishPreKeys(int count) async {
    await _invoke<bool>('replenishPreKeys', {'count': count});
  }

  @override
  Future<bool> hasSession(DeviceAddress remote) => _invoke<bool>(
        'hasSession',
        {'remoteUserId': remote.userId, 'remoteDeviceId': remote.deviceId},
      );

  @override
  Future<void> establishSession(
      DeviceAddress remote, DevicePublicBundle bundle) async {
    final oneTime = bundle.oneTimePreKeys.single;
    await _invoke<bool>('establishSession', {
      'remoteUserId': remote.userId,
      'remoteDeviceId': remote.deviceId,
      'bundle': {
        'registrationId': bundle.registrationId,
        'identityPublicKey': base64Encode(bundle.identityPublicKey),
        'signedPrekeyId': bundle.signedPreKeyId,
        'signedPrekeyPublic': base64Encode(bundle.signedPreKeyPublic),
        'signedPrekeySignature': base64Encode(bundle.signedPreKeySignature),
        'oneTimePrekey': {
          'prekeyId': oneTime.preKeyId,
          'publicKey': base64Encode(oneTime.publicKey),
          'kyberPrekeyId': oneTime.kyberPreKeyId,
          'kyberPublicKey': base64Encode(oneTime.kyberPublicKey),
          'kyberSignature': base64Encode(oneTime.kyberSignature),
        },
      },
    });
  }

  @override
  Future<EncryptedEnvelope> encrypt({
    required String messageId,
    required String conversationId,
    required DeviceAddress sender,
    required DeviceAddress recipient,
    required Uint8List plaintext,
  }) async {
    final value = await _invoke<Map<Object?, Object?>>('encrypt', {
      'remoteUserId': recipient.userId,
      'remoteDeviceId': recipient.deviceId,
      'plaintext': plaintext,
    });
    return EncryptedEnvelope(
      version: 1,
      messageId: messageId,
      conversationId: conversationId,
      sender: sender,
      recipient: recipient,
      protocolVersion: value['protocolVersion'] as int,
      messageType: value['messageType'] as String,
      ciphertext: base64Decode(value['ciphertext'] as String),
    );
  }

  @override
  Future<DecryptedMessage> decrypt(EncryptedEnvelope envelope) async {
    final value = await _invoke<Map<Object?, Object?>>('decrypt', {
      'remoteUserId': envelope.sender.userId,
      'remoteDeviceId': envelope.sender.deviceId,
      'messageType': envelope.messageType,
      'ciphertext': base64Encode(envelope.ciphertext),
    });
    return DecryptedMessage(
      plaintext: value['plaintext'] as Uint8List,
      sender: envelope.sender,
      identityTrust:
          IdentityTrustState.values.byName(value['identityTrust'] as String),
    );
  }

  @override
  Future<IdentityVerification> getSafetyNumber(DeviceAddress remote) async {
    final value = await _invoke<Map<Object?, Object?>>('getSafetyNumber', {
      'remoteUserId': remote.userId,
      'remoteDeviceId': remote.deviceId,
    });
    return IdentityVerification(
      display: value['display'] as String,
      scannable: base64Decode(value['scannable'] as String),
      verified: value['verified'] as bool,
    );
  }

  @override
  Future<void> markVerified(DeviceAddress remote) async {
    await _invoke<bool>('markVerified', {
      'remoteUserId': remote.userId,
      'remoteDeviceId': remote.deviceId,
    });
  }

  @override
  Future<bool> verifyScannable(
      DeviceAddress remote, Uint8List scannable) async {
    return _invoke<bool>('verifyScannable', {
      'remoteUserId': remote.userId,
      'remoteDeviceId': remote.deviceId,
      'scannable': scannable,
    });
  }

  @override
  Future<void> deleteSession(DeviceAddress remote) async {
    await _invoke<bool>('deleteSession', {
      'remoteUserId': remote.userId,
      'remoteDeviceId': remote.deviceId,
    });
  }
}
