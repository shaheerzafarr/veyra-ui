import 'dart:convert';

enum AttachmentKind { image, video, document, audio, voice }

enum AttachmentTransferState {
  preparing,
  encrypting,
  encrypted,
  waitingForNetwork,
  uploading,
  uploaded,
  descriptorPending,
  sending,
  sent,
  downloading,
  downloaded,
  decrypting,
  ready,
  failed,
  cancelled,
  expired,
}

enum AttachmentStorageClass { cache, retained }

enum AutoDownloadPolicy { wifi, wifiAndMobile, never }

bool allowsAutoDownload(AutoDownloadPolicy policy,
    {required bool onWifi, required bool onMobile}) {
  return switch (policy) {
    AutoDownloadPolicy.wifi => onWifi,
    AutoDownloadPolicy.wifiAndMobile => onWifi || onMobile,
    AutoDownloadPolicy.never => false,
  };
}

class AttachmentDescriptor {
  const AttachmentDescriptor({
    required this.attachmentId,
    required this.objectId,
    required this.kind,
    required this.mimeType,
    required this.originalFilename,
    required this.plaintextSize,
    required this.encryptedSize,
    required this.fileKey,
    required this.nonce,
    required this.ciphertextSha256,
    this.durationMilliseconds,
  });

  static const protocolVersion = 1;
  final String attachmentId;
  final String objectId;
  final AttachmentKind kind;
  final String mimeType;
  final String originalFilename;
  final int plaintextSize;
  final int encryptedSize;
  final String fileKey;
  final String nonce;
  final String ciphertextSha256;
  final int? durationMilliseconds;

  Map<String, dynamic> toJson() => {
        'version': protocolVersion,
        'attachment_id': attachmentId,
        'object_id': objectId,
        'kind': kind.name,
        'mime_type': mimeType,
        'original_filename': originalFilename,
        'size': plaintextSize,
        'encrypted_size': encryptedSize,
        'duration_ms': durationMilliseconds,
        'encryption': {
          'version': 1,
          'algorithm': 'AES-256-GCM',
          'nonce': nonce,
          'file_key': fileKey,
          'tag': 'appended-128-bit',
          'aad': 'veyra-attachment-v1',
          'ciphertext_sha256': ciphertextSha256,
        },
      };

  String encode() => jsonEncode(toJson());

  factory AttachmentDescriptor.fromJson(Map<String, dynamic> value) {
    if (value['version'] != protocolVersion) {
      throw const FormatException('Unsupported attachment version');
    }
    final encryption = value['encryption'];
    if (encryption is! Map<String, dynamic> ||
        encryption['version'] != 1 ||
        encryption['algorithm'] != 'AES-256-GCM' ||
        encryption['tag'] != 'appended-128-bit' ||
        encryption['aad'] != 'veyra-attachment-v1') {
      throw const FormatException('Unsupported attachment encryption');
    }
    return AttachmentDescriptor(
      attachmentId: value['attachment_id'] as String,
      objectId: value['object_id'] as String,
      kind: AttachmentKind.values.byName(value['kind'] as String),
      mimeType: value['mime_type'] as String,
      originalFilename: value['original_filename'] as String,
      plaintextSize: value['size'] as int,
      encryptedSize: value['encrypted_size'] as int,
      durationMilliseconds: value['duration_ms'] as int?,
      fileKey: encryption['file_key'] as String,
      nonce: encryption['nonce'] as String,
      ciphertextSha256: encryption['ciphertext_sha256'] as String,
    );
  }
}

class LocalAttachment {
  const LocalAttachment({
    required this.attachmentId,
    required this.messageId,
    required this.objectId,
    required this.kind,
    required this.mimeType,
    required this.originalFilename,
    required this.plaintextSize,
    required this.encryptedSize,
    required this.transferState,
    required this.progress,
    this.localPath,
    this.sourcePath,
    this.ciphertextPath,
    this.storageClass = AttachmentStorageClass.cache,
    this.failureCode,
  });

  final String attachmentId;
  final String messageId;
  final String objectId;
  final AttachmentKind kind;
  final String mimeType;
  final String originalFilename;
  final int plaintextSize;
  final int encryptedSize;
  final AttachmentTransferState transferState;
  final double progress;
  final String? localPath;
  final String? sourcePath;
  final String? ciphertextPath;
  final AttachmentStorageClass storageClass;
  final String? failureCode;
}

class AttachmentStorageUsage {
  const AttachmentStorageUsage({
    required this.images,
    required this.videos,
    required this.documents,
    required this.audioAndVoice,
  });

  final int images;
  final int videos;
  final int documents;
  final int audioAndVoice;
  int get total => images + videos + documents + audioAndVoice;
}
