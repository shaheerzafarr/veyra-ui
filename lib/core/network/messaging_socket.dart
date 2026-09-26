import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum MessagingConnectionState { connected, connecting, reconnecting, offline }

class MessagingSocket {
  MessagingSocket({
    required String apiBaseUrl,
    required Future<String?> Function({bool refresh}) tokenProvider,
    required Future<String> Function() deviceProvider,
    WebSocketChannel Function(Uri, Iterable<String>)? channelFactory,
    Random? random,
  })  : _apiBaseUrl = apiBaseUrl,
        _tokenProvider = tokenProvider,
        _deviceProvider = deviceProvider,
        _channelFactory = channelFactory ??
            ((uri, protocols) =>
                WebSocketChannel.connect(uri, protocols: protocols)),
        _random = random ?? Random();

  final String _apiBaseUrl;
  final Future<String?> Function({bool refresh}) _tokenProvider;
  final Future<String> Function() _deviceProvider;
  final WebSocketChannel Function(Uri, Iterable<String>) _channelFactory;
  final Random _random;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _states = StreamController<MessagingConnectionState>.broadcast();
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _stableTimer;
  Future<void>? _connecting;
  bool _shouldReconnect = false;
  bool _refreshTokenNext = false;
  int _attempt = 0;
  MessagingConnectionState _state = MessagingConnectionState.offline;

  Stream<Map<String, dynamic>> get events => _events.stream;
  Stream<MessagingConnectionState> get states => _states.stream;
  MessagingConnectionState get state => _state;

  Future<void> connect() {
    _shouldReconnect = true;
    return _connecting ??= _open().whenComplete(() => _connecting = null);
  }

  Future<void> _open() async {
    _setState(_attempt == 0
        ? MessagingConnectionState.connecting
        : MessagingConnectionState.reconnecting);
    try {
      final token = await _tokenProvider(refresh: _refreshTokenNext);
      _refreshTokenNext = false;
      if (token == null) throw StateError('Authentication required');
      final device = await _deviceProvider();
      final httpUri = Uri.parse(_apiBaseUrl);
      final uri = httpUri.replace(
        scheme: httpUri.scheme == 'https' ? 'wss' : 'ws',
        path: '${httpUri.path.replaceAll(RegExp(r'/$'), '')}/ws',
      );
      final channel =
          _channelFactory(uri, ['veyra.v1', 'bearer.$token', 'device.$device']);
      _channel = channel;
      await channel.ready;
      _setState(MessagingConnectionState.connected);
      _stableTimer?.cancel();
      _stableTimer = Timer(const Duration(seconds: 15), () => _attempt = 0);
      channel.stream.listen(_onData, onError: (_) {
        _refreshTokenNext = true;
        _lostConnection();
      }, onDone: _lostConnection, cancelOnError: true);
    } catch (_) {
      _refreshTokenNext = true;
      _lostConnection();
    }
  }

  void _onData(Object? data) {
    try {
      final decoded = jsonDecode(data as String);
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1) return;
      if (decoded['type'] == 'ping') {
        send('pong', const {}, requestId: decoded['request_id'] as String?);
      }
      _events.add(decoded);
    } catch (_) {
      // Invalid server frames are ignored rather than reaching repositories.
    }
  }

  void _lostConnection() {
    _stableTimer?.cancel();
    _channel = null;
    if (!_shouldReconnect || _reconnectTimer?.isActive == true) {
      if (!_shouldReconnect) _setState(MessagingConnectionState.offline);
      return;
    }
    _attempt++;
    _setState(MessagingConnectionState.reconnecting);
    final exponent = min(_attempt - 1, 5);
    final baseMilliseconds = 1000 * (1 << exponent);
    final jitter = _random.nextInt(max(1, baseMilliseconds ~/ 3));
    _reconnectTimer = Timer(
      Duration(milliseconds: min(30000, baseMilliseconds + jitter)),
      connect,
    );
  }

  bool send(String type, Map<String, dynamic> payload, {String? requestId}) {
    final channel = _channel;
    if (channel == null || _state != MessagingConnectionState.connected) {
      return false;
    }
    channel.sink.add(jsonEncode({
      'version': 1,
      'type': type,
      'request_id': requestId ?? const Uuid().v4(),
      'payload': payload,
    }));
    return true;
  }

  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _stableTimer?.cancel();
    final channel = _channel;
    _channel = null;
    await channel?.sink.close();
    _setState(MessagingConnectionState.offline);
  }

  void appResumed() => connect();
  Future<void> appPaused() => disconnect();

  void _setState(MessagingConnectionState value) {
    if (_state == value) return;
    _state = value;
    _states.add(value);
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
    await _states.close();
  }
}
