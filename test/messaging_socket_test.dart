import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:veyra/core/network/messaging_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class FakeWebSocketSink implements WebSocketSink {
  FakeWebSocketSink(this.controller);
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

class FakeWebSocketChannel extends StreamChannelMixin
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
  late final WebSocketSink sink = FakeWebSocketSink(outgoing);
  @override
  Stream<Object?> get stream => incoming.stream;
}

void main() {
  test('socket authenticates, exposes state, and answers heartbeat', () async {
    final channel = FakeWebSocketChannel();
    final sent = <Map<String, dynamic>>[];
    channel.outgoing.stream.listen((value) =>
        sent.add(jsonDecode(value as String) as Map<String, dynamic>));
    Uri? opened;
    final socket = MessagingSocket(
      apiBaseUrl: 'https://api.example.test',
      tokenProvider: ({bool refresh = false}) async => 'access-token',
      deviceProvider: () async => 'device-uuid',
      channelFactory: (uri, protocols) {
        opened = uri;
        expect(
            protocols,
            containsAll(
                ['veyra.v1', 'bearer.access-token', 'device.device-uuid']));
        return channel;
      },
    );

    await socket.connect();
    expect(socket.state, MessagingConnectionState.connected);
    expect(opened!.scheme, 'wss');
    expect(opened!.query, isEmpty);
    expect(socket.send('sync.request', const {}), isTrue);
    channel.incoming.add(jsonEncode({
      'version': 1,
      'type': 'ping',
      'request_id': '11111111-1111-4111-8111-111111111111',
      'payload': {},
    }));
    await Future<void>.delayed(Duration.zero);
    expect(sent.map((event) => event['type']),
        containsAll(['sync.request', 'pong']));

    await channel.incoming.close();
    await Future<void>.delayed(Duration.zero);
    expect(socket.state, MessagingConnectionState.reconnecting);
    await socket.disconnect();
    expect(socket.state, MessagingConnectionState.offline);
    await socket.dispose();
  });
}
