import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/e2ee_models.dart';

final e2eeServiceProvider = Provider<E2eeService>(
  (ref) => throw StateError('E2EE service was not configured'),
);

/// Stable application boundary for the future official Android libsignal
/// integration. No implementation in Phase 5B performs message cryptography.
abstract interface class E2eeService {
  Future<void> initialize(DeviceAddress local);
  Future<bool> hasIdentity();
  Future<DevicePublicBundle> getPublicBundle();
  Future<bool> hasSession(DeviceAddress remote);
  Future<void> establishSession(
      DeviceAddress remote, DevicePublicBundle bundle);
  Future<void> markPreKeysPublished(List<int> ids);
  Future<void> replenishPreKeys(int count);
  Future<EncryptedEnvelope> encrypt({
    required String messageId,
    required String conversationId,
    required DeviceAddress sender,
    required DeviceAddress recipient,
    required Uint8List plaintext,
  });
  Future<DecryptedMessage> decrypt(EncryptedEnvelope envelope);
  Future<IdentityVerification> getSafetyNumber(DeviceAddress remote);
  Future<void> markVerified(DeviceAddress remote);
  Future<bool> verifyScannable(DeviceAddress remote, Uint8List scannable);
  Future<void> deleteSession(DeviceAddress remote);
}
