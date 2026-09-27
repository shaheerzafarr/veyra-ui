import 'package:flutter/services.dart';

class PreparedAttachmentCiphertext {
  const PreparedAttachmentCiphertext({
    required this.ciphertextPath,
    required this.fileKey,
    required this.nonce,
    required this.plaintextSize,
    required this.encryptedSize,
    required this.ciphertextSha256,
  });

  final String ciphertextPath;
  final String fileKey;
  final String nonce;
  final int plaintextSize;
  final int encryptedSize;
  final String ciphertextSha256;
}

abstract interface class AttachmentCryptoService {
  Future<PreparedAttachmentCiphertext> encryptFile(String inputPath);
  Future<String> decryptFile({
    required String ciphertextPath,
    required String fileKey,
    required String nonce,
  });
  Future<void> deletePrivateFile(String path);
  Future<void> cleanupAbandonedFiles(List<String> retainedPaths);
  Future<void> storeSecret(String attachmentId, String value);
  Future<String> readSecret(String attachmentId);
  Future<void> deleteSecret(String attachmentId);
}

class AndroidAttachmentCryptoService implements AttachmentCryptoService {
  AndroidAttachmentCryptoService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.veyra/e2ee');

  final MethodChannel _channel;

  @override
  Future<PreparedAttachmentCiphertext> encryptFile(String inputPath) async {
    final value = await _channel.invokeMapMethod<String, dynamic>(
      'encryptAttachment',
      {'inputPath': inputPath},
    );
    if (value == null ||
        value['version'] != 1 ||
        value['algorithm'] != 'AES-256-GCM') {
      throw StateError('Attachment encryption is unavailable');
    }
    return PreparedAttachmentCiphertext(
      ciphertextPath: value['ciphertextPath'] as String,
      fileKey: value['key'] as String,
      nonce: value['nonce'] as String,
      plaintextSize: value['plaintextSize'] as int,
      encryptedSize: value['encryptedSize'] as int,
      ciphertextSha256: value['ciphertextSha256'] as String,
    );
  }

  @override
  Future<String> decryptFile({
    required String ciphertextPath,
    required String fileKey,
    required String nonce,
  }) async {
    final value = await _channel.invokeMapMethod<String, dynamic>(
      'decryptAttachment',
      {'ciphertextPath': ciphertextPath, 'key': fileKey, 'nonce': nonce},
    );
    final path = value?['plaintextPath'];
    if (path is! String) throw StateError('Attachment decryption failed');
    return path;
  }

  @override
  Future<void> deletePrivateFile(String path) async {
    await _channel
        .invokeMethod<bool>('deletePrivateAttachmentFile', {'path': path});
  }

  @override
  Future<void> cleanupAbandonedFiles(List<String> retainedPaths) async {
    await _channel.invokeMethod<int>('cleanupAbandonedAttachmentFiles', {
      'retainedPaths': retainedPaths,
      'olderThanEpochMs': DateTime.now()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> storeSecret(String attachmentId, String value) async {
    await _channel.invokeMethod<bool>('storeAttachmentSecret', {
      'attachmentId': attachmentId,
      'value': value,
    });
  }

  @override
  Future<String> readSecret(String attachmentId) async {
    final value = await _channel.invokeMethod<String>('readAttachmentSecret', {
      'attachmentId': attachmentId,
    });
    if (value == null) throw StateError('Attachment key is unavailable');
    return value;
  }

  @override
  Future<void> deleteSecret(String attachmentId) async {
    await _channel.invokeMethod<bool>('deleteAttachmentSecret', {
      'attachmentId': attachmentId,
    });
  }
}
