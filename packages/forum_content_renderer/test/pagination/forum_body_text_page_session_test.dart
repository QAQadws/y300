import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyTextPageSessionLimits _limits({
  int pages = 100,
  int fragments = 1000,
  int paragraphs = 10000,
  int text = 200000,
  int runs = 20000,
  int leases = 32,
  int issues = 4,
}) => ForumBodyTextPageSessionLimits(
  maxPages: pages,
  maxFragments: fragments,
  maxParagraphs: paragraphs,
  maxTextCodeUnits: text,
  maxRuns: runs,
  maxIssuedLeases: leases,
  maxStyleIssues: issues,
);

final class _Fixture {
  _Fixture(String html, {int entries = 8, int bytes = 1 << 22}) {
    document = const ForumBodyParser().parse(
      html: html,
      sourceId: 'session',
      conversionIdentity: 'none',
    );
    cache = ForumBodyParagraphCache(
      maxEntries: entries,
      maxEstimatedBytes: bytes,
    );
    addTearDown(cache.close);
  }
  late final ForumBodyDocument document;
  late final ForumBodyParagraphCache cache;
  ForumBodyTextPageSession session({
    double width = 100,
    double height = 20,
    ForumBodyTextPageSessionLimits? limits,
    TextScaler textScaler = TextScaler.noScaling,
    String id = 'generation-1',
  }) {
    final session = ForumBodyTextPageSession(
      document: document,
      reader: ForumBodyReaderStyle(
        textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 10, height: 1),
        fontRevision: 'ahem',
        linkColor: const Color(0xff0000ff),
      ),
      cache: cache,
      limits: limits ?? _limits(),
      layoutId: id,
      width: width,
      height: height,
      textScaler: textScaler,
    );
    addTearDown(session.close);
    return session;
  }
}

void _advance(ForumBodyTextPageSession session, {int? pages}) {
  var calls = 0;
  while (!session.isComplete &&
      (pages == null || session.snapshot.length < pages)) {
    if (++calls > 10000) fail('Session did not make bounded progress');
    final step = session.advance(maxEvents: 2, maxLines: 1);
    expect(step.eventsRead, lessThanOrEqualTo(2));
    expect(step.linesInspected, lessThanOrEqualTo(1));
    expect(step.paragraphsAdmitted, lessThanOrEqualTo(1));
    expect(step.pagesPublished, lessThanOrEqualTo(1));
    expect(step.waitingForLayoutBudget, isFalse);
    expect(step.madeProgress, isTrue);
  }
}

Matcher _failure(ForumBodyTextPageSessionFailure failure) => throwsA(
  isA<ForumBodyTextPageSessionException>().having(
    (error) => error.failure,
    'failure',
    failure,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'retiring a session during native input resolution cannot revive it as failed',
    () {
      final fixture = _Fixture('<p>a</p>');
      late final ForumBodyTextPageSession session;
      var retired = false;
      final scaler = _CallbackScaler((size) {
        if (!retired) {
          retired = true;
          session.close();
        }
        return size;
      });
      session = fixture.session(textScaler: scaler);
      expect(() => _advance(session), throwsStateError);
      expect(session.isClosed, isTrue);
      expect(session.retainedParagraphCount, 0);
      expect(fixture.cache.isClosed, isFalse);
      expect(fixture.cache.activeLeases, 0);
    },
  );

  for (final retireAt in [1, 2]) {
    test(
      'owner retirement during native scale resolution $retireAt prevents cache refill',
      () {
        final fixture = _Fixture('<p>a</p>');
        var calls = 0;
        final scaler = _CallbackScaler((size) {
          if (++calls == retireAt) fixture.cache.close();
          return size;
        });
        final session = fixture.session(textScaler: scaler);
        expect(
          () => _advance(session),
          _failure(ForumBodyTextPageSessionFailure.ownerRetired),
        );
        expect(session.isClosed, isTrue);
        expect(fixture.cache.isClosed, isTrue);
        expect(fixture.cache.activeLeases, 0);
        expect(fixture.cache.estimatedRetainedBytes, 0);
        expect(fixture.cache.entryCount, 0);
      },
    );
  }

  testWidgets(
    'a late format failure keeps the published page visible and materializable',
    (tester) async {
      final fixture = _Fixture(
        '<p style="margin:0">a</p><blockquote>quote</blockquote>',
      );
      final session = fixture.session(height: 10);
      _advance(session, pages: 1);
      final prefix = session.snapshot;
      final taps = <int>[];
      Widget view(List<ForumBodyParagraphLease> leases) => Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: ForumBodyTextPageSurface(
            snapshot: prefix,
            pageIndex: 0,
            layoutId: prefix.layoutId,
            leases: leases,
            onSourceTap: (_, position) => taps.add(position.sourceRune),
          ),
        ),
      );
      final first = session.preparePageLeases(0);
      await tester.pumpWidget(view(first));
      await tester.tapAt(const Offset(1, 5));
      expect(
        () => _advance(session),
        throwsA(isA<ForumBodyBlockFlowException>()),
      );
      await tester.pump();
      await tester.tapAt(const Offset(1, 5));
      expect(taps, [0, 0]);
      final replacement = session.preparePageLeases(0);
      await tester.pumpWidget(view(replacement));
      expect(first.single.isActive, isFalse);
      expect(replacement.single.isActive, isTrue);
      expect(fixture.cache.layoutBuildCount, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      session.close();
      expect(fixture.cache.activeLeases, 0);
      expect(
        () => view(replacement),
        throwsA(isA<ForumBodyTextPageSurfaceException>()),
      );
    },
  );

  test(
    'native post-layout bytes above the total budget fail permanently and release the transient layout',
    () {
      final fixture = _Fixture('<p>abcdef</p>', bytes: 5000);
      final session = fixture.session();
      expect(
        () => _advance(session),
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.content,
          ),
        ),
      );
      expect(fixture.cache.layoutBuildCount, 1);
      expect(fixture.cache.entryCount, 0);
      expect(fixture.cache.estimatedRetainedBytes, 0);
      expect(session.state, ForumBodyTextPageSessionState.failed);
      expect(session.waitingForLayoutBudget, isFalse);
    },
  );

  test(
    'invalid session limits reject before taking ownership of the borrowed cache',
    () {
      final fixture = _Fixture('');
      for (final limits in [
        _limits(pages: 0),
        _limits(paragraphs: 0),
        _limits(text: -1),
        _limits(leases: 0),
        _limits(issues: -1),
      ]) {
        expect(() => fixture.session(limits: limits), throwsArgumentError);
        expect(fixture.cache.isClosed, isFalse);
      }
    },
  );

  test(
    '100000-character chapter publishes an early fixed prefix with bounded traversal and one layout per call',
    () {
      final fixture = _Fixture(
        '<font>${List.filled(2500, '${'a' * 40}<br>').join()}</font>',
      );
      final session = fixture.session(width: 200, height: 60);
      var calls = 0;
      while (session.snapshot.isEmpty) {
        if (++calls > 100) fail('First page did not become readable');
        final before = fixture.cache.layoutBuildCount;
        final step = session.advance(maxEvents: 2, maxLines: 2);
        expect(step.eventsRead, lessThanOrEqualTo(2));
        expect(step.linesInspected, lessThanOrEqualTo(2));
        expect(fixture.cache.layoutBuildCount - before, lessThanOrEqualTo(1));
        expect(step.madeProgress, isTrue);
      }
      expect(session.resolvedNodeCount, lessThanOrEqualTo(12));
      expect(session.isComplete, isFalse);
      expect(session.snapshot.single.usedHeight, 60);
      final prefix = session.snapshot;
      final builds = fixture.cache.layoutBuildCount;
      final leases = session.preparePageLeases(0);
      expect(leases, hasLength(3));
      expect(() => leases.clear(), throwsUnsupportedError);
      expect(fixture.cache.layoutBuildCount, builds);
      _advance(session, pages: 2);
      expect(prefix, hasLength(1));
      expect(session.snapshot.first, same(prefix.single));
      for (final lease in leases) {
        lease.release();
      }
      expect(session.activeIssuedLeases, 0);
    },
  );

  test(
    'pinned cache pressure retains exact input and resumes after a visible lease releases',
    () {
      final fixture = _Fixture(
        '<p style="margin:0">a</p><p style="margin:0">b</p>',
        entries: 1,
      );
      final session = fixture.session(height: 10);
      _advance(session, pages: 1);
      final prefix = session.snapshot;
      final visible = session.preparePageLeases(0);
      ForumBodyTextPageSessionStep step;
      do {
        step = session.advance(maxEvents: 2, maxLines: 1);
      } while (!step.waitingForLayoutBudget);
      final resolved = session.resolvedNodeCount;
      expect(session.state, ForumBodyTextPageSessionState.active);
      expect(session.retainedParagraphCount, 1);
      expect(fixture.cache.layoutBuildCount, 1);
      final waiting = session.advance(maxEvents: 2, maxLines: 1);
      expect(waiting.waitingForLayoutBudget, isTrue);
      expect(waiting.madeProgress, isFalse);
      expect(session.resolvedNodeCount, resolved);
      visible.single.release();
      final resumed = session.advance(maxEvents: 2, maxLines: 1);
      expect(resumed.eventsRead, 0);
      expect(resumed.paragraphsAdmitted, 1);
      expect(resumed.pagesPublished, 1);
      expect(resumed.waitingForLayoutBudget, isFalse);
      _advance(session);
      expect(session.snapshot.first, same(prefix.single));
      expect(session.snapshot, hasLength(2));
      expect(fixture.cache.layoutBuildCount, 2);
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'an intrinsically oversized native input is a typed failure, not a cache wait',
    () {
      final fixture = _Fixture('<p>a</p>', bytes: 4096);
      final session = fixture.session();
      expect(
        () => _advance(session),
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.content,
          ),
        ),
      );
      expect(session.state, ForumBodyTextPageSessionState.failed);
      expect(session.waitingForLayoutBudget, isFalse);
      expect(session.retainedParagraphCount, 0);
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'late content budget failure keeps published views and removes only unpublished content',
    () {
      final fixture = _Fixture(
        '<p style="margin:0">a</p><p style="margin:0">b</p><p style="margin:0">c</p><p style="margin:0">d</p>',
      );
      final session = fixture.session(limits: _limits(paragraphs: 3));
      _advance(session, pages: 1);
      final prefix = session.snapshot;
      final visible = session.preparePageLeases(0);
      expect(
        () => _advance(session),
        _failure(ForumBodyTextPageSessionFailure.paragraphLimit),
      );
      expect(session.state, ForumBodyTextPageSessionState.failed);
      expect(session.snapshot, same(prefix));
      expect(session.retainedParagraphCount, 2);
      expect(session.retainedTextCodeUnits, 2);
      expect(session.retainedRuns, 2);
      expect(visible.every((lease) => lease.isActive), isTrue);
      final later = session.preparePageLeases(0);
      expect(
        later.map((lease) => lease.layout),
        visible.map((lease) => lease.layout),
      );
      for (final lease in [...visible, ...later]) {
        lease.release();
      }
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'a partially published paragraph survives a later page limit failure',
    () {
      final fixture = _Fixture('<p style="margin:0">abcdefghij</p>');
      final session = fixture.session(width: 20, limits: _limits(pages: 1));
      _advance(session, pages: 1);
      final prefix = session.snapshot;
      expect(
        () => _advance(session),
        throwsA(isA<ForumBodyTextPageException>()),
      );
      expect(session.retainedParagraphCount, 1);
      expect(session.retainedTextCodeUnits, 10);
      expect(session.snapshot, same(prefix));
      final leases = session.preparePageLeases(0);
      expect(leases.single.layout.fragment(0, 2).coverageEndUtf16, 4);
      leases.single.release();
      expect(fixture.cache.activeLeases, 0);
    },
  );

  for (final (limits, failure) in [
    (_limits(text: 0), ForumBodyTextPageSessionFailure.textLimit),
    (_limits(runs: 0), ForumBodyTextPageSessionFailure.runLimit),
  ]) {
    test('pure retained input $failure is checked before native layout', () {
      final fixture = _Fixture('<p>a</p>');
      final session = fixture.session(limits: limits);
      expect(() => _advance(session), _failure(failure));
      expect(fixture.cache.layoutBuildCount, 0);
      expect(session.retainedParagraphCount, 0);
    });
  }

  test('cold page preparation cannot wait forever on its own native pins', () {
    final fixture = _Fixture(
      '<p style="margin:0">a</p><p style="margin:0">b</p>',
      entries: 1,
    );
    final session = fixture.session();
    _advance(session);
    final prefix = session.snapshot;
    expect(
      () => session.preparePageLeases(0),
      _failure(ForumBodyTextPageSessionFailure.pageNotPrepared),
    );
    final preparation = session.openPagePreparation(0);
    preparation.advance(maxFragments: 2);
    expect(
      () => preparation.advance(maxFragments: 2),
      throwsA(isA<ForumBodyTextPagePreparationException>()),
    );
    expect(fixture.cache.activeLeases, 0);
    expect(session.activeIssuedLeases, 0);
    expect(session.state, ForumBodyTextPageSessionState.complete);
    expect(session.snapshot, same(prefix));
  });

  test(
    'issued-view limit is enforced transactionally and released leases are pruned',
    () {
      final fixture = _Fixture('<p style="margin:0">a</p>');
      final session = fixture.session(limits: _limits(leases: 1));
      _advance(session);
      final first = session.preparePageLeases(0);
      expect(
        () => session.preparePageLeases(0),
        _failure(ForumBodyTextPageSessionFailure.leaseLimit),
      );
      expect(first.single.isActive, isTrue);
      first.single.release();
      final second = session.preparePageLeases(0);
      expect(second.single.isActive, isTrue);
      expect(session.activeIssuedLeases, 1);
      session.close();
      expect(second.single.isActive, isFalse);
      expect(fixture.cache.isClosed, isFalse);
      expect(session.retainedParagraphCount, 0);
      expect(() => session.preparePageLeases(0), throwsStateError);
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'a retired generation leaves the borrowed cache available to a replacement',
    () {
      final fixture = _Fixture('<p style="margin:0">a</p>');
      final first = fixture.session();
      _advance(first);
      final visible = first.preparePageLeases(0);
      final second = fixture.session(id: 'generation-2');
      _advance(second);
      final next = second.preparePageLeases(0);
      expect(visible.single.layout, same(next.single.layout));
      expect(fixture.cache.layoutBuildCount, 1);
      first.close();
      expect(visible.single.isActive, isFalse);
      expect(next.single.isActive, isTrue);
      fixture.cache.close();
      expect(next.single.isActive, isFalse);
      expect(
        () => second.preparePageLeases(0),
        _failure(ForumBodyTextPageSessionFailure.ownerRetired),
      );
      expect(second.isClosed, isTrue);
    },
  );

  test(
    'materialization rejects changed actual scaling before issuing mismatched geometry',
    () {
      final fixture = _Fixture('<p style="margin:0">abcdef</p>');
      var factor = 1.0;
      final scaler = _CallbackScaler((size) => size * factor);
      final session = fixture.session(textScaler: scaler);
      _advance(session);
      factor = 2;
      expect(
        () => session.preparePageLeases(0),
        _failure(ForumBodyTextPageSessionFailure.pageNotPrepared),
      );
      final preparation = session.openPagePreparation(0);
      expect(
        () => preparation.advance(maxFragments: 1),
        throwsA(isA<ForumBodyTextPageSurfaceException>()),
      );
      expect(fixture.cache.activeLeases, 0);
      expect(session.activeIssuedLeases, 0);
      expect(session.isComplete, isTrue);
      factor = 1;
      expect(session.preparePageLeases(0).single.isActive, isTrue);
    },
  );

  test(
    'padding-only pages need no retained paragraph or issued lease budget',
    () {
      final fixture = _Fixture('<div style="padding:25px 0"></div>');
      final session = fixture.session(limits: _limits(text: 0, runs: 0));
      _advance(session);
      expect(session.snapshot.map((page) => page.usedHeight), [20, 20, 10]);
      expect(session.preparePageLeases(0), isEmpty);
      expect(session.retainedParagraphCount, 0);
      expect(fixture.cache.layoutBuildCount, 0);
    },
  );

  test(
    'diagnostic retention is bounded and drains independent immutable batches',
    () {
      final fixture = _Fixture(
        '<p style="filter:blur(1px)">a</p><p style="filter:blur(2px)">b</p>',
      );
      final session = fixture.session(limits: _limits(issues: 1));
      _advance(session);
      expect(session.droppedStyleIssueCount, 1);
      final issues = session.takePendingIssues();
      expect(issues, hasLength(1));
      expect(() => issues.clear(), throwsUnsupportedError);
      expect(session.takePendingIssues(), isEmpty);
    },
  );

  test(
    'unsupported container decoration is explicit and never silently painted as plain text',
    () {
      final fixture = _Fixture('<div style="background:red">a</div>');
      final session = fixture.session();
      expect(
        () => _advance(session),
        _failure(ForumBodyTextPageSessionFailure.decoration),
      );
      expect(session.state, ForumBodyTextPageSessionState.failed);
    },
  );

  test(
    'invalid work budgets do not retire a resumable session; empty EOF is explicit',
    () {
      final session = _Fixture('').session();
      expect(
        () => session.advance(maxEvents: 0, maxLines: 1),
        throwsArgumentError,
      );
      expect(session.state, ForumBodyTextPageSessionState.active);
      _advance(session);
      expect(session.snapshot, isEmpty);
      expect(session.snapshot.isComplete, isTrue);
      expect(
        () => session.advance(maxEvents: 1, maxLines: 1),
        throwsStateError,
      );
    },
  );
}

final class _CallbackScaler extends TextScaler {
  const _CallbackScaler(this.scaleSize);
  final double Function(double) scaleSize;
  @override
  double scale(double fontSize) => scaleSize(fontSize);
  @override
  double get textScaleFactor => scaleSize(1);
}
