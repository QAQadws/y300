import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_exception.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_work_scheduler.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';

final class _Fixture {
  _Fixture() {
    cache = ForumBodyParagraphCache(maxEntries: 2, maxEstimatedBytes: 1 << 20);
    session = ForumBodyTextPageSession(
      document: const ForumBodyParser().parse(
        html: '<p>x</p>',
        sourceId: 'wait',
        conversionIdentity: 'none',
      ),
      reader: ForumBodyReaderStyle(
        textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 10, height: 1),
        fontRevision: 'ahem',
        linkColor: const Color(0xFF0000FF),
      ),
      cache: cache,
      limits: const ForumBodyTextPageSessionLimits(
        maxPages: 10,
        maxFragments: 10,
        maxParagraphs: 10,
        maxTextCodeUnits: 100,
        maxRuns: 10,
        maxIssuedLeases: 10,
      ),
      layoutId: 'wait-a',
      width: 100,
      height: 100,
    );
    addTearDown(() {
      session.close();
      cache.close();
    });
  }
  late final ForumBodyParagraphCache cache;
  late final ForumBodyTextPageSession session;
  final token = NovelReaderPaginationCancellationToken();

  void publish() {
    var calls = 0;
    while (!session.isComplete) {
      if (++calls > 100) fail('Source made no progress');
      session.advance(maxEvents: 16, maxLines: 4);
    }
  }
}

Matcher get _cancelled => throwsA(
  isA<NovelReaderPaginationException>().having(
    (error) => error.code,
    'code',
    'paginationCancelled',
  ),
);
Matcher get _retired => throwsA(
  isA<ForumBodyTextPageSessionException>().having(
    (error) => error.failure,
    'failure',
    ForumBodyTextPageSessionFailure.ownerRetired,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('default work yield waits for an actual Flutter frame', (
    tester,
  ) async {
    final token = NovelReaderPaginationCancellationToken();
    var finished = false;
    final waiting = const NovelReaderNativeWorkScheduler()
        .nextFrame(token)
        .then((_) => finished = true);
    expect(finished, isFalse);
    await tester.pump();
    await waiting;
    expect(finished, isTrue);
  });

  test(
    'cancellation releases a frame wait and observes its late failure',
    () async {
      final frame = Completer<void>();
      final scheduler = NovelReaderNativeWorkScheduler(
        nextFrame: () => frame.future,
      );
      final token = NovelReaderPaginationCancellationToken();
      final waiting = scheduler.nextFrame(token);
      token.cancel();
      await expectLater(waiting, _cancelled);
      frame.completeError(StateError('late synthetic frame failure'));
      await Future<void>.delayed(Duration.zero);
    },
  );

  test('a retired request never starts another scheduled frame', () async {
    final token = NovelReaderPaginationCancellationToken()..cancel();
    var calls = 0;
    final scheduler = NovelReaderNativeWorkScheduler(
      nextFrame: () async {
        calls++;
      },
    );
    await expectLater(scheduler.nextFrame(token), _cancelled);
    expect(calls, 0);
  });

  test(
    'budget release wakes a waiter without source restart or native work',
    () async {
      final fixture = _Fixture();
      var finished = false;
      final waiting = const NovelReaderNativeWorkScheduler()
          .waitForLayoutBudget(
            session: fixture.session,
            afterRevision: fixture.session.layoutBudgetRevision,
            token: fixture.token,
          )
          .then((_) => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      fixture.publish();
      final builds = fixture.cache.layoutBuildCount;
      await waiting;
      expect(finished, isTrue);
      expect(fixture.cache.layoutBuildCount, builds);
      expect(fixture.session.isComplete, isTrue);
    },
  );

  test('a release between rejection and subscription cannot be lost', () async {
    final fixture = _Fixture();
    final rejectedRevision = fixture.session.layoutBudgetRevision;
    fixture.publish();
    expect(fixture.session.layoutBudgetRevision, greaterThan(rejectedRevision));
    await const NovelReaderNativeWorkScheduler().waitForLayoutBudget(
      session: fixture.session,
      afterRevision: rejectedRevision,
      token: fixture.token,
    );
  });

  test('session retirement ends a budget wait even when the borrowed cache stays open', () async {
    final fixture = _Fixture();
    final waiting = const NovelReaderNativeWorkScheduler().waitForLayoutBudget(
      session: fixture.session,
      afterRevision: 0,
      token: fixture.token,
    );
    fixture.session.close();
    await expectLater(waiting, _retired);
    expect(fixture.cache.isClosed, isFalse);
    expect(fixture.cache.budgetRevision, 0);
  });

  test(
    'closing the native owner fails a wait instead of retrying a dead cache',
    () async {
      final fixture = _Fixture();
      final waiting = const NovelReaderNativeWorkScheduler()
          .waitForLayoutBudget(
            session: fixture.session,
            afterRevision: 0,
            token: fixture.token,
          );
      fixture.cache.close();
      await expectLater(waiting, _retired);
      expect(fixture.session.isLayoutOwnerRetired, isTrue);
    },
  );

  test(
    'cancelling one wait does not close its source or another waiter',
    () async {
      final fixture = _Fixture();
      final other = NovelReaderPaginationCancellationToken();
      final first = const NovelReaderNativeWorkScheduler().waitForLayoutBudget(
        session: fixture.session,
        afterRevision: 0,
        token: fixture.token,
      );
      final second = const NovelReaderNativeWorkScheduler().waitForLayoutBudget(
        session: fixture.session,
        afterRevision: 0,
        token: other,
      );
      fixture.token.cancel();
      await expectLater(first, _cancelled);
      expect(fixture.session.isClosed, isFalse);
      fixture.publish();
      await second;
      expect(other.isCancelled, isFalse);
    },
  );

  test('invalid revisions do not install persistent waits', () async {
    final fixture = _Fixture();
    for (final revision in [-1, 1]) {
      await expectLater(
        const NovelReaderNativeWorkScheduler().waitForLayoutBudget(
          session: fixture.session,
          afterRevision: revision,
          token: fixture.token,
        ),
        throwsArgumentError,
      );
    }
    fixture.session.close();
    await expectLater(
      const NovelReaderNativeWorkScheduler().waitForLayoutBudget(
        session: fixture.session,
        afterRevision: 0,
        token: fixture.token,
      ),
      _retired,
    );
  });
}
