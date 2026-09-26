import '../models/entities.dart';
import '../network/remote_data_sources.dart';
import 'repositories.dart';

class ServerIdentityRepository
    implements UserRepository, ContactRequestRepository {
  ServerIdentityRepository({
    required LocalVeyraRepository local,
    required UserRemoteDataSource users,
    required RequestRemoteDataSource requests,
  })  : _local = local,
        _users = users,
        _requests = requests;

  final LocalVeyraRepository _local;
  final UserRemoteDataSource _users;
  final RequestRemoteDataSource _requests;
  final Map<String, ContactRequestView> _requestCache = {};
  bool _serverEnabled = false;
  String? _previousLocalUserId;

  Future<void> enableServer() async {
    _previousLocalUserId ??= await _local.getActiveUserId();
    final current = _userFromJson(await _users.me(), isPrivate: true);
    await _local.cacheUser(current);
    await _local.setActiveUserId(current.id);
    _serverEnabled = true;
  }

  Future<void> disableServer() async {
    _serverEnabled = false;
    _requestCache.clear();
    if (_previousLocalUserId case final id?) {
      await _local.setActiveUserId(id);
    }
  }

  @override
  Future<List<AppUser>> getUsers() => _local.getUsers();

  @override
  Future<AppUser> getUser(String id) => _local.getUser(id);

  @override
  Future<String> getActiveUserId() => _local.getActiveUserId();

  @override
  Future<void> setActiveUserId(String id) {
    if (_serverEnabled) {
      throw StateError(
          'Account switching is available only in debug mock mode');
    }
    return _local.setActiveUserId(id);
  }

  @override
  Future<List<AppUser>> searchUsers(String query, String activeUserId) async {
    if (!_serverEnabled) return _local.searchUsers(query, activeUserId);
    if (query.trim().isEmpty) return const [];
    final users = (await _users.search(query)).map(_userFromJson).toList();
    for (final user in users) {
      await _local.cacheUser(user);
    }
    return users;
  }

  @override
  Future<void> updateUser(AppUser user) async {
    if (!_serverEnabled) return _local.updateUser(user);
    final updated = _userFromJson(
      await _users.updateMe({
        'username': user.username,
        'display_name': user.displayName,
        'bio': user.bio,
        'avatar_url': user.avatar,
        'is_discoverable': user.isDiscoverable,
      }),
      isPrivate: true,
    );
    await _local.cacheUser(updated);
  }

  @override
  Future<bool> isUsernameAvailable(String username, String exceptUserId) async {
    if (!_serverEnabled) {
      return _local.isUsernameAvailable(username, exceptUserId);
    }
    final result = await _users.usernameAvailability(username);
    return result['available'] as bool;
  }

  @override
  Future<List<ContactRequestView>> getIncomingRequests(String userId) async {
    if (!_serverEnabled) return _local.getIncomingRequests(userId);
    return _cacheViews(await _requests.incoming());
  }

  @override
  Future<List<ContactRequestView>> getOutgoingRequests(String userId) async {
    if (!_serverEnabled) return _local.getOutgoingRequests(userId);
    return _cacheViews(await _requests.outgoing());
  }

  Future<List<ContactRequestView>> _cacheViews(
      List<Map<String, dynamic>> rows) async {
    final views = rows.map(_requestFromJson).toList();
    for (final view in views) {
      _requestCache[view.request.id] = view;
    }
    await _local.cacheRequestViews(views);
    return views;
  }

  @override
  Future<ContactRequest?> getRequestBetween(
      String firstId, String secondId) async {
    if (!_serverEnabled) return _local.getRequestBetween(firstId, secondId);
    for (final view in _requestCache.values) {
      final request = view.request;
      if ((request.senderUserId == firstId &&
              request.recipientUserId == secondId) ||
          (request.senderUserId == secondId &&
              request.recipientUserId == firstId)) {
        return request;
      }
    }
    return null;
  }

  @override
  Future<ContactRequest> createRequest(
      String senderId, String recipientId, String message) async {
    if (!_serverEnabled) {
      return _local.createRequest(senderId, recipientId, message);
    }
    final view = _requestFromJson(await _requests.create(recipientId, message));
    _requestCache[view.request.id] = view;
    await _local.cacheRequestViews([view]);
    return view.request;
  }

  @override
  Future<String> acceptRequest(String requestId, String recipientId) async {
    if (!_serverEnabled) return _local.acceptRequest(requestId, recipientId);
    final view = _requestCache[requestId];
    if (view == null) throw StateError('Pending request is not cached');
    final result = await _requests.accept(requestId);
    final conversationId = result['conversation_id'] as String;
    await _local.cacheAcceptedConversation(view, conversationId, recipientId);
    _requestCache.remove(requestId);
    return conversationId;
  }

  @override
  Future<void> changeRequestStatus(
    String requestId,
    String actorId,
    ContactRequestStatus status,
  ) async {
    if (!_serverEnabled) {
      return _local.changeRequestStatus(requestId, actorId, status);
    }
    final view = _requestCache[requestId];
    switch (status) {
      case ContactRequestStatus.declined:
        await _requests.decline(requestId);
      case ContactRequestStatus.cancelled:
        await _requests.cancel(requestId);
      case ContactRequestStatus.blocked:
        if (view == null) throw StateError('Pending request is not cached');
        await _users.block(view.otherUser.id);
      default:
        throw ArgumentError('Unsupported request transition');
    }
    _requestCache.remove(requestId);
  }

  AppUser _userFromJson(Map<String, dynamic> json, {bool isPrivate = false}) {
    final created = DateTime.tryParse(json['created_at']?.toString() ?? '') ??
        DateTime.now().toUtc();
    return AppUser(
      id: json['id'] as String,
      email: isPrivate ? (json['email'] as String? ?? '') : '',
      username: json['username'] as String,
      displayName: json['display_name'] as String,
      avatar: json['avatar_url'] as String?,
      avatarColor: 0xFF34D399,
      bio: json['bio'] as String?,
      isDiscoverable: json['is_discoverable'] as bool? ?? true,
      createdAt: created,
      updatedAt:
          DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? created,
    );
  }

  ContactRequestView _requestFromJson(Map<String, dynamic> json) {
    final other = _userFromJson(json['other_user'] as Map<String, dynamic>);
    return ContactRequestView(
      request: ContactRequest(
        id: json['id'] as String,
        senderUserId: json['sender_user_id'] as String,
        recipientUserId: json['recipient_user_id'] as String,
        introductoryMessage: json['introductory_message'] as String,
        status: ContactRequestStatus.values.byName(json['status'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      ),
      otherUser: other,
    );
  }
}
