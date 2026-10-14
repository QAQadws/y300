import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/presentation/services/thread_body_presentation.dart';

void main() {
  test(
    'same HTML remount preserves fold and height but rejects old consumer',
    () {
      final store = ThreadBodyPresentationStore();
      final body = store.obtain('one', '<p>same</p>');
      final first = body.bind(consumer: Object(), layoutIdentity: 'layout');
      first.rendering.collapseExpansion['one-fold'] = true;
      first.recordHeight(640);
      first.release();
      expect(store.obtain('one', '<p>same</p>'), same(body));
      final second = body.bind(consumer: Object(), layoutIdentity: 'layout');
      expect(second.height, 640);
      expect(second.rendering.collapseExpansion['one-fold'], true);
      first.recordHeight(12);
      first.release();
      expect(second.isCurrent, true);
      expect(second.height, 640);
      second.recordHeight(720);
      expect(second.height, 720);
      store.clear();
    },
  );

  test(
    'layout changes clear height and retire nested layout but retain folds',
    () {
      final store = ThreadBodyPresentationStore();
      final body = store.obtain('one', '<p>same</p>');
      final consumer = Object();
      final first = body.bind(
        consumer: consumer,
        layoutIdentity: (300, 'font1'),
      );
      first.rendering.collapseExpansion['one-fold'] = true;
      first.recordHeight(640);
      final second = body.bind(
        consumer: consumer,
        layoutIdentity: (220, 'font2'),
      );
      expect(first.isCurrent, false);
      expect(first.rendering.isActive, false);
      expect(second.height, isNull);
      expect(second.rendering.collapseExpansion['one-fold'], true);
      first.recordHeight(999);
      expect(second.height, isNull);
      second.recordHeight(1280);
      expect(
        body.bind(consumer: consumer, layoutIdentity: (220, 'font2')),
        same(second),
      );
      expect(second.height, 1280);
      store.clear();
    },
  );

  test(
    'HTML A-B-A, removed PID, safe handoff and owner clear retire values',
    () {
      final store = ThreadBodyPresentationStore();
      final first = store.obtain('one', 'A');
      final old = first.bind(consumer: Object(), layoutIdentity: 'same-layout');
      old.rendering.collapseExpansion['fold'] = true;
      old.recordHeight(600);
      final middle = store.obtain('one', 'B');
      final replacement = store.obtain('one', 'A');
      expect(first.isActive, false);
      expect(middle.isActive, false);
      expect(replacement, isNot(same(first)));
      final current = replacement.bind(
        consumer: Object(),
        layoutIdentity: 'same-layout',
      );
      old.recordHeight(800);
      expect(current.height, isNull);
      expect(current.rendering.collapseExpansion, isEmpty);
      final other = store.obtain('two', 'other');
      store.retainWhere((pid, html) => pid == 'one' && html == 'A');
      expect(other.isActive, false);
      expect(store.length, 1);
      store.remove('one');
      expect(current.isCurrent, false);
      expect(replacement.isActive, false);
      expect(store.length, 0);
      final finalBody = store.obtain('one', 'A');
      store.clear();
      expect(finalBody.isActive, false);
      expect(store.length, 0);
    },
  );

  test('placeholder and invalid heights cannot replace completed geometry', () {
    final store = ThreadBodyPresentationStore();
    final lease = store
        .obtain('one', 'A')
        .bind(consumer: Object(), layoutIdentity: 'layout');
    lease.recordHeight(600);
    for (final invalid in [0.0, -1.0, double.infinity, double.nan]) {
      lease.recordHeight(invalid);
    }
    expect(lease.height, 600);
    store.clear();
    lease.recordHeight(30);
    expect(lease.isCurrent, false);
  });

  testWidgets(
    'waiting preserves height; built content and failure stay unconstrained',
    (tester) async {
      final store = ThreadBodyPresentationStore();
      addTearDown(store.clear);
      final lease = store
          .obtain('one', 'A')
          .bind(consumer: Object(), layoutIdentity: 'layout');
      lease.recordHeight(600);
      var phase = ThreadBodyLayoutPhase.preparing;
      var actualHeight = 20.0;
      const key = Key('waiting-body');
      Widget host() => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ThreadBodyWaitingLayout(
              key: key,
              lease: lease,
              phase: () => phase,
              child: SizedBox(height: actualHeight),
            ),
          ),
        ),
      );
      await tester.pumpWidget(host());
      expect(tester.getSize(find.byKey(key)).height, 600);
      expect(lease.height, 600);
      phase = ThreadBodyLayoutPhase.built;
      actualHeight = 720;
      await tester.pumpWidget(host());
      expect(tester.getSize(find.byKey(key)).height, 720);
      expect(lease.height, 720);
      phase = ThreadBodyLayoutPhase.failed;
      actualHeight = 40;
      await tester.pumpWidget(host());
      expect(tester.getSize(find.byKey(key)).height, 40);
      expect(lease.height, 720);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('late layout cannot fill a replacement HTML or layout lease', (
    tester,
  ) async {
    final store = ThreadBodyPresentationStore();
    addTearDown(store.clear);
    final old = store
        .obtain('one', 'A')
        .bind(consumer: Object(), layoutIdentity: 'old');
    final replacement = store
        .obtain('one', 'B')
        .bind(consumer: Object(), layoutIdentity: 'new');
    replacement.recordHeight(720);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThreadBodyWaitingLayout(
            lease: old,
            phase: () => ThreadBodyLayoutPhase.built,
            child: const SizedBox(height: 100),
          ),
        ),
      ),
    );
    expect(old.isCurrent, false);
    expect(replacement.height, 720);
    expect(tester.takeException(), isNull);
  });
}
