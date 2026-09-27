import 'dart:async';

import 'models/e2ee_models.dart';

/// Serializes future ratchet mutations for one remote device.
class SessionOperationCoordinator {
  final Map<String, Future<void>> _tails = {};

  Future<T> synchronized<T>(
    DeviceAddress remote,
    Future<T> Function() operation,
  ) async {
    final previous = _tails[remote.lockKey] ?? Future<void>.value();
    final completer = Completer<void>();
    final tail = completer.future;
    _tails[remote.lockKey] = tail;
    await previous;
    try {
      return await operation();
    } finally {
      completer.complete();
      if (identical(_tails[remote.lockKey], tail)) {
        _tails.remove(remote.lockKey);
      }
    }
  }
}
