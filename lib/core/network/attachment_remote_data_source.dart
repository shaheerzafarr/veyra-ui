import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/attachment.dart';
import 'api_client.dart';

class AttachmentTransferCancelled implements Exception {
  const AttachmentTransferCancelled();
}

class AttachmentTransferCancellation {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];
  bool get isCancelled => _cancelled;
  void addListener(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners.toList()) {
      listener();
    }
    _listeners.clear();
  }

  void throwIfCancelled() {
    if (_cancelled) throw const AttachmentTransferCancelled();
  }
}

class AttachmentUploadAuthorization {
  const AttachmentUploadAuthorization({
    required this.attachmentId,
    required this.objectId,
    required this.uploadUrl,
    required this.headers,
  });
  final String attachmentId;
  final String objectId;
  final Uri uploadUrl;
  final Map<String, String> headers;
}

class AttachmentRemoteDataSource {
  AttachmentRemoteDataSource(this._api);
  final ApiClient _api;

  Future<AttachmentUploadAuthorization> createUpload({
    required String attachmentId,
    required String conversationId,
    required String recipientDeviceId,
    required AttachmentKind kind,
    required int encryptedSize,
  }) async {
    final value = await _api.postJson('/attachments', body: {
      'attachment_id': attachmentId,
      'conversation_id': conversationId,
      'recipient_device_id': recipientDeviceId,
      'kind': kind.name,
      'encrypted_size': encryptedSize,
    });
    return AttachmentUploadAuthorization(
      attachmentId: value['attachment_id'] as String,
      objectId: value['object_id'] as String,
      uploadUrl: Uri.parse(value['upload_url'] as String),
      headers: (value['required_headers'] as Map).cast<String, String>(),
    );
  }

  Future<void> uploadCiphertext(
    AttachmentUploadAuthorization authorization,
    String path, {
    void Function(double progress)? onProgress,
    AttachmentTransferCancellation? cancellation,
  }) async {
    final file = File(path);
    final length = await file.length();
    final client = http.Client();
    cancellation?.addListener(client.close);
    try {
      cancellation?.throwIfCancelled();
      final request = http.StreamedRequest('PUT', authorization.uploadUrl)
        ..headers.addAll(authorization.headers)
        ..contentLength = length;
      var sent = 0;
      file.openRead().listen(
        (chunk) {
          if (cancellation?.isCancelled ?? false) {
            request.sink.addError(const AttachmentTransferCancelled());
            return;
          }
          sent += chunk.length;
          request.sink.add(chunk);
          onProgress?.call(sent / length);
        },
        onError: request.sink.addError,
        onDone: request.sink.close,
        cancelOnError: true,
      );
      final response = await client.send(request);
      cancellation?.throwIfCancelled();
      await response.stream.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
            'Ciphertext upload failed (${response.statusCode})');
      }
    } finally {
      client.close();
    }
  }

  Future<void> markUploaded(String attachmentId) =>
      _api.postJson('/attachments/$attachmentId/uploaded').then((_) {});

  Future<void> register(String attachmentId, String messageId) => _api.postJson(
        '/attachments/$attachmentId/registered',
        body: {'message_id': messageId},
      ).then((_) {});

  Future<String> downloadCiphertext(
    String attachmentId, {
    void Function(double progress)? onProgress,
    AttachmentTransferCancellation? cancellation,
  }) async {
    final auth = await _api.postJson('/attachments/$attachmentId/download');
    final uri = Uri.parse(auth['download_url'] as String);
    final expected = auth['encrypted_size'] as int;
    final directory = await getTemporaryDirectory();
    final output =
        File(p.join(directory.path, '${const Uuid().v4()}.ciphertext'));
    final client = http.Client();
    cancellation?.addListener(client.close);
    IOSink? sink;
    try {
      final response = await client.send(http.Request('GET', uri));
      cancellation?.throwIfCancelled();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
            'Ciphertext download failed (${response.statusCode})');
      }
      sink = output.openWrite();
      var received = 0;
      await for (final chunk in response.stream) {
        cancellation?.throwIfCancelled();
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received / expected);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (received != expected) {
        throw const FileSystemException('Ciphertext size mismatch');
      }
      return output.path;
    } catch (_) {
      await sink?.close();
      if (await output.exists()) await output.delete();
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<void> acknowledgeReceived(String attachmentId) =>
      _api.postJson('/attachments/$attachmentId/received').then((_) {});

  Future<void> cancel(String attachmentId) =>
      _api.deleteJson('/attachments/$attachmentId').then((_) {});
}
