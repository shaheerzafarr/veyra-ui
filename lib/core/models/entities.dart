enum ConversationType { direct, group }

enum ParticipantRole { member, admin, owner }

enum MessageType { text, image, video, document, audio, voice, system }

enum DeliveryStatus { sending, sent, delivered, read, failed }

enum ContactRequestStatus { pending, accepted, declined, blocked, cancelled }

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    required this.avatarColor,
    required this.isDiscoverable,
    required this.createdAt,
    required this.updatedAt,
    this.avatar,
    this.bio,
  });

  final String id;
  final String email;
  final String username;
  final String displayName;
  final String? avatar;
  final int avatarColor;
  final String? bio;
  final bool isDiscoverable;
  final DateTime createdAt;
  final DateTime updatedAt;

  AppUser copyWith({
    String? username,
    String? displayName,
    String? avatar,
    int? avatarColor,
    String? bio,
    bool? isDiscoverable,
    DateTime? updatedAt,
  }) =>
      AppUser(
        id: id,
        email: email,
        username: username ?? this.username,
        displayName: displayName ?? this.displayName,
        avatar: avatar ?? this.avatar,
        avatarColor: avatarColor ?? this.avatarColor,
        bio: bio ?? this.bio,
        isDiscoverable: isDiscoverable ?? this.isDiscoverable,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class Conversation {
  const Conversation({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
    this.title,
    this.avatar,
    this.lastMessageAt,
  });

  final String id;
  final ConversationType type;
  final String? title;
  final String? avatar;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastMessageAt;
}

class ConversationSummary {
  const ConversationSummary({
    required this.conversation,
    required this.displayName,
    required this.avatarColor,
    required this.unreadCount,
    required this.isPinned,
    required this.isMuted,
    this.otherUserId,
    this.lastMessage,
    this.lastMessageSenderName,
  });

  final Conversation conversation;
  final String displayName;
  final int avatarColor;
  final String? otherUserId;
  final String? lastMessage;
  final String? lastMessageSenderName;
  final int unreadCount;
  final bool isPinned;
  final bool isMuted;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderUserId,
    required this.type,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.deliveryStatus,
    this.senderDeviceId,
    this.serverReceivedAt,
    this.replyToMessageId,
    this.isEdited = false,
    this.isDeleted = false,
  });

  final String id;
  final String conversationId;
  final String senderUserId;
  final String? senderDeviceId;
  final MessageType type;
  final String content;
  final String? replyToMessageId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? serverReceivedAt;
  final DeliveryStatus deliveryStatus;
  final bool isEdited;
  final bool isDeleted;
}

class ContactRequest {
  const ContactRequest({
    required this.id,
    required this.senderUserId,
    required this.recipientUserId,
    required this.introductoryMessage,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String senderUserId;
  final String recipientUserId;
  final String introductoryMessage;
  final ContactRequestStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class ContactRequestView {
  const ContactRequestView({required this.request, required this.otherUser});
  final ContactRequest request;
  final AppUser otherUser;
}

class AppSettings {
  const AppSettings({
    required this.userId,
    this.theme = 'dark',
    this.notificationsEnabled = true,
    this.callNotificationsEnabled = true,
    this.readReceiptsEnabled = true,
    this.profilePhotoVisibility = 'everyone',
    this.requestAudience = 'everyone',
    this.wifiOnlyDownloads = false,
    this.fontScale = 1,
  });

  final String userId;
  final String theme;
  final bool notificationsEnabled;
  final bool callNotificationsEnabled;
  final bool readReceiptsEnabled;
  final String profilePhotoVisibility;
  final String requestAudience;
  final bool wifiOnlyDownloads;
  final double fontScale;

  AppSettings copyWith({
    String? theme,
    bool? notificationsEnabled,
    bool? callNotificationsEnabled,
    bool? readReceiptsEnabled,
    String? profilePhotoVisibility,
    String? requestAudience,
    bool? wifiOnlyDownloads,
    double? fontScale,
  }) =>
      AppSettings(
        userId: userId,
        theme: theme ?? this.theme,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        callNotificationsEnabled:
            callNotificationsEnabled ?? this.callNotificationsEnabled,
        readReceiptsEnabled: readReceiptsEnabled ?? this.readReceiptsEnabled,
        profilePhotoVisibility:
            profilePhotoVisibility ?? this.profilePhotoVisibility,
        requestAudience: requestAudience ?? this.requestAudience,
        wifiOnlyDownloads: wifiOnlyDownloads ?? this.wifiOnlyDownloads,
        fontScale: fontScale ?? this.fontScale,
      );
}
