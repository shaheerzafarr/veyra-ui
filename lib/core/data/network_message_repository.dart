import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../models/entities.dart';
import '../models/attachment.dart';
import '../network/attachment_remote_data_source.dart';
import '../network/messaging_socket.dart';
import '../network/remote_data_sources.dart';
import '../../security/e2ee_service.dart';
import '../../security/attachment_crypto_service.dart';
import '../../security/models/e2ee_models.dart';
import '../../security/session_operation_coordinator.dart';
import 'repositories.dart';

class MessagingUpdate {
  const MessagingUpdate({this.conversationId, this.typingUserId});
  final String? conversationId;
  final String? typingUserId;
}

abstract interface class RealtimeMessageActions {
  Stream<MessagingUpdate> get updates;
  Stream<MessagingConnectionState> get connectionStates;
  MessagingConnectionState get connectionState;
  Future<void> start(String userId);
  Future<void> stop();
  Future<void> markConversationRead(String conversationId, bool enabled);
  void typing(String conversationId, bool isTyping);
}

class NetworkMessageRepository
    implements MessageRepository, RealtimeMessageActions {
  NetworkMessageRepository({
    required LocalVeyraRepository local,
    required MessagingSocket socket,
    required Future<String> Function() deviceId,
    required E2eeService e2ee,
    required CryptoRemoteDataSource crypto,
    AttachmentRemoteDataSource? attachments,
    AttachmentCryptoService? attachmentCrypto,
    required bool allowDevelopmentPlaintextTransport,
  })  : _local = local,
        _socket = socket,
        _deviceId = deviceId,
        _e2ee = e2ee,
        _crypto = crypto,
        _attachments = attachments,
        _attachmentCrypto = attachmentCrypto,
        _allowDevelopmentPlaintextTransport =
            allowDevelopmentPlaintextTransport {
    _eventSubscription = _socket.events.listen(_handleEvent);
    _stateSubscription = _socket.states.listen(_handleState);
  }

  final LocalVeyraRepository _local;
  final MessagingSocket _socket;
  final Future<String> Function() _deviceId;
  final E2eeService _e2ee;
  final CryptoRemoteDataSource _crypto;
  final AttachmentRemoteDataSource? _attachments;
  final AttachmentCryptoService? _attachmentCrypto;
  final SessionOperationCoordinator _sessionOperations =
      SessionOperationCoordinator();
  final bool _allowDevelopmentPlaintextTransport;
  final _updates = StreamController<MessagingUpdate>.broadcast();
  final Map<String, Timer> _acceptanceTimers = {};
  late final StreamSubscription<Map<String, dynamic>> _eventSubscription;
  late final StreamSubscription<MessagingConnectionState> _stateSubscription;
  String? _activeUserId;
  DeviceAddress? _localAddress;
  bool _e2eeReady = false;

  @override
  Stream<MessagingUpdate> get updates => _updates.stream;
  @override
  Stream<MessagingConnectionState> get connectionStates => _socket.states;
  @override
  MessagingConnectionState get connectionState => _socket.state;

  @override
  Future<void> start(String userId) async {
    _activeUserId = userId;
    await _socket.connect();
    await _retryOutbox();
  }

  @override
  Future<void> stop() async {
    _activeUserId = null;
    _localAddress = null;
    _e2eeReady = false;
    for (final timer in _acceptanceTimers.values) {
      timer.cancel();
    }
    _acceptanceTimers.clear();
    await _socket.disconnect();
  }

  @override
  Future<List<ChatMessage>> getMessages(String conversationId,
          {int limit = 100, int offset = 0}) =>
      _local.getMessages(conversationId, limit: limit, offset: offset);

  @override
  Future<ChatMessage> sendTextMessage(
    String conversationId,
    String senderId,
    String content, {
    String? replyToMessageId,
  }) async {
    if (_activeUserId == null) {
      return _local.sendTextMessage(conversationId, senderId, content,
          replyToMessageId: replyToMessageId);
    }
    final message = await _local.createOutgoingMessage(
      conversationId,
      senderId,
      await _deviceId(),
      content,
      replyToMessageId: replyToMessageId,
    );
    await _submit(message);
    return message;
  }

  Future<ChatMessage> sendAttachmentDescriptor(
    String conversationId,
    String senderId,
    AttachmentDescriptor descriptor,
  ) async {
    if (_activeUserId == null || !_e2eeReady || _localAddress == null) {
      throw StateError('Secure messaging is unavailable');
    }
    final message = await _local.createOutgoingAttachmentMessage(
      conversationId,
      senderId,
      await _deviceId(),
      descriptor,
    );
    await sendPreparedAttachment(message, descriptor);
    return message;
  }

  Future<ChatMessage> stageAttachment({
    required String attachmentId,
    required String conversationId,
    required String senderId,
    required AttachmentKind kind,
    required String mimeType,
    required String originalFilename,
    required int plaintextSize,
    required String sourcePath,
  }) async {
    if (_activeUserId == null || !_e2eeReady || _localAddress == null) {
      throw StateError('Secure messaging is unavailable');
    }
    return _local.stageOutgoingAttachment(
      attachmentId: attachmentId,
      conversationId: conversationId,
      senderId: senderId,
      senderDeviceId: await _deviceId(),
      kind: kind,
      mimeType: mimeType,
      originalFilename: originalFilename,
      plaintextSize: plaintextSize,
      sourcePath: sourcePath,
    );
  }

  Future<void> sendPreparedAttachment(
      ChatMessage message, AttachmentDescriptor descriptor) async {
    if (_activeUserId == null || !_e2eeReady || _localAddress == null) {
      throw StateError('Secure messaging is unavailable');
    }
    await _attachmentCrypto?.storeSecret(
        descriptor.attachmentId, descriptor.encode());
    await _local.updateAttachmentState(
        descriptor.attachmentId, AttachmentTransferState.descriptorPending,
        progress: 1);
    await _e2eeAttachment(message, descriptor);
  }

  Future<void> retryAttachmentMessage(String messageId) async {
    final message = await _local.getMessage(messageId);
    if (message == null) throw StateError('Attachment message is unavailable');
    await _submit(message);
  }

  Future<void> _e2eeAttachment(
      ChatMessage message, AttachmentDescriptor descriptor) async {
    await _local.updateAttachmentState(
        descriptor.attachmentId, AttachmentTransferState.sending,
        progress: 1);
    final conversation = await _local.getConversation(message.conversationId);
    final recipientDeviceId = conversation?.remoteDeviceId;
    if (recipientDeviceId == null || _localAddress == null) {
      throw StateError('Recipient device is unavailable');
    }
    final participants = await _local.getParticipants(message.conversationId);
    final recipientUserId = participants
        .map((user) => user.id)
        .firstWhere((id) => id != _activeUserId);
    final remote = DeviceAddress(
      userId: recipientUserId,
      deviceId: recipientDeviceId,
    );
    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode({
      'type': 'attachment',
      'descriptor': descriptor.toJson(),
      'message_id': message.id,
      'conversation_id': message.conversationId,
      'sender_user_id': _activeUserId,
      'sender_device_id': _localAddress!.deviceId,
      'recipient_user_id': recipientUserId,
      'recipient_device_id': recipientDeviceId,
      'client_created_at': message.createdAt.toUtc().toIso8601String(),
    })));
    try {
      final envelope = await _sessionOperations.synchronized(remote, () async {
        if (!await _e2ee.hasSession(remote)) {
          await _e2ee.establishSession(
              remote, await _crypto.fetchBundle(remote));
        }
        return _e2ee.encrypt(
          messageId: message.id,
          conversationId: message.conversationId,
          sender: _localAddress!,
          recipient: remote,
          plaintext: plaintext,
        );
      });
      final transport = <String, dynamic>{
        'message_id': envelope.messageId,
        'conversation_id': envelope.conversationId,
        'recipient_device_id': envelope.recipient.deviceId,
        'transport_security': 'e2ee',
        'protocol_version': envelope.protocolVersion,
        'message_type': envelope.messageType,
        'ciphertext': base64Encode(envelope.ciphertext),
        'client_created_at': message.createdAt.toUtc().toIso8601String(),
      };
      await _local.persistEncryptedEnvelope(message.id, jsonEncode(transport));
      await _sendEncryptedEnvelope(message, transport);
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }

  Future<void> _submit(ChatMessage message) async {
    if (message.encryptedEnvelope case final stored?) {
      await _sendEncryptedEnvelope(message, jsonDecode(stored));
      return;
    }
    if (!_e2eeReady || _localAddress == null) {
      await _local.updateDeliveryStatus(message.id, DeliveryStatus.failed);
      _updates.add(MessagingUpdate(conversationId: message.conversationId));
      return;
    }
    if (message.type != MessageType.text) {
      final attachment = await _local.getAttachmentForMessage(message.id);
      if (attachment == null ||
          !const {
            AttachmentTransferState.descriptorPending,
            AttachmentTransferState.sending,
          }.contains(attachment.transferState)) {
        return;
      }
      try {
        final secret =
            await _attachmentCrypto?.readSecret(attachment.attachmentId);
        if (secret == null) throw StateError('Attachment key unavailable');
        final descriptor = AttachmentDescriptor.fromJson(
            (jsonDecode(secret) as Map).cast<String, dynamic>());
        await _e2eeAttachment(message, descriptor);
      } catch (_) {
        await _local.updateAttachmentState(
            attachment.attachmentId, AttachmentTransferState.failed,
            failureCode: 'descriptor_encryption_failed');
      }
      return;
    }
    final conversation = await _local.getConversation(message.conversationId);
    final recipientDeviceId = conversation?.remoteDeviceId;
    if (recipientDeviceId == null) {
      await _local.updateDeliveryStatus(message.id, DeliveryStatus.failed);
      _updates.add(MessagingUpdate(conversationId: message.conversationId));
      return;
    }
    final activeUserId = _activeUserId!;
    final participants = await _local.getParticipants(message.conversationId);
    final recipientUserId = participants
        .map((user) => user.id)
        .firstWhere((id) => id != activeUserId);
    final remote = DeviceAddress(
      userId: recipientUserId,
      deviceId: recipientDeviceId,
    );
    final envelope = await _sessionOperations.synchronized(remote, () async {
      if (!await _e2ee.hasSession(remote)) {
        await _e2ee.establishSession(remote, await _crypto.fetchBundle(remote));
      }
      final inner = utf8.encode(jsonEncode({
        'type': 'text',
        'body': message.content,
        'reply_to': message.replyToMessageId,
        'client_created_at': message.createdAt.toUtc().toIso8601String(),
        'message_id': message.id,
        'conversation_id': message.conversationId,
        'sender_user_id': activeUserId,
        'sender_device_id': _localAddress!.deviceId,
        'recipient_user_id': recipientUserId,
        'recipient_device_id': recipientDeviceId,
      }));
      return _e2ee.encrypt(
        messageId: message.id,
        conversationId: message.conversationId,
        sender: _localAddress!,
        recipient: remote,
        plaintext: Uint8List.fromList(inner),
      );
    });
    final transport = <String, dynamic>{
      'message_id': envelope.messageId,
      'conversation_id': envelope.conversationId,
      'recipient_device_id': envelope.recipient.deviceId,
      'transport_security': 'e2ee',
      'protocol_version': envelope.protocolVersion,
      'message_type': envelope.messageType,
      'ciphertext': base64Encode(envelope.ciphertext),
      'client_created_at': message.createdAt.toUtc().toIso8601String(),
    };
    await _local.persistEncryptedEnvelope(message.id, jsonEncode(transport));
    await _sendEncryptedEnvelope(message, transport);
  }

  Future<void> _sendEncryptedEnvelope(
      ChatMessage message, Map<String, dynamic> transport) async {
    final sent = _socket.send('message.send', transport);
    if (!sent) return;
    _acceptanceTimers[message.id]?.cancel();
    _acceptanceTimers[message.id] = Timer(const Duration(seconds: 8), () async {
      final count = await _local.incrementRetry(
        message.id,
        DateTime.now().toUtc().add(
            Duration(seconds: min(32, 1 << min(5, _acceptanceTimers.length)))),
      );
      if (count >= 5) {
        await _local.updateDeliveryStatus(message.id, DeliveryStatus.failed);
        _updates.add(MessagingUpdate(conversationId: message.conversationId));
      } else {
        await _sendEncryptedEnvelope(message, transport);
      }
    });
  }

  Future<void> _retryOutbox() async {
    if (_socket.state != MessagingConnectionState.connected) return;
    for (final message in await _local.pendingOutgoingMessages()) {
      await _submit(message);
    }
    for (final attachment in await _local.recoverableAttachments()) {
      final message = await _local.getMessage(attachment.messageId);
      if (message?.deliveryStatus == DeliveryStatus.sent &&
          attachment.transferState ==
              AttachmentTransferState.descriptorPending) {
        await _registerAttachment(attachment, message!.id);
      }
    }
    _socket.send('sync.request', const {});
  }

  Future<void> _handleEvent(Map<String, dynamic> event) async {
    final type = event['type'] as String?;
    final payload =
        (event['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    if (type == 'connection.ready') {
      await _prepareE2ee(payload);
      await _retryOutbox();
      return;
    }
    if (type == 'message.accepted') {
      final id = payload['message_id'] as String;
      _acceptanceTimers.remove(id)?.cancel();
      await _local.updateDeliveryStatus(
        id,
        DeliveryStatus.sent,
        serverReceivedAt:
            DateTime.parse(payload['server_received_at'] as String),
      );
      final attachment = await _local.getAttachmentForMessage(id);
      if (attachment != null) {
        await _registerAttachment(attachment, id);
      }
      _updates.add(const MessagingUpdate());
      return;
    }
    if (type == 'message.failed') {
      final id = payload['message_id'] as String?;
      if (id != null) {
        _acceptanceTimers.remove(id)?.cancel();
        await _local.updateDeliveryStatus(id, DeliveryStatus.failed);
        _updates.add(const MessagingUpdate());
      }
      return;
    }
    if (type == 'message.new') {
      if (payload['transport_security'] == 'e2ee') {
        await _handleEncryptedIncoming(payload);
        return;
      }
      if (!_allowDevelopmentPlaintextTransport ||
          payload['transport_security'] != _developmentOnlyPlaintextTransport) {
        return;
      }
      final message = ChatMessage(
        id: payload['message_id'] as String,
        conversationId: payload['conversation_id'] as String,
        senderUserId: payload['sender_user_id'] as String,
        senderDeviceId: payload['sender_device_id'] as String?,
        type: MessageType.text,
        content: payload['content'] as String,
        replyToMessageId: payload['reply_to_message_id'] as String?,
        createdAt: DateTime.parse(payload['client_created_at'] as String),
        updatedAt: DateTime.parse(payload['server_received_at'] as String),
        serverReceivedAt:
            DateTime.parse(payload['server_received_at'] as String),
        deliveryStatus: DeliveryStatus.delivered,
      );
      final activeUserId = _activeUserId;
      if (activeUserId == null) return;
      await _local.ensureDirectConversation(
        message.conversationId,
        activeUserId,
        message.senderUserId,
        message.serverReceivedAt!,
        remoteDeviceId: message.senderDeviceId,
      );
      await _local.persistIncomingMessage(message);
      // Durable ACK is deliberately sent only after the SQLite transaction.
      _socket.send('message.delivered', {'message_id': message.id});
      _updates.add(MessagingUpdate(conversationId: message.conversationId));
      return;
    }
    if (type == 'message.delivered' || type == 'message.read') {
      final id = payload['message_id'] as String;
      await _local.updateDeliveryStatus(
        id,
        type == 'message.read' ? DeliveryStatus.read : DeliveryStatus.delivered,
      );
      _updates.add(const MessagingUpdate());
      return;
    }
    if (type == 'typing.start' || type == 'typing.stop') {
      _updates.add(MessagingUpdate(
        conversationId: payload['conversation_id'] as String?,
        typingUserId:
            type == 'typing.start' ? payload['user_id'] as String? : null,
      ));
    }
  }

  Future<void> _registerAttachment(
      LocalAttachment attachment, String messageId) async {
    if (_attachments == null) return;
    try {
      await _attachments.register(attachment.attachmentId, messageId);
      final ciphertextPath = attachment.ciphertextPath;
      if (ciphertextPath != null) {
        await _attachmentCrypto?.deletePrivateFile(ciphertextPath);
      }
      await _local.updateAttachmentState(
          attachment.attachmentId, AttachmentTransferState.sent,
          clearCiphertextPath: true);
    } catch (_) {
      await _local.updateAttachmentState(
        attachment.attachmentId,
        AttachmentTransferState.descriptorPending,
        failureCode: 'descriptor_registration_failed',
      );
    }
  }

  static const _developmentOnlyPlaintextTransport = 'development_plaintext';

  Future<void> _prepareE2ee(Map<String, dynamic> payload) async {
    final userId = _activeUserId;
    final deviceId = payload['device_id'] as String?;
    if (userId == null || deviceId == null) return;
    final local = DeviceAddress(userId: userId, deviceId: deviceId);
    await _e2ee.initialize(local);
    final bundle = await _e2ee.getPublicBundle();
    await _crypto.publish(bundle);
    await _e2ee.markPreKeysPublished(
        bundle.oneTimePreKeys.map((key) => key.preKeyId).toList());
    final available = await _crypto.availablePreKeyCount();
    if (available < _preKeyReplenishmentThreshold) {
      await _e2ee.replenishPreKeys(_preKeyTarget - available);
      final replenishment = await _e2ee.getPublicBundle();
      await _crypto.publish(replenishment);
      await _e2ee.markPreKeysPublished(
        replenishment.oneTimePreKeys.map((key) => key.preKeyId).toList(),
      );
    }
    _localAddress = local;
    _e2eeReady = true;
  }

  static const _preKeyReplenishmentThreshold = 20;
  static const _preKeyTarget = 50;

  Future<void> _handleEncryptedIncoming(Map<String, dynamic> payload) async {
    final local = _localAddress;
    final activeUserId = _activeUserId;
    if (!_e2eeReady || local == null || activeUserId == null) return;
    final messageId = payload['message_id'] as String;
    if (await _local.hasMessage(messageId)) {
      _socket.send('message.delivered', {'message_id': messageId});
      return;
    }
    final sender = DeviceAddress(
      userId: payload['sender_user_id'] as String,
      deviceId: payload['sender_device_id'] as String,
    );
    if (payload['recipient_user_id'] != activeUserId ||
        payload['recipient_device_id'] != local.deviceId) {
      return;
    }
    final envelope = EncryptedEnvelope(
      version: 1,
      messageId: messageId,
      conversationId: payload['conversation_id'] as String,
      sender: sender,
      recipient: local,
      protocolVersion: payload['protocol_version'] as int,
      messageType: payload['message_type'] as String,
      ciphertext: base64Decode(payload['ciphertext'] as String),
    );
    final decrypted = await _sessionOperations.synchronized(
      sender,
      () => _e2ee.decrypt(envelope),
    );
    final inner = jsonDecode(utf8.decode(decrypted.plaintext));
    if (inner is! Map<String, dynamic> ||
        !const {'text', 'attachment'}.contains(inner['type']) ||
        inner['message_id'] != messageId ||
        inner['conversation_id'] != envelope.conversationId ||
        inner['sender_user_id'] != sender.userId ||
        inner['sender_device_id'] != sender.deviceId ||
        inner['recipient_user_id'] != activeUserId ||
        inner['recipient_device_id'] != local.deviceId) {
      return;
    }
    final receivedAt = DateTime.parse(payload['server_received_at'] as String);
    final isAttachment = inner['type'] == 'attachment';
    final descriptor = isAttachment
        ? AttachmentDescriptor.fromJson(
            (inner['descriptor'] as Map).cast<String, dynamic>())
        : null;
    final message = ChatMessage(
      id: messageId,
      conversationId: envelope.conversationId,
      senderUserId: sender.userId,
      senderDeviceId: sender.deviceId,
      type: descriptor == null
          ? MessageType.text
          : MessageType.values.byName(descriptor.kind.name),
      content: descriptor?.originalFilename ?? inner['body'] as String,
      replyToMessageId: inner['reply_to'] as String?,
      createdAt: DateTime.parse(inner['client_created_at'] as String),
      updatedAt: receivedAt,
      serverReceivedAt: receivedAt,
      deliveryStatus: DeliveryStatus.delivered,
    );
    await _local.ensureDirectConversation(
      message.conversationId,
      activeUserId,
      sender.userId,
      receivedAt,
      remoteDeviceId: sender.deviceId,
    );
    if (descriptor == null) {
      await _local.persistIncomingMessage(message);
    } else {
      await _attachmentCrypto?.storeSecret(
          descriptor.attachmentId, descriptor.encode());
      await _local.persistIncomingAttachment(message, descriptor);
    }
    _socket.send('message.delivered', {'message_id': message.id});
    _updates.add(MessagingUpdate(conversationId: message.conversationId));
  }

  void _handleState(MessagingConnectionState state) {
    _updates.add(const MessagingUpdate());
    if (state == MessagingConnectionState.connected) _retryOutbox();
  }

  @override
  Future<void> markConversationRead(String conversationId, bool enabled) async {
    if (!enabled) return;
    final userId = _activeUserId;
    if (userId == null) return;
    final messages = await _local.getMessages(conversationId);
    for (final message in messages.where((item) =>
        item.senderUserId != userId &&
        item.deliveryStatus == DeliveryStatus.delivered)) {
      _socket.send('message.read', {'message_id': message.id});
    }
  }

  @override
  void typing(String conversationId, bool isTyping) {
    _socket.send(isTyping ? 'typing.start' : 'typing.stop',
        {'conversation_id': conversationId});
  }

  void appResumed() => _socket.appResumed();
  Future<void> appPaused() => _socket.appPaused();

  @override
  Future<void> deleteMessage(String messageId, String requesterId) =>
      _local.deleteMessage(messageId, requesterId);

  Future<void> dispose() async {
    await stop();
    await _eventSubscription.cancel();
    await _stateSubscription.cancel();
    await _updates.close();
  }
}
