import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../security/attachment_crypto_service.dart';
import '../models/attachment.dart';
import '../models/entities.dart';
import '../network/attachment_remote_data_source.dart';
import 'network_message_repository.dart';
import 'repositories.dart';

class AttachmentCoordinator {
  AttachmentCoordinator({
    required AttachmentRemoteDataSource remote,
    required AttachmentCryptoService crypto,
    required LocalVeyraRepository local,
    required NetworkMessageRepository messages,
  })  : _remote = remote,
        _crypto = crypto,
        _local = local,
        _messages = messages;

  final AttachmentRemoteDataSource _remote;
  final AttachmentCryptoService _crypto;
  final LocalVeyraRepository _local;
  final NetworkMessageRepository _messages;
  final Map<String, AttachmentTransferCancellation> _cancellations = {};

  Future<ChatMessage> sendFile({
    required String conversationId,
    required String senderId,
    required String inputPath,
    required AttachmentKind kind,
    void Function(AttachmentTransferState state, double progress)? onProgress,
    void Function(String attachmentId)? onAttachmentCreated,
    int? durationMilliseconds,
  }) async {
    if ((await _local.getConversation(conversationId))?.type !=
        ConversationType.direct) {
      throw StateError('Encrypted group attachments are not supported');
    }
    onProgress?.call(AttachmentTransferState.preparing, 0);
    final detectedMime = await _validateAndDetect(inputPath, kind);
    final attachmentId = const Uuid().v4();
    final source = File(inputPath);
    final message = await _messages.stageAttachment(
      attachmentId: attachmentId,
      conversationId: conversationId,
      senderId: senderId,
      kind: kind,
      mimeType: detectedMime,
      originalFilename: p.basename(inputPath),
      plaintextSize: await source.length(),
      sourcePath: inputPath,
    );
    onAttachmentCreated?.call(attachmentId);
    final cancellation = AttachmentTransferCancellation();
    _cancellations[attachmentId] = cancellation;
    await _local.updateAttachmentState(
        attachmentId, AttachmentTransferState.encrypting);
    onProgress?.call(AttachmentTransferState.encrypting, 0);
    String? ciphertextPath;
    AttachmentUploadAuthorization? authorization;
    try {
      final encrypted = await _crypto.encryptFile(inputPath);
      ciphertextPath = encrypted.ciphertextPath;
      cancellation.throwIfCancelled();
      final conversation = await _local.getConversation(conversationId);
      final recipientDeviceId = conversation?.remoteDeviceId;
      if (recipientDeviceId == null) {
        throw StateError('Recipient device is unavailable');
      }
      authorization = await _remote.createUpload(
        attachmentId: attachmentId,
        conversationId: conversationId,
        recipientDeviceId: recipientDeviceId,
        kind: kind,
        encryptedSize: encrypted.encryptedSize,
      );
      final descriptor = AttachmentDescriptor(
        attachmentId: attachmentId,
        objectId: authorization.objectId,
        kind: kind,
        mimeType: detectedMime,
        originalFilename: p.basename(inputPath),
        plaintextSize: encrypted.plaintextSize,
        encryptedSize: encrypted.encryptedSize,
        fileKey: encrypted.fileKey,
        nonce: encrypted.nonce,
        ciphertextSha256: encrypted.ciphertextSha256,
        durationMilliseconds: durationMilliseconds,
      );
      await _crypto.storeSecret(attachmentId, descriptor.encode());
      await _local.updateAttachmentPrepared(
        attachmentId,
        objectId: authorization.objectId,
        ciphertextPath: encrypted.ciphertextPath,
        encryptedSize: encrypted.encryptedSize,
      );
      onProgress?.call(AttachmentTransferState.uploading, 0);
      await _local.updateAttachmentState(
          attachmentId, AttachmentTransferState.uploading,
          progress: 0);
      await _remote.uploadCiphertext(
        authorization,
        encrypted.ciphertextPath,
        cancellation: cancellation,
        onProgress: (value) =>
            onProgress?.call(AttachmentTransferState.uploading, value),
      );
      await _remote.markUploaded(authorization.attachmentId);
      await _local.updateAttachmentState(
          attachmentId, AttachmentTransferState.uploaded,
          progress: 1);
      onProgress?.call(AttachmentTransferState.sending, 1);
      await _messages.sendPreparedAttachment(message, descriptor);
      if (kind == AttachmentKind.voice && await source.exists()) {
        await source.delete();
      }
      return message;
    } on AttachmentTransferCancelled {
      await _local.updateAttachmentState(
          attachmentId, AttachmentTransferState.cancelled,
          clearCiphertextPath: true);
      if (ciphertextPath != null) {
        await _crypto.deletePrivateFile(ciphertextPath);
      }
      if (authorization != null) {
        try {
          await _remote.cancel(authorization.attachmentId);
        } catch (_) {}
      }
      rethrow;
    } on SocketException catch (_) {
      await _local.updateAttachmentState(
          attachmentId, AttachmentTransferState.waitingForNetwork,
          failureCode: 'network_unavailable');
      rethrow;
    } on HttpException catch (_) {
      await _local.updateAttachmentState(
          attachmentId, AttachmentTransferState.waitingForNetwork,
          failureCode: 'transfer_failed');
      rethrow;
    } catch (error) {
      await _local.updateAttachmentState(
          attachmentId, AttachmentTransferState.failed,
          failureCode: error.runtimeType.toString());
      rethrow;
    } finally {
      _cancellations.remove(attachmentId);
    }
  }

  Future<String> download(String attachmentId,
      {void Function(AttachmentTransferState state, double progress)?
          onProgress}) async {
    final local = await _local.getAttachment(attachmentId);
    if (local == null) throw StateError('Attachment is unavailable');
    if (local.localPath case final path?) {
      if (await File(path).exists()) return path;
    }
    final descriptor = AttachmentDescriptor.fromJson(
      (jsonDecode(await _crypto.readSecret(attachmentId)) as Map)
          .cast<String, dynamic>(),
    );
    await _local.updateAttachmentState(
        attachmentId, AttachmentTransferState.downloading,
        progress: 0);
    String? ciphertextPath;
    final cancellation = AttachmentTransferCancellation();
    _cancellations[attachmentId] = cancellation;
    try {
      ciphertextPath = await _remote.downloadCiphertext(
        attachmentId,
        cancellation: cancellation,
        onProgress: (value) {
          onProgress?.call(AttachmentTransferState.downloading, value);
          // Persistence is intentionally throttled to transfer milestones by
          // the caller; the visual callback may update more frequently.
        },
      );
      await _local.updateAttachmentState(
          attachmentId, AttachmentTransferState.downloaded,
          progress: 1);
      onProgress?.call(AttachmentTransferState.decrypting, 1);
      await _local.updateAttachmentState(
          attachmentId, AttachmentTransferState.decrypting,
          progress: 1);
      final plaintextPath = await _crypto.decryptFile(
        ciphertextPath: ciphertextPath,
        fileKey: descriptor.fileKey,
        nonce: descriptor.nonce,
      );
      await _local.updateAttachmentState(
        attachmentId,
        AttachmentTransferState.ready,
        progress: 1,
        localPath: plaintextPath,
      );
      await _remote.acknowledgeReceived(attachmentId);
      return plaintextPath;
    } on AttachmentTransferCancelled {
      await _local.updateAttachmentState(
          attachmentId, AttachmentTransferState.cancelled,
          progress: 0);
      rethrow;
    } catch (error) {
      await _local.updateAttachmentState(
        attachmentId,
        AttachmentTransferState.failed,
        failureCode: error.runtimeType.toString(),
      );
      rethrow;
    } finally {
      _cancellations.remove(attachmentId);
      if (ciphertextPath != null) {
        final file = File(ciphertextPath);
        if (await file.exists()) await file.delete();
      }
    }
  }

  Future<void> cancel(String attachmentId) async {
    _cancellations[attachmentId]?.cancel();
    final attachment = await _local.getAttachment(attachmentId);
    if (attachment == null) return;
    if (attachment.ciphertextPath case final path?) {
      await _crypto.deletePrivateFile(path);
    }
    if (attachment.objectId.isNotEmpty) {
      try {
        await _remote.cancel(attachmentId);
      } catch (_) {}
    }
    await _local.updateAttachmentState(
        attachmentId, AttachmentTransferState.cancelled,
        progress: 0, clearCiphertextPath: true);
  }

  Future<void> retry(String attachmentId,
      {void Function(AttachmentTransferState state, double progress)?
          onProgress}) async {
    final attachment = await _local.getAttachment(attachmentId);
    if (attachment == null) throw StateError('Attachment is unavailable');
    if (attachment.ciphertextPath != null) {
      await _resumeUpload(attachment, onProgress: onProgress);
    } else if (attachment.transferState == AttachmentTransferState.sent ||
        attachment.transferState == AttachmentTransferState.failed ||
        attachment.transferState == AttachmentTransferState.cancelled) {
      await download(attachmentId, onProgress: onProgress);
    }
  }

  Future<void> recoverPending() async {
    await _crypto.cleanupAbandonedFiles(await _local.retainedAttachmentPaths());
    await _cleanupAbandonedRecordings();
    for (final attachment in await _local.recoverableAttachments()) {
      try {
        if (attachment.ciphertextPath != null &&
            await File(attachment.ciphertextPath!).exists()) {
          await _resumeUpload(attachment);
        } else if (attachment.transferState ==
                AttachmentTransferState.descriptorPending ||
            attachment.transferState == AttachmentTransferState.sending) {
          await _messages.retryAttachmentMessage(attachment.messageId);
        } else if (attachment.transferState ==
                AttachmentTransferState.downloading ||
            attachment.transferState == AttachmentTransferState.downloaded ||
            attachment.transferState == AttachmentTransferState.decrypting) {
          await download(attachment.attachmentId);
        } else if (attachment.transferState ==
                AttachmentTransferState.preparing ||
            attachment.transferState == AttachmentTransferState.encrypting) {
          await _local.updateAttachmentState(
              attachment.attachmentId, AttachmentTransferState.failed,
              failureCode: 'interrupted_before_encryption_completed');
        }
      } catch (_) {
        // The operation records its own durable failure/waiting state.
      }
    }
  }

  Future<void> _cleanupAbandonedRecordings() async {
    final directory = await getTemporaryDirectory();
    final recordingCutoff = DateTime.now().subtract(const Duration(hours: 24));
    final transferCutoff = DateTime.now().subtract(const Duration(hours: 1));
    await for (final entry in directory.list()) {
      if (entry is File) {
        final name = p.basename(entry.path);
        final modified = await entry.lastModified();
        if ((name.startsWith('voice-') && modified.isBefore(recordingCutoff)) ||
            (name.endsWith('.ciphertext') &&
                modified.isBefore(transferCutoff))) {
          await entry.delete();
        }
      }
    }
  }

  Future<void> _resumeUpload(LocalAttachment attachment,
      {void Function(AttachmentTransferState state, double progress)?
          onProgress}) async {
    final path = attachment.ciphertextPath;
    if (path == null || !await File(path).exists()) {
      await _local.updateAttachmentState(
          attachment.attachmentId, AttachmentTransferState.failed,
          failureCode: 'prepared_ciphertext_missing');
      return;
    }
    final descriptor = AttachmentDescriptor.fromJson(
      (jsonDecode(await _crypto.readSecret(attachment.attachmentId)) as Map)
          .cast<String, dynamic>(),
    );
    final message = await _local.getMessage(attachment.messageId);
    final conversation = message == null
        ? null
        : await _local.getConversation(message.conversationId);
    if (message == null || conversation?.remoteDeviceId == null) {
      throw StateError('Recipient device is unavailable');
    }
    final cancellation = AttachmentTransferCancellation();
    _cancellations[attachment.attachmentId] = cancellation;
    try {
      final authorization = await _remote.createUpload(
        attachmentId: attachment.attachmentId,
        conversationId: message.conversationId,
        recipientDeviceId: conversation!.remoteDeviceId!,
        kind: attachment.kind,
        encryptedSize: attachment.encryptedSize,
      );
      await _local.updateAttachmentState(
          attachment.attachmentId, AttachmentTransferState.uploading,
          progress: 0);
      await _remote.uploadCiphertext(authorization, path,
          cancellation: cancellation,
          onProgress: (value) =>
              onProgress?.call(AttachmentTransferState.uploading, value));
      await _remote.markUploaded(attachment.attachmentId);
      await _local.updateAttachmentState(
          attachment.attachmentId, AttachmentTransferState.uploaded,
          progress: 1);
      await _messages.sendPreparedAttachment(message, descriptor);
    } on SocketException {
      await _local.updateAttachmentState(
          attachment.attachmentId, AttachmentTransferState.waitingForNetwork,
          failureCode: 'network_unavailable');
    } finally {
      _cancellations.remove(attachment.attachmentId);
    }
  }

  Future<AttachmentStorageUsage> storageUsage() =>
      _local.attachmentStorageUsage();

  Future<void> clearCache() async {
    for (final path in await _local.clearAttachmentCacheRecords()) {
      await _crypto.deletePrivateFile(path);
    }
  }

  Future<LocalAttachment?> attachmentForMessage(String messageId) =>
      _local.getAttachmentForMessage(messageId);

  Future<String> _validateAndDetect(String path, AttachmentKind kind) async {
    final file = File(path);
    if (!await file.exists()) throw const FileSystemException('File missing');
    final input = await file.open();
    final length = await file.length();
    final header = await input.read(length.clamp(0, 32));
    await input.close();
    bool starts(List<int> signature, [int offset = 0]) {
      if (header.length < offset + signature.length) return false;
      for (var index = 0; index < signature.length; index++) {
        if (header[offset + index] != signature[index]) return false;
      }
      return true;
    }

    final isJpeg = header.length >= 3 &&
        header[0] == 0xff &&
        header[1] == 0xd8 &&
        header[2] == 0xff;
    final isPng = starts(const [0x89, 0x50, 0x4e, 0x47]);
    final isWebp = starts(const [0x52, 0x49, 0x46, 0x46]) &&
        starts(const [0x57, 0x45, 0x42, 0x50], 8);
    final isPdf = starts(const [0x25, 0x50, 0x44, 0x46]);
    final isZip = starts(const [0x50, 0x4b, 0x03, 0x04]);
    final isOgg = starts(const [0x4f, 0x67, 0x67, 0x53]);
    final isMp3 = starts(const [0x49, 0x44, 0x33]) ||
        (header.length >= 2 && header[0] == 0xff && (header[1] & 0xe0) == 0xe0);
    final isMp4 = header.length >= 12 &&
        header[4] == 0x66 &&
        header[5] == 0x74 &&
        header[6] == 0x79 &&
        header[7] == 0x70;
    final extension = p.extension(path).toLowerCase();
    final result = switch (kind) {
      AttachmentKind.image when isJpeg => 'image/jpeg',
      AttachmentKind.image when isPng => 'image/png',
      AttachmentKind.image when isWebp => 'image/webp',
      AttachmentKind.video when isMp4 => 'video/mp4',
      AttachmentKind.audio || AttachmentKind.voice when isOgg => 'audio/ogg',
      AttachmentKind.audio || AttachmentKind.voice when isMp3 => 'audio/mpeg',
      AttachmentKind.audio || AttachmentKind.voice when isMp4 => 'audio/mp4',
      AttachmentKind.document when isPdf => 'application/pdf',
      AttachmentKind.document when isZip && extension == '.zip' =>
        'application/zip',
      AttachmentKind.document when isZip && extension == '.docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      AttachmentKind.document when isZip && extension == '.xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      AttachmentKind.document when isZip && extension == '.pptx' =>
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      AttachmentKind.document when extension == '.txt' && !header.contains(0) =>
        'text/plain',
      _ => null,
    };
    if (result == null) {
      throw const FormatException('Unsupported or mismatched file type');
    }
    return result;
  }
}
