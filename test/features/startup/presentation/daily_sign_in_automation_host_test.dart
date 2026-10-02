import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/y300_app.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
import 'package:y300/features/startup/presentation/daily_sign_in_automation_host.dart';

const _firstOwner = (uid: '654321', revision: 1);
const _secondOwner = (uid: '777777', revision: 2);
final _testOwnerProvider = StateProvider<VerifiedProfileOwner?>((ref) => null);

void main() {
  test('the default app home keeps the automation host mounted', () {
    expect(const Y300App().home, isA<DailySignInAutomationHost>());
  });

  testWidgets(
    'cold start waits for a verified owner and keeps the shell ready',
    (tester) async {
      final operations = _FakeOperations();
      await _pumpHost(tester, operations: operations);

      expect(find.text('main shell'), findsOneWidget);
      expect(operations.triggerCount, 0);

      _setOwner(tester, _firstOwner);
      await tester.pump();
      await tester.pump();
      expect(operations.triggerCount, 1);

      // A duplicate resumed event within the same foreground period does not
      // start another network check.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(operations.triggerCount, 1);
    },
  );

  testWidgets('background login checks only after returning to foreground', (
    tester,
  ) async {
    final operations = _FakeOperations();
    await _pumpHost(tester, operations: operations);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

    _setOwner(tester, _firstOwner);
    await tester.pump();
    expect(operations.triggerCount, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(operations.triggerCount, 1);
  });

  testWidgets('foreground returns do not restart a completed launch check', (
    tester,
  ) async {
    final operations = _FakeOperations();
    await _pumpHost(tester, operations: operations, initialOwner: _firstOwner);
    expect(operations.triggerCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(operations.cancelCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(operations.triggerCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(operations.triggerCount, 1);
  });

  testWidgets(
    'a cancelled in-flight run does not restart on foreground return',
    (tester) async {
      final oldFlight = Completer<void>();
      final operations = _FakeOperations(onTrigger: (_) => oldFlight.future);
      await _pumpHost(
        tester,
        operations: operations,
        initialOwner: _firstOwner,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(operations.cancelCount, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(operations.triggerCount, 1);

      oldFlight.complete();
      await tester.pump();
      await tester.pump();
      expect(operations.triggerCount, 1);
    },
  );

  testWidgets('a failed startup run remains non-blocking and is not retried', (
    tester,
  ) async {
    final operations = _FakeOperations(
      onTrigger: (_) => Future<void>.error(StateError('synthetic failure')),
    );
    await _pumpHost(tester, operations: operations, initialOwner: _firstOwner);

    expect(tester.takeException(), isNull);
    expect(find.text('main shell'), findsOneWidget);
    expect(operations.triggerCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    _setOwner(tester, null);
    await tester.pump();
    _setOwner(tester, (uid: _firstOwner.uid, revision: 2));
    await tester.pump();
    expect(operations.triggerCount, 1);
  });

  testWidgets('owner change during an old flight schedules a new check', (
    tester,
  ) async {
    final oldFlight = Completer<void>();
    final operations = _FakeOperations(
      onTrigger: (call) {
        if (call == 1) return oldFlight.future;
        return Future<void>.value();
      },
    );
    await _pumpHost(tester, operations: operations, initialOwner: _firstOwner);
    expect(operations.triggerCount, 1);

    _setOwner(tester, _secondOwner);
    await tester.pump();
    expect(operations.triggerCount, 1);
    expect(operations.cancelCount, 1);
    expect(find.text('main shell'), findsOneWidget);

    oldFlight.complete();
    await tester.pump();
    await tester.pump();
    expect(operations.triggerCount, 2);
  });

  testWidgets('logout and same UID relogin keep the launch check consumed', (
    tester,
  ) async {
    final operations = _FakeOperations();
    await _pumpHost(tester, operations: operations, initialOwner: _firstOwner);
    expect(operations.triggerCount, 1);

    _setOwner(tester, null);
    await tester.pump();
    expect(operations.cancelCount, 1);
    expect(operations.triggerCount, 1);

    _setOwner(tester, (uid: _firstOwner.uid, revision: 2));
    await tester.pump();
    await tester.pump();
    expect(operations.triggerCount, 1);
  });

  testWidgets('a new session revision cannot repeat the same UID run', (
    tester,
  ) async {
    final operations = _FakeOperations();
    await _pumpHost(tester, operations: operations, initialOwner: _firstOwner);

    _setOwner(tester, (uid: _firstOwner.uid, revision: 2));
    await tester.pump();
    await tester.pump();
    expect(operations.triggerCount, 1);
  });

  testWidgets('switching accounts grants one run to each UID in this launch', (
    tester,
  ) async {
    final operations = _FakeOperations();
    await _pumpHost(tester, operations: operations, initialOwner: _firstOwner);

    _setOwner(tester, _secondOwner);
    await tester.pump();
    await tester.pump();
    expect(operations.triggerCount, 2);

    _setOwner(tester, (uid: _firstOwner.uid, revision: 3));
    await tester.pump();
    _setOwner(tester, (uid: _secondOwner.uid, revision: 4));
    await tester.pump();
    expect(operations.triggerCount, 2);
  });

  testWidgets(
    'a new account in background waits after the old flight settles',
    (tester) async {
      final oldFlight = Completer<void>();
      final operations = _FakeOperations(
        onTrigger: (call) =>
            call == 1 ? oldFlight.future : Future<void>.value(),
      );
      await _pumpHost(
        tester,
        operations: operations,
        initialOwner: _firstOwner,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      _setOwner(tester, _secondOwner);
      await tester.pump();
      oldFlight.complete();
      await tester.pump();
      expect(operations.triggerCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(operations.triggerCount, 2);
    },
  );

  testWidgets('ordinary host rebuilds keep the launch check consumed', (
    tester,
  ) async {
    final operations = _FakeOperations();
    await _pumpHost(tester, operations: operations, initialOwner: _firstOwner);
    final state = tester.state(find.byType(DailySignInAutomationHost));

    await _pumpHost(tester, operations: operations, initialOwner: _firstOwner);
    expect(tester.state(find.byType(DailySignInAutomationHost)), same(state));
    expect(operations.triggerCount, 1);
  });

  testWidgets('a new app launch grants the same UID a new initial run', (
    tester,
  ) async {
    final operations = _FakeOperations();
    await _pumpHost(tester, operations: operations, initialOwner: _firstOwner);
    expect(operations.triggerCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpHost(tester, operations: operations, initialOwner: _firstOwner);
    expect(operations.triggerCount, 2);
  });
}

Future<void> _pumpHost(
  WidgetTester tester, {
  required _FakeOperations operations,
  VerifiedProfileOwner? initialOwner,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        _testOwnerProvider.overrideWith((ref) => initialOwner),
        verifiedProfileOwnerProvider.overrideWith(
          (ref) => ref.watch(_testOwnerProvider),
        ),
        dailySignInAutomationOperationsProvider.overrideWithValue(
          DailySignInAutomationOperations(
            trigger: operations.trigger,
            cancelPending: operations.cancel,
          ),
        ),
      ],
      child: const MaterialApp(
        home: DailySignInAutomationHost(
          child: Scaffold(body: Text('main shell')),
        ),
      ),
    ),
  );
  await tester.pump();
}

void _setOwner(WidgetTester tester, VerifiedProfileOwner? owner) {
  final scope = ProviderScope.containerOf(
    tester.element(find.byType(DailySignInAutomationHost)),
  );
  scope.read(_testOwnerProvider.notifier).state = owner;
}

class _FakeOperations {
  _FakeOperations({this.onTrigger});

  final Future<void> Function(int call)? onTrigger;
  int triggerCount = 0;
  int cancelCount = 0;

  Future<void> trigger() {
    triggerCount += 1;
    return onTrigger?.call(triggerCount) ?? Future<void>.value();
  }

  void cancel() => cancelCount += 1;
}
