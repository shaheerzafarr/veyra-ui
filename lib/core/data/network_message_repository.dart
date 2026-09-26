import 'dart:async';
import 'dart:math';

import '../models/entities.dart';
import '../network/messaging_socket.dart';
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
  })  : _local = local,
        _socket = socket,
        _deviceId = deviceId {
    _eventSubscription = _socket.events.listen(_handleEvent);
    _stateSubscription = _socket.states.listen(_handleState);
  }

  final LocalVeyraRepository _local;
  final MessagingSocket _socket;
  final Future<String> Function() _deviceId;
  final _updates = StreamController<MessagingUpdate>.broadcast();
  final Map<String, Timer> _acceptanceTimers = {};
  late final StreamSubscription<Map<String, dynamic>> _eventSubscription;
  late final StreamSubscription<MessagingConnectionState> _stateSubscription;
  String? _activeUserId;

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

  Future<void> _submit(ChatMessage message) async {
    final sent = _socket.send('message.send', {
      'message_id': message.id,
      'conversation_id': message.conversationId,
      'type': 'text',
      'content': message.content,
      'client_created_at': message.createdAt.toUtc().toIso8601String(),
      'reply_to_message_id': message.replyToMessageId,
    });
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
        await _submit(message);
      }
    });
  }

  Future<void> _retryOutbox() async {
    if (_socket.state != MessagingConnectionState.connected) return;
    for (final message in await _local.pendingOutgoingMessages()) {
      await _submit(message);
    }
    _socket.send('sync.request', const {});
  }

  Future<void> _handleEvent(Map<String, dynamic> event) async {
    final type = event['type'] as String?;
    final payload =
        (event['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    if (type == 'connection.ready') {
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
