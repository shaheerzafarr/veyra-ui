import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veyra/core/models/attachment.dart';

void main() {
  test('attachment descriptor round trips with explicit authenticated version',
      () {
    const descriptor = AttachmentDescriptor(
      attachmentId: '3af2767e-f7cb-4c91-809f-5b789730a268',
      objectId: 'attachments/7d527944-feb1-4a63-9b02-670040b8d15d',
      kind: AttachmentKind.document,
      mimeType: 'application/pdf',
      originalFilename: 'VERY_PRIVATE_FILENAME_39174.pdf',
      plaintextSize: 4096,
      encryptedSize: 4112,
      fileKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      nonce: 'AAAAAAAAAAAAAAAA',
      ciphertextSha256: 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
    );
    final decoded = AttachmentDescriptor.fromJson(
      (jsonDecode(descriptor.encode()) as Map).cast<String, dynamic>(),
    );
    expect(decoded.attachmentId, descriptor.attachmentId);
    expect(decoded.fileKey, descriptor.fileKey);
    expect(decoded.originalFilename, descriptor.originalFilename);
    expect(decoded.toJson()['version'], 1);
    expect((decoded.toJson()['encryption'] as Map)['algorithm'], 'AES-256-GCM');
  });

  test('unsupported protocol version fails closed', () {
    expect(
      () => AttachmentDescriptor.fromJson({
        'version': 2,
      }),
      throwsFormatException,
    );
  });

  test('auto-download policies distinguish Wi-Fi, mobile, and never', () {
    expect(
        allowsAutoDownload(AutoDownloadPolicy.wifi,
            onWifi: true, onMobile: false),
        isTrue);
    expect(
        allowsAutoDownload(AutoDownloadPolicy.wifi,
            onWifi: false, onMobile: true),
        isFalse);
    expect(
        allowsAutoDownload(AutoDownloadPolicy.wifiAndMobile,
            onWifi: false, onMobile: true),
        isTrue);
    expect(
        allowsAutoDownload(AutoDownloadPolicy.never,
            onWifi: true, onMobile: true),
        isFalse);
  });
}
