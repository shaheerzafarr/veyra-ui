import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/network_message_repository.dart';
import '../data/attachment_coordinator.dart';
import '../data/repositories.dart';
import '../models/entities.dart';
import '../models/attachment.dart';
import '../models/public_profile.dart';
import '../network/messaging_socket.dart';

final veyraControllerProvider = ChangeNotifierProvider<VeyraController>(
  (ref) => throw StateError('VeyraController must be provided at the app root'),
);

class VeyraController extends ChangeNotifier {
  VeyraController({
    required UserRepository users,
    required ConversationRepository conversations,
    required MessageRepository messages,
    required ContactRequestRepository requests,
    required SettingsRepository settings,
    AttachmentCoordinator? attachments,
  })  : _users = users,
        _conversations = conversations,
        _messages = messages,
        _requests = requests,
        _attachments = attachments,
        _settingsRepository = settings {
    if (_messages is RealtimeMessageActions) {
      (_messages as RealtimeMessageActions).updates.listen(_onMessagingUpdate);
    }
  }

  final UserRepository _users;
  final ConversationRepository _conversations;
  final MessageRepository _messages;
  final ContactRequestRepository _requests;
  final SettingsRepository _settingsRepository;
  final AttachmentCoordinator? _attachments;

  bool isLoading = true;
  String? errorMessage;
  late AppUser activeUser;
  late AppSettings settings;
  List<AppUser> allUsers = const [];
  List<ConversationSummary> conversationSummaries = const [];
  List<ContactRequestView> incomingRequests = const [];
  List<ContactRequestView> outgoingRequests = const [];
  final Map<String, List<ChatMessage>> _messageCache = {};
  final Map<String, String> typingUsers = {};
  String? _activeConversationId;
  bool realtimeEnabled = false;
  bool _attachmentRecoveryRunning = false;

  MessagingConnectionState get connectionState =>
      _messages is RealtimeMessageActions
          ? (_messages as RealtimeMessageActions).connectionState
          : MessagingConnectionState.offline;

  Future<void> enableRealtime() async {
    if (_messages is! RealtimeMessageActions) return;
    realtimeEnabled = true;
    await (_messages as RealtimeMessageActions).start(activeUser.id);
    await _attachments?.recoverPending();
    notifyListeners();
  }

  Future<void> disableRealtime() async {
    realtimeEnabled = false;
    if (_messages is RealtimeMessageActions) {
      await (_messages as RealtimeMessageActions).stop();
    }
    notifyListeners();
  }

  Future<void> _onMessagingUpdate(MessagingUpdate update) async {
    if (!realtimeEnabled) return;
    if (!_attachmentRecoveryRunning && _attachments != null) {
      _attachmentRecoveryRunning = true;
      try {
        await _attachments.recoverPending();
      } finally {
        _attachmentRecoveryRunning = false;
      }
    }
    if (update.conversationId case final conversationId?) {
      if (_messageCache.containsKey(conversationId)) {
        _messageCache[conversationId] =
            await _messages.getMessages(conversationId, limit: 100);
      }
      if (_activeConversationId == conversationId) {
        await _markConversationRead(conversationId);
      }
      if (update.typingUserId case final userId?) {
        typingUsers[conversationId] = userId;
      } else {
        typingUsers.remove(conversationId);
      }
    } else {
      for (final conversationId in _messageCache.keys.toList()) {
        _messageCache[conversationId] =
            await _messages.getMessages(conversationId, limit: 100);
      }
    }
    conversationSummaries =
        await _conversations.getConversations(activeUser.id);
    notifyListeners();
  }

  Future<void> initialize() async {
    isLoading = true;
    notifyListeners();
    try {
      allUsers = await _users.getUsers();
      final activeId = await _users.getActiveUserId();
      activeUser = allUsers.firstWhere((user) => user.id == activeId);
      await _reloadAccountData();
      errorMessage = null;
    } catch (error) {
      errorMessage = error.toString();
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _reloadAccountData() async {
    if (_users is ConversationSync) {
      await (_users as ConversationSync).syncConversations();
    }
    final results = await Future.wait<Object>([
      _conversations.getConversations(activeUser.id),
      _requests.getIncomingRequests(activeUser.id),
      _requests.getOutgoingRequests(activeUser.id),
      _settingsRepository.getSettings(activeUser.id),
    ]);
    conversationSummaries = results[0] as List<ConversationSummary>;
    incomingRequests = results[1] as List<ContactRequestView>;
    outgoingRequests = results[2] as List<ContactRequestView>;
    settings = results[3] as AppSettings;
    _messageCache.clear();
  }

  Future<void> refresh() async {
    await _reloadAccountData();
    notifyListeners();
  }

  Future<void> switchAccount(String userId) async {
    if (userId == activeUser.id) return;
    isLoading = true;
    notifyListeners();
    await _users.setActiveUserId(userId);
    activeUser = allUsers.firstWhere((user) => user.id == userId);
    await _reloadAccountData();
    isLoading = false;
    notifyListeners();
  }

  Future<List<PublicProfile>> searchProfiles(String query) async {
    final results = await _users.searchUsers(query, activeUser.id);
    return results.map((user) {
      final conversation = conversationWith(user.id);
      final pending = outgoingRequests.any((view) =>
          view.otherUser.id == user.id &&
          view.request.status == ContactRequestStatus.pending);
      return PublicProfile.fromUser(
        user,
        isContact: conversation != null,
        hasPendingRequest: pending,
      );
    }).toList();
  }

  ConversationSummary? conversationWith(String userId) {
    for (final summary in conversationSummaries) {
      if (summary.otherUserId == userId) return summary;
    }
    return null;
  }

  ConversationSummary? conversationById(String id) {
    for (final summary in conversationSummaries) {
      if (summary.conversation.id == id) return summary;
    }
    return null;
  }

  Future<ContactRequest> sendRequest(String recipientId, String message) async {
    final request =
        await _requests.createRequest(activeUser.id, recipientId, message);
    await refresh();
    return request;
  }

  Future<String> acceptRequest(String requestId) async {
    final id = await _requests.acceptRequest(requestId, activeUser.id);
    await refresh();
    return id;
  }

  Future<void> declineRequest(String requestId) async {
    await _requests.changeRequestStatus(
        requestId, activeUser.id, ContactRequestStatus.declined);
    await refresh();
  }

  Future<void> blockRequest(String requestId) async {
    await _requests.changeRequestStatus(
        requestId, activeUser.id, ContactRequestStatus.blocked);
    await refresh();
  }

  Future<void> cancelRequest(String requestId) async {
    await _requests.changeRequestStatus(
        requestId, activeUser.id, ContactRequestStatus.cancelled);
    await refresh();
  }

  Future<List<ChatMessage>> loadMessages(String conversationId,
      {bool force = false}) async {
    final loaded = !force && _messageCache.containsKey(conversationId)
        ? _messageCache[conversationId]!
        : await _messages.getMessages(conversationId, limit: 100);
    await _markConversationRead(conversationId);
    _messageCache[conversationId] = loaded;
    conversationSummaries =
        await _conversations.getConversations(activeUser.id);
    notifyListeners();
    return loaded;
  }

  Future<void> _markConversationRead(String conversationId) async {
    await _conversations.markConversationRead(conversationId, activeUser.id);
    if (_messages is RealtimeMessageActions) {
      await (_messages as RealtimeMessageActions)
          .markConversationRead(conversationId, settings.readReceiptsEnabled);
    }
  }

  void openConversation(String conversationId) {
    _activeConversationId = conversationId;
  }

  void closeConversation(String conversationId) {
    if (_activeConversationId == conversationId) {
      _activeConversationId = null;
    }
  }

  List<ChatMessage> messagesFor(String conversationId) =>
      _messageCache[conversationId] ?? const [];

  Future<void> sendMessage(String conversationId, String content,
      {String? replyToMessageId}) async {
    final message = await _messages.sendTextMessage(
      conversationId,
      activeUser.id,
      content,
      replyToMessageId: replyToMessageId,
    );
    _messageCache.putIfAbsent(conversationId, () => []).add(message);
    conversationSummaries =
        await _conversations.getConversations(activeUser.id);
    notifyListeners();
  }

  Future<void> sendAttachment(
    String conversationId,
    String path,
    AttachmentKind kind, {
    void Function(AttachmentTransferState state, double progress)? onProgress,
    void Function(String attachmentId)? onAttachmentCreated,
    int? durationMilliseconds,
  }) async {
    final attachments = _attachments;
    if (attachments == null) throw StateError('Attachments are unavailable');
    final message = await attachments.sendFile(
      conversationId: conversationId,
      senderId: activeUser.id,
      inputPath: path,
      kind: kind,
      onProgress: onProgress,
      onAttachmentCreated: onAttachmentCreated,
      durationMilliseconds: durationMilliseconds,
    );
    _messageCache.putIfAbsent(conversationId, () => []).add(message);
    notifyListeners();
  }

  Future<LocalAttachment?> attachmentForMessage(String messageId) =>
      _attachments == null
          ? Future.value(null)
          : _attachments.attachmentForMessage(messageId);

  Future<String> downloadAttachment(String attachmentId,
      {void Function(AttachmentTransferState, double)? onProgress}) {
    final attachments = _attachments;
    if (attachments == null) throw StateError('Attachments are unavailable');
    return attachments.download(attachmentId, onProgress: onProgress);
  }

  Future<void> retryAttachment(String attachmentId,
          {void Function(AttachmentTransferState, double)? onProgress}) =>
      _attachments!.retry(attachmentId, onProgress: onProgress);

  Future<void> cancelAttachment(String attachmentId) =>
      _attachments!.cancel(attachmentId);

  Future<AttachmentStorageUsage> attachmentStorageUsage() =>
      _attachments == null
          ? Future.value(const AttachmentStorageUsage(
              images: 0, videos: 0, documents: 0, audioAndVoice: 0))
          : _attachments.storageUsage();

  Future<void> clearAttachmentCache() async {
    await _attachments?.clearCache();
    notifyListeners();
  }

  void setTyping(String conversationId, bool value) {
    if (_messages is RealtimeMessageActions) {
      (_messages as RealtimeMessageActions).typing(conversationId, value);
    }
  }

  void appResumed() {
    if (realtimeEnabled && _messages is NetworkMessageRepository) {
      _messages.appResumed();
    }
  }

  Future<void> appPaused() async {
    if (realtimeEnabled && _messages is NetworkMessageRepository) {
      await _messages.appPaused();
    }
  }

  Future<void> deleteMessage(String conversationId, String messageId) async {
    await _messages.deleteMessage(messageId, activeUser.id);
    await loadMessages(conversationId, force: true);
  }

  Future<void> toggleConversationMuted(String conversationId) async {
    final summary = conversationById(conversationId);
    if (summary == null) return;
    await _conversations.setConversationMuted(
        conversationId, activeUser.id, !summary.isMuted);
    conversationSummaries =
        await _conversations.getConversations(activeUser.id);
    notifyListeners();
  }

  Future<String> createGroup(String name, List<String> memberIds) async {
    final id = await _conversations.createGroup(activeUser.id, name, memberIds);
    await refresh();
    return id;
  }

  Future<List<AppUser>> groupParticipants(String conversationId) =>
      _conversations.getParticipants(conversationId);

  Future<void> addGroupMember(String conversationId, String userId) async {
    await _conversations.addGroupMember(conversationId, activeUser.id, userId);
    notifyListeners();
  }

  Future<void> removeGroupMember(String conversationId, String userId) async {
    await _conversations.removeGroupMember(
        conversationId, activeUser.id, userId);
    notifyListeners();
  }

  Future<void> leaveGroup(String conversationId) async {
    await _conversations.leaveGroup(conversationId, activeUser.id);
    await refresh();
  }

  Future<String?> updateProfile({
    String? displayName,
    String? username,
    String? bio,
    bool? isDiscoverable,
  }) async {
    final normalizedUsername =
        username?.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase();
    if (normalizedUsername != null &&
        !RegExp(r'^[a-z0-9._]{3,30}$').hasMatch(normalizedUsername)) {
      return 'Use 3–30 letters, numbers, dots, or underscores.';
    }
    if (normalizedUsername != null &&
        !await _users.isUsernameAvailable(normalizedUsername, activeUser.id)) {
      return 'That username is already in use.';
    }
    final updated = activeUser.copyWith(
      displayName: displayName,
      username: normalizedUsername,
      bio: bio,
      isDiscoverable: isDiscoverable,
      updatedAt: DateTime.now().toUtc(),
    );
    await _users.updateUser(updated);
    activeUser = updated;
    allUsers = await _users.getUsers();
    notifyListeners();
    return null;
  }

  Future<void> updateSettings(AppSettings value) async {
    settings = value;
    notifyListeners();
    await _settingsRepository.saveSettings(value);
  }
}
