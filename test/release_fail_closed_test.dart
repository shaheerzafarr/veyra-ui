import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:veyra/core/data/local_database.dart';
import 'package:veyra/core/data/network_message_repository.dart';
import 'package:veyra/core/data/repositories.dart';
import 'package:veyra/core/models/entities.dart';
import 'package:veyra/core/network/api_client.dart';
import 'package:veyra/core/network/messaging_socket.dart';
import 'package:veyra/core/network/remote_data_sources.dart';
import 'package:veyra/core/network/token_storage.dart';
import 'package:veyra/security/e2ee_service.dart';
import 'package:veyra/security/models/e2ee_models.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FakeWebSocketSink implements WebSocketSink {
  _FakeWebSocketSink(this.controller);
  final StreamController<Object?> controller;

  @override
  void add(Object? data) => controller.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      controller.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<Object?> stream) =>
      controller.addStream(stream);
  @override
  Future<void> close([int? closeCode, String? closeReason]) =>
      controller.close();
  @override
  Future<void> get done => controller.done;
}

class _FakeWebSocketChannel extends StreamChannelMixin
    implements WebSocketChannel {
  final incoming = StreamController<Object?>.broadcast();
  final outgoing = StreamController<Object?>.broadcast();

  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;
  @override
  Future<void> get ready => Future.value();
  @override
  late final WebSocketSink sink = _FakeWebSocketSink(outgoing);
  @override
  Stream<Object?> get stream => incoming.stream;
}

class _MemoryTokens implements TokenStorage {
  @override
  Future<void> clear() async {}
  @override
  Future<String?> readAccessToken() async => null;
  @override
  Future<String?> readDeviceId() async => 'device';
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> writeDeviceId(String value) async {}
  @override
  Future<void> writeTokens(
      {required String accessToken, required String refreshToken}) async {}
}

class _UnavailableE2ee implements E2eeService {
  Never _unavailable() => throw const E2eeException(
        E2eeFailureCode.notInitialized,
        sanitizedMessage: 'Secure messaging unavailable',
      );

  @override
  Future<DecryptedMessage> decrypt(EncryptedEnvelope envelope) async =>
      _unavailable();
  @override
  Future<void> deleteSession(DeviceAddress remote) async => _unavailable();
  @override
  Future<EncryptedEnvelope> encrypt({
    required String messageId,
    required String conversationId,
    required DeviceAddress sender,
    required DeviceAddress recipient,
    required Uint8List plaintext,
  }) async =>
      _unavailable();
  @override
  Future<void> establishSession(
          DeviceAddress remote, DevicePublicBundle bundle) async =>
      _unavailable();
  @override
  Future<DevicePublicBundle> getPublicBundle() async => _unavailable();
  @override
  Future<IdentityVerification> getSafetyNumber(DeviceAddress remote) async =>
      _unavailable();
  @override
  Future<bool> hasIdentity() async => false;
  @override
  Future<bool> hasSession(DeviceAddress remote) async => false;
  @override
  Future<void> initialize(DeviceAddress local) async => _unavailable();
  @override
  Future<void> markPreKeysPublished(List<int> ids) async => _unavailable();
  @override
  Future<void> markVerified(DeviceAddress remote) async => _unavailable();
  @override
  Future<void> replenishPreKeys(int count) async => _unavailable();
  @override
  Future<bool> verifyScannable(
          DeviceAddress remote, Uint8List scannable) async =>
      _unavailable();
}

void main() {
  setUpAll(sqfliteFfiInit);

  test('release messaging fails closed when E2EE is not ready', () async {
    final database = VeyraDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final local = LocalVeyraRepository(database);
    final users = await local.getUsers();
    final alice = users.firstWhere((user) => user.username == 'alex');
    final bob = users.firstWhere((user) => user.username == 'sarah');
    final request = await local.createRequest(alice.id, bob.id, 'Hello');
    final conversationId = await local.acceptRequest(request.id, bob.id);
    final channel = _FakeWebSocketChannel();
    final sentTypes = <String>[];
    channel.outgoing.stream.listen((value) {
      sentTypes.add((jsonDecode(value as String)
          as Map<String, dynamic>)['type'] as String);
    });
    final socket = MessagingSocket(
      apiBaseUrl: 'https://api.example.test',
      tokenProvider: ({bool refresh = false}) async => 'access-token',
      deviceProvider: () async => 'device',
      channelFactory: (_, __) => channel,
    );
    final network = NetworkMessageRepository(
      local: local,
      socket: socket,
      deviceId: () async => 'device',
      e2ee: _UnavailableE2ee(),
      crypto: CryptoRemoteDataSource(
        ApiClient(baseUrl: 'https://api.example.test', tokens: _MemoryTokens()),
      ),
      allowDevelopmentPlaintextTransport: false,
    );
    addTearDown(() async {
      await network.dispose();
      await socket.dispose();
      await channel.incoming.close();
      await database.close();
    });

    await network.start(alice.id);
    await network.sendTextMessage(
        conversationId, alice.id, 'MUST_NOT_LEAVE_AS_PLAINTEXT');

    final stored = (await local.getMessages(conversationId)).last;
    expect(stored.deliveryStatus, DeliveryStatus.failed);
    expect(stored.encryptedEnvelope, isNull);
    expect(sentTypes, isNot(contains('message.send')));
  });
}
