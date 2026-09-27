import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:veyra/security/models/e2ee_models.dart';
import 'package:veyra/security/session_operation_coordinator.dart';

void main() {
  test('native error names map to safe application failures', () {
    expect(
      E2eeFailureCode.fromWireName('IDENTITY_CHANGED'),
      E2eeFailureCode.identityChanged,
    );
    expect(
      E2eeFailureCode.fromWireName('NATIVE_STACK_TRACE_NOT_EXPOSED'),
      E2eeFailureCode.notInitialized,
    );
  });

  test('session operations are serialized per remote device', () async {
    final coordinator = SessionOperationCoordinator();
    const remote = DeviceAddress(userId: 'bob', deviceId: 'bob-device');
    final firstMayFinish = Completer<void>();
    final order = <String>[];

    final first = coordinator.synchronized(remote, () async {
      order.add('first-start');
      await firstMayFinish.future;
      order.add('first-end');
    });
    final second = coordinator.synchronized(remote, () async {
      order.add('second');
    });

    await Future<void>.delayed(Duration.zero);
    expect(order, ['first-start']);
    firstMayFinish.complete();
    await Future.wait([first, second]);
    expect(order, ['first-start', 'first-end', 'second']);
  });
}
