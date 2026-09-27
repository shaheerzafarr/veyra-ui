import 'dart:typed_data';

enum IdentityTrustState { unknown, trusted, verified, changed }

enum E2eeFailureCode {
  notInitialized('E2EE_NOT_INITIALIZED'),
  identityMissing('IDENTITY_MISSING'),
  sessionMissing('SESSION_MISSING'),
  invalidBundle('INVALID_BUNDLE'),
  identityChanged('IDENTITY_CHANGED'),
  decryptionFailed('DECRYPTION_FAILED'),
  unsupportedProtocol('UNSUPPORTED_PROTOCOL'),
  deviceRevoked('DEVICE_REVOKED'),
  dependencyBlocked('E2EE_DEPENDENCY_BLOCKED');

  const E2eeFailureCode(this.wireName);
  final String wireName;

  static E2eeFailureCode fromWireName(String value) => values.firstWhere(
        (item) => item.wireName == value,
        orElse: () => E2eeFailureCode.notInitialized,
      );
}

class E2eeException implements Exception {
  const E2eeException(this.code, {this.sanitizedMessage});
  final E2eeFailureCode code;
  final String? sanitizedMessage;

  @override
  String toString() => sanitizedMessage ?? code.wireName;
}

class DeviceAddress {
  const DeviceAddress({required this.userId, required this.deviceId});
  final String userId;
  final String deviceId;

  String get lockKey => '$userId:$deviceId';
}

class DevicePublicBundle {
  const DevicePublicBundle({
    required this.protocolVersion,
    required this.registrationId,
    required this.identityPublicKey,
    required this.signedPreKeyId,
    required this.signedPreKeyPublic,
    required this.signedPreKeySignature,
    this.oneTimePreKeys = const [],
  });

  final int protocolVersion;
  final int registrationId;
  final Uint8List identityPublicKey;
  final int signedPreKeyId;
  final Uint8List signedPreKeyPublic;
  final Uint8List signedPreKeySignature;
  final List<PublicOneTimePreKey> oneTimePreKeys;
}

class PublicOneTimePreKey {
  const PublicOneTimePreKey({
    required this.preKeyId,
    required this.publicKey,
    required this.kyberPreKeyId,
    required this.kyberPublicKey,
    required this.kyberSignature,
  });

  final int preKeyId;
  final Uint8List publicKey;
  final int kyberPreKeyId;
  final Uint8List kyberPublicKey;
  final Uint8List kyberSignature;
}

class IdentityVerification {
  const IdentityVerification({
    required this.display,
    required this.scannable,
    required this.verified,
  });

  final String display;
  final Uint8List scannable;
  final bool verified;
}

class EncryptedEnvelope {
  const EncryptedEnvelope({
    required this.version,
    required this.messageId,
    required this.conversationId,
    required this.sender,
    required this.recipient,
    required this.protocolVersion,
    required this.messageType,
    required this.ciphertext,
  });

  final int version;
  final String messageId;
  final String conversationId;
  final DeviceAddress sender;
  final DeviceAddress recipient;
  final int protocolVersion;
  final String messageType;
  final Uint8List ciphertext;
}

class DecryptedMessage {
  const DecryptedMessage({
    required this.plaintext,
    required this.sender,
    required this.identityTrust,
  });

  final Uint8List plaintext;
  final DeviceAddress sender;
  final IdentityTrustState identityTrust;
}
