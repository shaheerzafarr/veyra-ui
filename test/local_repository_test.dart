import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:veyra/core/data/local_database.dart';
import 'package:veyra/core/data/repositories.dart';
import 'package:veyra/core/models/entities.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late VeyraDatabase database;
  late LocalVeyraRepository repository;

  setUp(() async {
    database = VeyraDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repository = LocalVeyraRepository(database);
    await database.database;
  });

  tearDown(() => database.close());

  test('accept request creates a conversation with the introduction', () async {
    final users = await repository.getUsers();
    final alice = users.firstWhere((user) => user.username == 'alex');
    final bob = users.firstWhere((user) => user.username == 'sarah');

    final request = await repository.createRequest(
        alice.id, bob.id, 'Hello Sarah, I would love to connect.');
    expect(request.status, ContactRequestStatus.pending);
    await expectLater(
      repository.createRequest(alice.id, bob.id, 'A second message'),
      throwsStateError,
    );

    final conversationId = await repository.acceptRequest(request.id, bob.id);
    final messages = await repository.getMessages(conversationId);
    expect(messages.single.content, 'Hello Sarah, I would love to connect.');

    await repository.sendTextMessage(conversationId, bob.id, 'Welcome!');
    expect(await repository.getMessages(conversationId), hasLength(2));
  });

  test('declining a request does not create a conversation', () async {
    final users = await repository.getUsers();
    final alice = users.firstWhere((user) => user.username == 'alex');
    final bob = users.firstWhere((user) => user.username == 'sarah');
    final request = await repository.createRequest(alice.id, bob.id, 'Hello');

    await repository.changeRequestStatus(
        request.id, bob.id, ContactRequestStatus.declined);

    expect(
        (await repository.getConversations(alice.id))
            .where((chat) => chat.otherUserId == bob.id),
        isEmpty);
  });

  test('blocking prevents another request', () async {
    final users = await repository.getUsers();
    final alice = users.firstWhere((user) => user.username == 'alex');
    final bob = users.firstWhere((user) => user.username == 'sarah');
    final request = await repository.createRequest(alice.id, bob.id, 'Hello');

    await repository.changeRequestStatus(
        request.id, bob.id, ContactRequestStatus.blocked);

    await expectLater(
      repository.createRequest(alice.id, bob.id, 'Trying again'),
      throwsStateError,
    );
  });

  test('conversation and messages survive a database reopen', () async {
    await database.close();
    final directory = await Directory.systemTemp.createTemp('veyra_test_');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}veyra.db';
    final firstDatabase =
        VeyraDatabase(factory: databaseFactoryFfi, path: path);
    final first = LocalVeyraRepository(firstDatabase);
    final users = await first.getUsers();
    final alice = users.firstWhere((user) => user.username == 'alex');
    final bob = users.firstWhere((user) => user.username == 'sarah');
    final request =
        await first.createRequest(alice.id, bob.id, 'Persistent hello');
    final conversationId = await first.acceptRequest(request.id, bob.id);
    await first.sendTextMessage(conversationId, bob.id, 'Persistent reply');
    await firstDatabase.close();

    final reopenedDatabase =
        VeyraDatabase(factory: databaseFactoryFfi, path: path);
    final reopened = LocalVeyraRepository(reopenedDatabase);
    final messages = await reopened.getMessages(conversationId);
    expect(messages.map((message) => message.content),
        ['Persistent hello', 'Persistent reply']);
    await reopenedDatabase.close();
  });

  test('persistent outbox survives restart and keeps the same UUID', () async {
    await database.close();
    final directory = await Directory.systemTemp.createTemp('veyra_outbox_');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}veyra.db';
    final firstDatabase =
        VeyraDatabase(factory: databaseFactoryFfi, path: path);
    final first = LocalVeyraRepository(firstDatabase);
    final users = await first.getUsers();
    final alice = users.firstWhere((user) => user.username == 'alex');
    final bob = users.firstWhere((user) => user.username == 'sarah');
    final request = await first.createRequest(alice.id, bob.id, 'Hello');
    final conversationId = await first.acceptRequest(request.id, bob.id);
    final outgoing = await first.createOutgoingMessage(
        conversationId, alice.id, 'device-alice', 'Queued message');
    expect(outgoing.deliveryStatus, DeliveryStatus.sending);
    await firstDatabase.close();

    final reopenedDatabase =
        VeyraDatabase(factory: databaseFactoryFfi, path: path);
    final reopened = LocalVeyraRepository(reopenedDatabase);
    final pending = await reopened.pendingOutgoingMessages();
    expect(pending.single.id, outgoing.id);
    expect(pending.single.content, 'Queued message');
    await reopenedDatabase.close();
  });

  test('incoming message persistence is idempotent and statuses are real',
      () async {
    final users = await repository.getUsers();
    final alice = users.firstWhere((user) => user.username == 'alex');
    final bob = users.firstWhere((user) => user.username == 'sarah');
    final request = await repository.createRequest(alice.id, bob.id, 'Hello');
    final conversationId = await repository.acceptRequest(request.id, bob.id);
    final now = DateTime.now().toUtc();
    final incoming = ChatMessage(
      id: '11111111-1111-4111-8111-111111111111',
      conversationId: conversationId,
      senderUserId: alice.id,
      senderDeviceId: 'device-alice',
      type: MessageType.text,
      content: 'Delivered once',
      createdAt: now.subtract(const Duration(seconds: 1)),
      updatedAt: now,
      serverReceivedAt: now,
      deliveryStatus: DeliveryStatus.delivered,
    );
    expect(await repository.persistIncomingMessage(incoming), isTrue);
    expect(await repository.persistIncomingMessage(incoming), isFalse);
    final stored = await repository.getMessages(conversationId);
    expect(stored.where((message) => message.id == incoming.id), hasLength(1));

    await repository.updateDeliveryStatus(incoming.id, DeliveryStatus.read);
    expect(
      (await repository.getMessages(conversationId))
          .firstWhere((message) => message.id == incoming.id)
          .deliveryStatus,
      DeliveryStatus.read,
    );
  });
}
