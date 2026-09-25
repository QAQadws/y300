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

  testWidgets('foreground return checks once and background cancels pending', (
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
    expect(operations.triggerCount, 2);
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

  testWidgets('logout and same UID relogin create separate checks', (
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
