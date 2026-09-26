import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/entities.dart';
import 'local_database.dart';

abstract interface class UserRepository {
  Future<List<AppUser>> getUsers();
  Future<AppUser> getUser(String id);
  Future<String> getActiveUserId();
  Future<void> setActiveUserId(String id);
  Future<List<AppUser>> searchUsers(String query, String activeUserId);
  Future<void> updateUser(AppUser user);
  Future<bool> isUsernameAvailable(String username, String exceptUserId);
}

abstract interface class ConversationRepository {
  Future<List<ConversationSummary>> getConversations(String userId);
  Future<Conversation?> getConversation(String id);
  Future<String> createGroup(
      String ownerId, String title, List<String> members);
  Future<List<AppUser>> getParticipants(String conversationId);
  Future<void> addGroupMember(
      String conversationId, String actorId, String userId);
  Future<void> removeGroupMember(
      String conversationId, String actorId, String userId);
  Future<void> markConversationRead(String conversationId, String userId);
  Future<void> setConversationMuted(
      String conversationId, String userId, bool isMuted);
  Future<void> leaveGroup(String conversationId, String userId);
}

abstract interface class MessageRepository {
  Future<List<ChatMessage>> getMessages(String conversationId,
      {int limit = 100, int offset = 0});
  Future<ChatMessage> sendTextMessage(
      String conversationId, String senderId, String content,
      {String? replyToMessageId});
  Future<void> deleteMessage(String messageId, String requesterId);
}

abstract interface class ContactRequestRepository {
  Future<List<ContactRequestView>> getIncomingRequests(String userId);
  Future<List<ContactRequestView>> getOutgoingRequests(String userId);
  Future<ContactRequest?> getRequestBetween(String firstId, String secondId);
  Future<ContactRequest> createRequest(
      String senderId, String recipientId, String message);
  Future<String> acceptRequest(String requestId, String recipientId);
  Future<void> changeRequestStatus(
      String requestId, String actorId, ContactRequestStatus status);
}

abstract interface class SettingsRepository {
  Future<AppSettings> getSettings(String userId);
  Future<void> saveSettings(AppSettings settings);
}

class LocalVeyraRepository
    implements
        UserRepository,
        ConversationRepository,
        MessageRepository,
        ContactRequestRepository,
        SettingsRepository {
  LocalVeyraRepository(this._localDatabase, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final VeyraDatabase _localDatabase;
  final Uuid _uuid;

  Future<Database> get _db => _localDatabase.database;

  @override
  Future<List<AppUser>> getUsers() async {
    final rows = await (await _db)
        .query('users', orderBy: 'display_name COLLATE NOCASE');
    return rows.map(_userFromRow).toList();
  }

  @override
  Future<AppUser> getUser(String id) async {
    final rows =
        await (await _db).query('users', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) throw StateError('User not found: $id');
    return _userFromRow(rows.single);
  }

  @override
  Future<String> getActiveUserId() async {
    final rows = await (await _db).query('app_state',
        columns: ['value'], where: 'key = ?', whereArgs: ['active_user_id']);
    if (rows.isEmpty) throw StateError('No active development account');
    return rows.single['value']! as String;
  }

  @override
  Future<void> setActiveUserId(String id) async {
    await (await _db).insert(
      'app_state',
      {'key': 'active_user_id', 'value': id},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<AppUser>> searchUsers(String query, String activeUserId) async {
    final normalized =
        query.trim().toLowerCase().replaceFirst(RegExp(r'^@'), '');
    final db = await _db;
    final rows = normalized.isEmpty
        ? await db.query('users',
            where: 'is_discoverable = 1 AND id != ?',
            whereArgs: [activeUserId],
            orderBy: 'display_name COLLATE NOCASE',
            limit: 20)
        : await db.query('users',
            where: '''is_discoverable = 1 AND id != ? AND
              (lower(display_name) LIKE ? OR lower(username) LIKE ?)''',
            whereArgs: [activeUserId, '%$normalized%', '%$normalized%'],
            orderBy: 'display_name COLLATE NOCASE',
            limit: 50);
    return rows.map(_userFromRow).toList();
  }

  @override
  Future<void> updateUser(AppUser user) async {
    final count = await (await _db).update(
      'users',
      {
        'username': user.username.trim().replaceFirst(RegExp(r'^@'), ''),
        'display_name': user.displayName.trim(),
        'avatar': user.avatar,
        'avatar_color': user.avatarColor,
        'bio': user.bio?.trim(),
        'is_discoverable': user.isDiscoverable ? 1 : 0,
        'updated_at': user.updatedAt.toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [user.id],
    );
    if (count != 1) throw StateError('User update failed');
  }

  @override
  Future<bool> isUsernameAvailable(String username, String exceptUserId) async {
    final normalized =
        username.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase();
    final result = await (await _db).rawQuery(
      'SELECT COUNT(*) count FROM users WHERE lower(username) = ? AND id != ?',
      [normalized, exceptUserId],
    );
    return Sqflite.firstIntValue(result) == 0;
  }

  @override
  Future<List<ConversationSummary>> getConversations(String userId) async {
    final rows = await (await _db).rawQuery('''
      SELECT c.*, s.is_pinned, s.is_muted, s.last_read_at,
        CASE WHEN c.type = 'group' THEN c.title ELSE other.display_name END display_name,
        CASE WHEN c.type = 'group' THEN 0xFF4E4667 ELSE other.avatar_color END avatar_color,
        CASE WHEN c.type = 'direct' THEN other.id END other_user_id,
        lm.content last_message,
        sender.display_name last_message_sender_name,
        (SELECT COUNT(*) FROM messages unread
          WHERE unread.conversation_id = c.id
            AND unread.sender_user_id != ?
            AND unread.is_deleted = 0
            AND (s.last_read_at IS NULL OR unread.created_at > s.last_read_at)
        ) unread_count
      FROM conversations c
      JOIN conversation_participants mine
        ON mine.conversation_id = c.id AND mine.user_id = ?
      LEFT JOIN conversation_user_state s
        ON s.conversation_id = c.id AND s.user_id = ?
      LEFT JOIN conversation_participants op
        ON op.conversation_id = c.id AND op.user_id != ? AND c.type = 'direct'
      LEFT JOIN users other ON other.id = op.user_id
      LEFT JOIN messages lm ON lm.id = (
        SELECT id FROM messages
        WHERE conversation_id = c.id AND is_deleted = 0
        ORDER BY created_at DESC LIMIT 1
      )
      LEFT JOIN users sender ON sender.id = lm.sender_user_id
      ORDER BY COALESCE(c.last_message_at, c.created_at) DESC
    ''', [userId, userId, userId, userId]);
    return rows.map((row) {
      final conversation = _conversationFromRow(row);
      return ConversationSummary(
        conversation: conversation,
        displayName: (row['display_name'] as String?) ?? 'Conversation',
        avatarColor: (row['avatar_color'] as int?) ?? 0xFF4E4667,
        otherUserId: row['other_user_id'] as String?,
        lastMessage: row['last_message'] as String?,
        lastMessageSenderName: row['last_message_sender_name'] as String?,
        unreadCount: (row['unread_count'] as int?) ?? 0,
        isPinned: row['is_pinned'] == 1,
        isMuted: row['is_muted'] == 1,
      );
    }).toList();
  }

  @override
  Future<Conversation?> getConversation(String id) async {
    final rows = await (await _db)
        .query('conversations', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _conversationFromRow(rows.single);
  }

  @override
  Future<String> createGroup(
      String ownerId, String title, List<String> members) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await (await _db).transaction((txn) async {
      await txn.insert('conversations', {
        'id': id,
        'type': 'group',
        'title': title.trim(),
        'created_at': now,
        'updated_at': now,
      });
      final unique = <String>{ownerId, ...members};
      for (final userId in unique) {
        await txn.insert('conversation_participants', {
          'conversation_id': id,
          'user_id': userId,
          'role': userId == ownerId ? 'owner' : 'member',
          'joined_at': now,
        });
        await txn.insert('conversation_user_state', {
          'conversation_id': id,
          'user_id': userId,
          'last_read_at': now,
        });
      }
      await txn.insert('messages', {
        'id': _uuid.v4(),
        'conversation_id': id,
        'sender_user_id': ownerId,
        'type': 'system',
        'content': 'Group created',
        'created_at': now,
        'updated_at': now,
        'delivery_status': 'read',
      });
    });
    return id;
  }

  @override
  Future<List<AppUser>> getParticipants(String conversationId) async {
    final rows = await (await _db).rawQuery('''
      SELECT u.* FROM users u
      JOIN conversation_participants p ON p.user_id = u.id
      WHERE p.conversation_id = ?
      ORDER BY CASE p.role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 ELSE 2 END,
        u.display_name COLLATE NOCASE
    ''', [conversationId]);
    return rows.map(_userFromRow).toList();
  }

  Future<void> _requireGroupManager(
      DatabaseExecutor db, String conversationId, String actorId) async {
    final rows = await db.rawQuery('''
      SELECT p.role FROM conversation_participants p
      JOIN conversations c ON c.id = p.conversation_id
      WHERE p.conversation_id = ? AND p.user_id = ? AND c.type = 'group'
    ''', [conversationId, actorId]);
    if (rows.isEmpty || !{'owner', 'admin'}.contains(rows.single['role'])) {
      throw StateError('Only group owners and admins can manage members');
    }
  }

  @override
  Future<void> addGroupMember(
      String conversationId, String actorId, String userId) async {
    final db = await _db;
    await _requireGroupManager(db, conversationId, actorId);
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      await txn.insert(
          'conversation_participants',
          {
            'conversation_id': conversationId,
            'user_id': userId,
            'role': 'member',
            'joined_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.insert(
          'conversation_user_state',
          {
            'conversation_id': conversationId,
            'user_id': userId,
            'last_read_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }

  @override
  Future<void> removeGroupMember(
      String conversationId, String actorId, String userId) async {
    final db = await _db;
    await _requireGroupManager(db, conversationId, actorId);
    final target = await db.query('conversation_participants',
        columns: ['role'],
        where: 'conversation_id = ? AND user_id = ?',
        whereArgs: [conversationId, userId]);
    if (target.isNotEmpty && target.single['role'] == 'owner') {
      throw StateError('The group owner cannot be removed');
    }
    await db.delete('conversation_participants',
        where: 'conversation_id = ? AND user_id = ?',
        whereArgs: [conversationId, userId]);
  }

  @override
  Future<void> markConversationRead(
      String conversationId, String userId) async {
    await (await _db).update(
        'conversation_user_state',
        {
          'last_read_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'conversation_id = ? AND user_id = ?',
        whereArgs: [conversationId, userId]);
  }

  @override
  Future<void> setConversationMuted(
      String conversationId, String userId, bool isMuted) async {
    await (await _db).update(
        'conversation_user_state',
        {
          'is_muted': isMuted ? 1 : 0,
        },
        where: 'conversation_id = ? AND user_id = ?',
        whereArgs: [conversationId, userId]);
  }

  @override
  Future<void> leaveGroup(String conversationId, String userId) async {
    await (await _db).delete('conversation_participants',
        where: 'conversation_id = ? AND user_id = ?',
        whereArgs: [conversationId, userId]);
  }

  @override
  Future<List<ChatMessage>> getMessages(String conversationId,
      {int limit = 100, int offset = 0}) async {
    final rows = await (await _db).query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.reversed.map(_messageFromRow).toList();
  }

  @override
  Future<ChatMessage> sendTextMessage(
      String conversationId, String senderId, String content,
      {String? replyToMessageId}) async {
    final db = await _db;
    final member = Sqflite.firstIntValue(await db.rawQuery('''
      SELECT COUNT(*) FROM conversation_participants
      WHERE conversation_id = ? AND user_id = ?
    ''', [conversationId, senderId]));
    if (member != 1) throw StateError('Sender is not a conversation member');
    final now = DateTime.now().toUtc();
    final message = ChatMessage(
      id: _uuid.v4(),
      conversationId: conversationId,
      senderUserId: senderId,
      type: MessageType.text,
      content: content.trim(),
      replyToMessageId: replyToMessageId,
      createdAt: now,
      updatedAt: now,
      deliveryStatus: DeliveryStatus.sent,
    );
    await db.transaction((txn) async {
      await txn.insert('messages', _messageToRow(message));
      await txn.update(
          'conversations',
          {
            'updated_at': now.toIso8601String(),
            'last_message_at': now.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [conversationId]);
      await txn.update(
          'conversation_user_state',
          {
            'last_read_at': now.toIso8601String(),
          },
          where: 'conversation_id = ? AND user_id = ?',
          whereArgs: [conversationId, senderId]);
    });
    return message;
  }

  @override
  Future<void> deleteMessage(String messageId, String requesterId) async {
    await (await _db).update(
      'messages',
      {
        'content': '',
        'is_deleted': 1,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND sender_user_id = ?',
      whereArgs: [messageId, requesterId],
    );
  }

  @override
  Future<List<ContactRequestView>> getIncomingRequests(String userId) =>
      _requestViews(userId, incoming: true);

  @override
  Future<List<ContactRequestView>> getOutgoingRequests(String userId) =>
      _requestViews(userId, incoming: false);

  Future<List<ContactRequestView>> _requestViews(String userId,
      {required bool incoming}) async {
    final ownColumn = incoming ? 'recipient_user_id' : 'sender_user_id';
    final otherColumn = incoming ? 'sender_user_id' : 'recipient_user_id';
    final rows = await (await _db).rawQuery('''
      SELECT r.*, u.id u_id, u.email u_email, u.username u_username,
        u.display_name u_display_name, u.avatar u_avatar,
        u.avatar_color u_avatar_color, u.bio u_bio,
        u.is_discoverable u_is_discoverable, u.created_at u_created_at,
        u.updated_at u_updated_at
      FROM contact_requests r JOIN users u ON u.id = r.$otherColumn
      WHERE r.$ownColumn = ? AND r.status = 'pending'
      ORDER BY r.created_at DESC
    ''', [userId]);
    return rows
        .map((row) => ContactRequestView(
              request: _requestFromRow(row),
              otherUser: AppUser(
                id: row['u_id']! as String,
                email: row['u_email']! as String,
                username: row['u_username']! as String,
                displayName: row['u_display_name']! as String,
                avatar: row['u_avatar'] as String?,
                avatarColor: row['u_avatar_color']! as int,
                bio: row['u_bio'] as String?,
                isDiscoverable: row['u_is_discoverable'] == 1,
                createdAt: DateTime.parse(row['u_created_at']! as String),
                updatedAt: DateTime.parse(row['u_updated_at']! as String),
              ),
            ))
        .toList();
  }

  @override
  Future<ContactRequest?> getRequestBetween(
      String firstId, String secondId) async {
    final rows = await (await _db).query('contact_requests',
        where: '''(sender_user_id = ? AND recipient_user_id = ?) OR
          (sender_user_id = ? AND recipient_user_id = ?)''',
        whereArgs: [firstId, secondId, secondId, firstId],
        orderBy: 'created_at DESC',
        limit: 1);
    return rows.isEmpty ? null : _requestFromRow(rows.single);
  }

  @override
  Future<ContactRequest> createRequest(
      String senderId, String recipientId, String message) async {
    final db = await _db;
    final existing = await getRequestBetween(senderId, recipientId);
    if (existing != null && existing.status != ContactRequestStatus.cancelled) {
      throw StateError(existing.status == ContactRequestStatus.blocked
          ? 'Contact is blocked'
          : 'A relationship or request already exists');
    }
    final direct = Sqflite.firstIntValue(await db.rawQuery('''
      SELECT COUNT(*) FROM conversations c
      JOIN conversation_participants a ON a.conversation_id = c.id AND a.user_id = ?
      JOIN conversation_participants b ON b.conversation_id = c.id AND b.user_id = ?
      WHERE c.type = 'direct'
    ''', [senderId, recipientId]));
    if ((direct ?? 0) > 0) throw StateError('A conversation already exists');
    final now = DateTime.now().toUtc();
    final request = ContactRequest(
      id: _uuid.v4(),
      senderUserId: senderId,
      recipientUserId: recipientId,
      introductoryMessage: message.trim(),
      status: ContactRequestStatus.pending,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('contact_requests', _requestToRow(request));
    return request;
  }

  @override
  Future<String> acceptRequest(String requestId, String recipientId) async {
    final db = await _db;
    return db.transaction((txn) async {
      final rows = await txn.query('contact_requests',
          where: 'id = ? AND recipient_user_id = ? AND status = ?',
          whereArgs: [requestId, recipientId, 'pending']);
      if (rows.isEmpty) throw StateError('Pending request not found');
      final request = _requestFromRow(rows.single);
      final now = DateTime.now().toUtc().toIso8601String();
      final conversationId = _uuid.v4();
      await txn.update(
          'contact_requests', {'status': 'accepted', 'updated_at': now},
          where: 'id = ?', whereArgs: [requestId]);
      await txn.insert('conversations', {
        'id': conversationId,
        'type': 'direct',
        'created_at': request.createdAt.toUtc().toIso8601String(),
        'updated_at': now,
        'last_message_at': request.createdAt.toUtc().toIso8601String(),
      });
      for (final userId in [request.senderUserId, request.recipientUserId]) {
        await txn.insert('conversation_participants', {
          'conversation_id': conversationId,
          'user_id': userId,
          'role': 'member',
          'joined_at': now,
        });
        await txn.insert('conversation_user_state', {
          'conversation_id': conversationId,
          'user_id': userId,
          'last_read_at': userId == recipientId ? now : null,
        });
      }
      await txn.insert('messages', {
        'id': _uuid.v4(),
        'conversation_id': conversationId,
        'sender_user_id': request.senderUserId,
        'type': 'text',
        'content': request.introductoryMessage,
        'created_at': request.createdAt.toUtc().toIso8601String(),
        'updated_at': request.updatedAt.toUtc().toIso8601String(),
        'delivery_status': 'read',
      });
      return conversationId;
    });
  }

  @override
  Future<void> changeRequestStatus(
      String requestId, String actorId, ContactRequestStatus status) async {
    final db = await _db;
    final allowed = switch (status) {
      ContactRequestStatus.cancelled => 'sender_user_id',
      ContactRequestStatus.declined ||
      ContactRequestStatus.blocked =>
        'recipient_user_id',
      _ => throw ArgumentError('Unsupported request transition'),
    };
    final changed = await db.update(
        'contact_requests',
        {
          'status': status.name,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ? AND $allowed = ? AND status = ?',
        whereArgs: [requestId, actorId, 'pending']);
    if (changed != 1) throw StateError('Request cannot be changed');
  }

  @override
  Future<AppSettings> getSettings(String userId) async {
    final rows = await (await _db)
        .query('settings', where: 'user_id = ?', whereArgs: [userId]);
    if (rows.isEmpty) {
      final settings = AppSettings(userId: userId);
      await saveSettings(settings);
      return settings;
    }
    final row = rows.single;
    return AppSettings(
      userId: userId,
      theme: row['theme']! as String,
      notificationsEnabled: row['notifications_enabled'] == 1,
      callNotificationsEnabled: row['call_notifications_enabled'] == 1,
      readReceiptsEnabled: row['read_receipts_enabled'] == 1,
      profilePhotoVisibility: row['profile_photo_visibility']! as String,
      requestAudience: row['request_audience']! as String,
      wifiOnlyDownloads: row['wifi_only_downloads'] == 1,
      fontScale: (row['font_scale']! as num).toDouble(),
    );
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    await (await _db).insert(
        'settings',
        {
          'user_id': settings.userId,
          'theme': settings.theme,
          'notifications_enabled': settings.notificationsEnabled ? 1 : 0,
          'call_notifications_enabled':
              settings.callNotificationsEnabled ? 1 : 0,
          'read_receipts_enabled': settings.readReceiptsEnabled ? 1 : 0,
          'profile_photo_visibility': settings.profilePhotoVisibility,
          'request_audience': settings.requestAudience,
          'wifi_only_downloads': settings.wifiOnlyDownloads ? 1 : 0,
          'font_scale': settings.fontScale,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> cacheUser(AppUser user) async {
    await (await _db).insert(
      'users',
      _userToRow(user),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> cacheRequestViews(List<ContactRequestView> views) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (final view in views) {
        await txn.insert(
          'users',
          _userToRow(view.otherUser),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await txn.insert(
          'contact_requests',
          _requestToRow(view.request),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> cacheAcceptedConversation(
    ContactRequestView view,
    String conversationId,
    String currentUserId,
  ) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
        'contact_requests',
        {'status': 'accepted', 'updated_at': now},
        where: 'id = ?',
        whereArgs: [view.request.id],
      );
      await txn.insert(
        'conversations',
        {
          'id': conversationId,
          'type': 'direct',
          'created_at': view.request.createdAt.toUtc().toIso8601String(),
          'updated_at': now,
          'last_message_at': view.request.createdAt.toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      for (final userId in [
        view.request.senderUserId,
        view.request.recipientUserId
      ]) {
        await txn.insert(
          'conversation_participants',
          {
            'conversation_id': conversationId,
            'user_id': userId,
            'role': 'member',
            'joined_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await txn.insert(
          'conversation_user_state',
          {
            'conversation_id': conversationId,
            'user_id': userId,
            'last_read_at': userId == currentUserId ? now : null,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await txn.insert(
        'messages',
        {
          'id': const Uuid().v4(),
          'conversation_id': conversationId,
          'sender_user_id': view.request.senderUserId,
          'type': 'text',
          'content': view.request.introductoryMessage,
          'created_at': view.request.createdAt.toUtc().toIso8601String(),
          'updated_at': now,
          'delivery_status': 'read',
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    });
  }

  Map<String, Object?> _userToRow(AppUser user) => {
        'id': user.id,
        'email': user.email,
        'username': user.username,
        'display_name': user.displayName,
        'avatar': user.avatar,
        'avatar_color': user.avatarColor,
        'bio': user.bio,
        'is_discoverable': user.isDiscoverable ? 1 : 0,
        'created_at': user.createdAt.toUtc().toIso8601String(),
        'updated_at': user.updatedAt.toUtc().toIso8601String(),
      };

  AppUser _userFromRow(Map<String, Object?> row) => AppUser(
        id: row['id']! as String,
        email: row['email']! as String,
        username: row['username']! as String,
        displayName: row['display_name']! as String,
        avatar: row['avatar'] as String?,
        avatarColor: row['avatar_color']! as int,
        bio: row['bio'] as String?,
        isDiscoverable: row['is_discoverable'] == 1,
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
      );

  Conversation _conversationFromRow(Map<String, Object?> row) => Conversation(
        id: row['id']! as String,
        type: ConversationType.values.byName(row['type']! as String),
        title: row['title'] as String?,
        avatar: row['avatar'] as String?,
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
        lastMessageAt: row['last_message_at'] == null
            ? null
            : DateTime.parse(row['last_message_at']! as String),
      );

  ChatMessage _messageFromRow(Map<String, Object?> row) => ChatMessage(
        id: row['id']! as String,
        conversationId: row['conversation_id']! as String,
        senderUserId: row['sender_user_id']! as String,
        type: MessageType.values.byName(row['type']! as String),
        content: row['content']! as String,
        replyToMessageId: row['reply_to_message_id'] as String?,
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
        deliveryStatus:
            DeliveryStatus.values.byName(row['delivery_status']! as String),
        isEdited: row['is_edited'] == 1,
        isDeleted: row['is_deleted'] == 1,
      );

  Map<String, Object?> _messageToRow(ChatMessage message) => {
        'id': message.id,
        'conversation_id': message.conversationId,
        'sender_user_id': message.senderUserId,
        'type': message.type.name,
        'content': message.content,
        'reply_to_message_id': message.replyToMessageId,
        'created_at': message.createdAt.toUtc().toIso8601String(),
        'updated_at': message.updatedAt.toUtc().toIso8601String(),
        'delivery_status': message.deliveryStatus.name,
        'is_edited': message.isEdited ? 1 : 0,
        'is_deleted': message.isDeleted ? 1 : 0,
      };

  ContactRequest _requestFromRow(Map<String, Object?> row) => ContactRequest(
        id: row['id']! as String,
        senderUserId: row['sender_user_id']! as String,
        recipientUserId: row['recipient_user_id']! as String,
        introductoryMessage: row['introductory_message']! as String,
        status: ContactRequestStatus.values.byName(row['status']! as String),
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
      );

  Map<String, Object?> _requestToRow(ContactRequest request) => {
        'id': request.id,
        'sender_user_id': request.senderUserId,
        'recipient_user_id': request.recipientUserId,
        'introductory_message': request.introductoryMessage,
        'status': request.status.name,
        'created_at': request.createdAt.toUtc().toIso8601String(),
        'updated_at': request.updatedAt.toUtc().toIso8601String(),
      };
}
