import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final _reader = ForumBodyReaderStyle(
  textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 10, height: 1),
  fontRevision: 'ahem',
  linkColor: const Color(0xff0000ff),
);

final class _Fixture {
  _Fixture({
    String html =
        '<p style="margin:0">aa</p><p style="margin:0">bb</p><p style="margin:0">cc</p>',
    int entries = 8,
    int bytes = 1 << 22,
    int leases = 12,
    int preparations = 3,
    double height = 100,
    TextScaler textScaler = TextScaler.noScaling,
    bool firstPageOnly = false,
  }) {
    document = const ForumBodyParser().parse(
      html: html,
      sourceId: 'page-preparation',
      conversionIdentity: 'none',
    );
    cache = ForumBodyParagraphCache(
      maxEntries: entries,
      maxEstimatedBytes: bytes,
    );
    session = ForumBodyTextPageSession(
      document: document,
      reader: _reader,
      cache: cache,
      limits: ForumBodyTextPageSessionLimits(
        maxPages: 100,
        maxFragments: 100,
        maxParagraphs: 100,
        maxTextCodeUnits: 10000,
        maxRuns: 1000,
        maxIssuedLeases: leases,
        maxPagePreparations: preparations,
      ),
      layoutId: 'preparation',
      width: 100,
      height: height,
      textScaler: textScaler,
    );
    addTearDown(cache.close);
    addTearDown(session.close);
    var calls = 0;
    while (!session.isComplete &&
        (!firstPageOnly || session.snapshot.isEmpty)) {
      if (++calls > 1000) fail('Session did not reach EOF');
      final step = session.advance(maxEvents: 2, maxLines: 1);
      expect(step.madeProgress, isTrue);
      expect(step.waitingForLayoutBudget, isFalse);
    }
  }
  late final ForumBodyParagraphCache cache;
  late final ForumBodyDocument document;
  late final ForumBodyTextPageSession session;
}

ForumBodyParagraphContent _external() {
  final doc = const ForumBodyParser().parse(
    html: '<p>x</p>',
    sourceId: 'external-pin',
    conversionIdentity: 'none',
  );
  return const ForumBodyParagraphContentBuilder().build(
    document: doc,
    styles: const ForumBodyStyleResolver().resolve(doc, _reader),
    path: '0',
  );
}

Matcher _sessionFailure(ForumBodyTextPageSessionFailure failure) => throwsA(
  isA<ForumBodyTextPageSessionException>().having(
    (error) => error.failure,
    'failure',
    failure,
  ),
);

void _finish(
  ForumBodyTextPagePreparation preparation, {
  int maxFragments = 20,
}) {
  var calls = 0;
  while (!preparation.isReady) {
    if (++calls > 100) fail('Preparation did not become ready');
    final step = preparation.advance(maxFragments: maxFragments);
    expect(step.layoutsBuilt, lessThanOrEqualTo(1));
    expect(step.fragmentsPrepared, lessThanOrEqualTo(maxFragments));
    expect(step.waitingForLayoutBudget, isFalse);
    expect(step.madeProgress, isTrue);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'an active continuation cannot hide an intrinsically oversized page behind a pin wait',
    () {
      final fixture = _Fixture(
        html:
            '<p style="margin:0">a</p><p style="margin:0">bbbbbbbbbbbbbbbbbbbb</p>',
        entries: 1,
        height: 20,
        firstPageOnly: true,
      );
      expect(fixture.session.snapshot.single.fragments, hasLength(2));
      expect(fixture.cache.activeLeases, 1);
      final builds = fixture.cache.layoutBuildCount;
      final preparation = fixture.session.openPagePreparation(0);
      expect(
        () => preparation.advance(maxFragments: 2),
        throwsA(
          isA<ForumBodyTextPagePreparationException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyTextPagePreparationFailure.intrinsicBudget,
          ),
        ),
      );
      expect(fixture.cache.layoutBuildCount, builds);
      expect(fixture.cache.activeLeases, 1);
      expect(fixture.session.snapshot.length, 1);
      expect(fixture.session.reservedViewLeases, 0);
    },
  );

  test(
    'whole-view capacity inspection pauses by fragment budget without entering a release wait',
    () {
      final fixture = _Fixture(
        html:
            '<p style="margin:0">a</p><p style="margin:0">bbbbbbbbbbbbbbbbbbbb</p>',
        entries: 1,
        height: 20,
        firstPageOnly: true,
      );
      final preparation = fixture.session.openPagePreparation(0);
      final builds = fixture.cache.layoutBuildCount;
      final first = preparation.advance(maxFragments: 1);
      expect(first.fragmentsInspected, 1);
      expect(first.fragmentsPrepared, 0);
      expect(first.waitingForLayoutBudget, isFalse);
      expect(first.madeProgress, isTrue);
      expect(
        () => preparation.advance(maxFragments: 1),
        throwsA(isA<ForumBodyTextPagePreparationException>()),
      );
      expect(fixture.cache.layoutBuildCount, builds);
      expect(fixture.cache.activeLeases, 1);
      expect(fixture.session.reservedViewLeases, 0);
    },
  );

  test('a pinned continuation cannot hide the full-page byte lower bound', () {
    final fixture = _Fixture(
      html:
          '<p style="margin:0">a</p><p style="margin:0">bbbbbbbbbbbbbbbbbbbb</p>',
      entries: 8,
      bytes: 8000,
      height: 20,
      firstPageOnly: true,
    );
    final preparation = fixture.session.openPagePreparation(0);
    final builds = fixture.cache.layoutBuildCount;
    expect(
      () => preparation.advance(maxFragments: 8),
      throwsA(isA<ForumBodyTextPagePreparationException>()),
    );
    expect(fixture.cache.layoutBuildCount, builds);
    expect(fixture.cache.activeLeases, 1);
    expect(fixture.session.reservedViewLeases, 0);
  });

  test(
    'whole-view probes count repeated BR windows as one actual native input',
    () {
      final fixture = _Fixture(html: '<span>a<br><br></span>', entries: 1);
      fixture.cache.clearUnpinned();
      final external = fixture.cache.acquire(content: _external(), width: 100);
      final builds = fixture.cache.layoutBuildCount;
      final preparation = fixture.session.openPagePreparation(0);
      final first = preparation.advance(maxFragments: 1);
      expect(first.fragmentsInspected, 1);
      expect(first.waitingForLayoutBudget, isFalse);
      final second = preparation.advance(maxFragments: 1);
      expect(second.fragmentsInspected, 1);
      expect(second.waitingForLayoutBudget, isTrue);
      expect(fixture.cache.layoutBuildCount, builds);
      external.release();
      _finish(preparation, maxFragments: 1);
      final leases = preparation.takeLeases();
      expect(leases, hasLength(2));
      expect(leases.first.layout, same(leases.last.layout));
      for (final lease in leases) {
        lease.release();
      }
    },
  );

  test(
    'release during metadata inspection requests fresh admission rather than a lost-event wait',
    () {
      var armed = false;
      var calls = 0;
      late ForumBodyParagraphLease external;
      final fixture = _Fixture(
        html: '<p style="margin:0">a</p><p style="margin:0">b</p>',
        entries: 2,
        textScaler: _CallbackScaler((size) {
          if (armed && ++calls == 2) external.release();
          return size;
        }),
      );
      fixture.cache.clearUnpinned();
      external = fixture.cache.acquire(content: _external(), width: 100);
      final preparation = fixture.session.openPagePreparation(0);
      preparation.advance(maxFragments: 2);
      armed = true;
      final inspected = preparation.advance(maxFragments: 2);
      expect(inspected.fragmentsInspected, 2);
      expect(external.isActive, isFalse);
      expect(inspected.waitingForLayoutBudget, isFalse);
      expect(preparation.advance(maxFragments: 2).isReady, isTrue);
      preparation.close();
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'external aliases of prepared native entries do not hide an intrinsic capacity failure',
    () {
      final fixture = _Fixture(
        html: '<p style="margin:0">a</p><p style="margin:0">b</p>',
        entries: 1,
      );
      final alias = ForumBodyTextPageSession(
        document: fixture.document,
        reader: _reader,
        cache: fixture.cache,
        limits: fixture.session.limits,
        layoutId: 'visible-alias',
        width: 100,
        height: 10,
      );
      addTearDown(alias.close);
      while (alias.snapshot.isEmpty) {
        alias.advance(maxEvents: 2, maxLines: 1);
      }
      final visible = alias.preparePageLeases(0);
      final preparation = fixture.session.openPagePreparation(0);
      preparation.advance(maxFragments: 1);
      expect(fixture.cache.activeLeases, 2);
      expect(
        () => preparation.advance(maxFragments: 1),
        throwsA(isA<ForumBodyTextPagePreparationException>()),
      );
      expect(visible.single.isActive, isTrue);
      expect(fixture.cache.activeLeases, 1);
      expect(fixture.session.reservedViewLeases, 0);
      visible.single.release();
    },
  );

  for (final retireCache in [false, true]) {
    test(
      'retirement during whole-view inspection releases partial work: cache=$retireCache',
      () {
        var armed = false;
        var calls = 0;
        late final _Fixture fixture;
        fixture = _Fixture(
          html: '<p style="margin:0">a</p><p style="margin:0">b</p>',
          entries: 2,
          textScaler: _CallbackScaler((size) {
            if (armed && ++calls == 2) {
              if (retireCache) {
                fixture.cache.close();
              } else {
                fixture.session.close();
              }
            }
            return size;
          }),
        );
        fixture.cache.clearUnpinned();
        final external = fixture.cache.acquire(
          content: _external(),
          width: 100,
        );
        final preparation = fixture.session.openPagePreparation(0);
        preparation.advance(maxFragments: 2);
        armed = true;
        expect(
          () => preparation.advance(maxFragments: 2),
          retireCache
              ? _sessionFailure(ForumBodyTextPageSessionFailure.ownerRetired)
              : throwsStateError,
        );
        expect(preparation.state, ForumBodyTextPagePreparationState.closed);
        expect(fixture.session.reservedViewLeases, 0);
        expect(fixture.cache.activeLeases, retireCache ? 0 : 1);
        external.release();
        expect(fixture.cache.activeLeases, 0);
      },
    );
  }

  test(
    'owned native bytes can prove a page too large even with other pinned entries',
    () {
      final fixture = _Fixture(
        html: '<p style="margin:0">abcdef</p><p style="margin:0">ghijkl</p>',
        bytes: 9900,
      );
      fixture.cache.clearUnpinned();
      final external = fixture.cache.acquire(content: _external(), width: 100);
      final preparation = fixture.session.openPagePreparation(0);
      preparation.advance(maxFragments: 1);
      expect(
        () => preparation.advance(maxFragments: 1),
        throwsA(isA<ForumBodyTextPagePreparationException>()),
      );
      expect(preparation.waitingForLayoutBudget, isFalse);
      expect(external.isActive, isTrue);
      expect(fixture.cache.activeLeases, 1);
      expect(fixture.session.reservedViewLeases, 0);
      external.release();
    },
  );

  test(
    'a discarded native build is not a prepared fragment while metadata inspection is bounded progress',
    () {
      final fixture = _Fixture(
        html: '<p style="margin:0">abcdef</p>',
        bytes: 9500,
      );
      fixture.cache.clearUnpinned();
      final external = fixture.cache.acquire(content: _external(), width: 100);
      final preparation = fixture.session.openPagePreparation(0);
      final step = preparation.advance(maxFragments: 1);
      expect(step.layoutsBuilt, 1);
      expect(step.fragmentsPrepared, 0);
      expect(step.waitingForLayoutBudget, isTrue);
      expect(step.fragmentsInspected, 1);
      expect(step.madeProgress, isTrue);
      external.release();
      expect(preparation.advance(maxFragments: 1).isReady, isTrue);
      preparation.close();
      expect(fixture.cache.activeLeases, 0);
      expect(fixture.session.reservedViewLeases, 0);
    },
  );

  test(
    'published-page preparation remains valid after the source session fails later',
    () {
      final fixture = _Fixture(
        html:
            '<p style="margin:0">aa</p><p style="margin:0">bb</p><blockquote>quote</blockquote>',
        height: 20,
        firstPageOnly: true,
      );
      fixture.cache.clearUnpinned();
      final preparation = fixture.session.openPagePreparation(0);
      preparation.advance(maxFragments: 1);
      expect(() {
        while (!fixture.session.isComplete) {
          fixture.session.advance(maxEvents: 2, maxLines: 1);
        }
      }, throwsA(isA<ForumBodyBlockFlowException>()));
      expect(fixture.session.state, ForumBodyTextPageSessionState.failed);
      _finish(preparation);
      final leases = preparation.takeLeases();
      expect(leases, hasLength(2));
      expect(leases.every((lease) => lease.isActive), isTrue);
      expect(fixture.session.reservedViewLeases, 0);
    },
  );

  for (final retireOwner in [false, true]) {
    test(
      'scale callback retirement during page preparation cannot publish late leases: owner=$retireOwner',
      () {
        var retire = false;
        late final _Fixture fixture;
        final scaler = _CallbackScaler((size) {
          if (retire) {
            if (retireOwner) {
              fixture.cache.close();
            } else {
              fixture.session.close();
            }
          }
          return size;
        });
        fixture = _Fixture(textScaler: scaler);
        fixture.cache.clearUnpinned();
        final preparation = fixture.session.openPagePreparation(0);
        retire = true;
        if (retireOwner) {
          expect(
            () => preparation.advance(maxFragments: 1),
            _sessionFailure(ForumBodyTextPageSessionFailure.ownerRetired),
          );
        } else {
          expect(() => preparation.advance(maxFragments: 1), throwsStateError);
        }
        expect(preparation.state, ForumBodyTextPagePreparationState.closed);
        expect(fixture.session.isClosed, isTrue);
        expect(fixture.session.reservedViewLeases, 0);
        expect(fixture.cache.activeLeases, 0);
        expect(preparation.takeLeases, throwsStateError);
      },
    );
  }

  test('issued views and pending reservations share the same lease budget', () {
    final fixture = _Fixture(
      html: '<p style="margin:0">a</p><p style="margin:0">b</p>',
      height: 10,
      leases: 2,
    );
    final visible = fixture.session.preparePageLeases(0);
    final next = fixture.session.openPagePreparation(1);
    expect(fixture.session.activeIssuedLeases, 1);
    expect(fixture.session.reservedViewLeases, 1);
    expect(
      () => fixture.session.openPagePreparation(0),
      _sessionFailure(ForumBodyTextPageSessionFailure.leaseLimit),
    );
    next.close();
    expect(visible.single.isActive, isTrue);
    expect(fixture.session.reservedViewLeases, 0);
    visible.single.release();
  });

  test(
    'cold fragments shape at most once per step and transfer only after final validation',
    () {
      final fixture = _Fixture();
      fixture.cache.clearUnpinned();
      final before = fixture.cache.layoutBuildCount;
      final preparation = fixture.session.openPagePreparation(0);
      expect(fixture.session.reservedViewLeases, 3);
      for (var index = 0; index < 3; index++) {
        final step = preparation.advance(maxFragments: 20);
        expect(step.layoutsBuilt, 1);
        expect(step.fragmentsPrepared, 1);
        expect(preparation.preparedFragmentCount, index + 1);
        if (index < 2) expect(preparation.takeLeases, throwsStateError);
      }
      expect(preparation.isReady, isTrue);
      final leases = preparation.takeLeases();
      expect(leases, hasLength(3));
      expect(() => leases.clear(), throwsUnsupportedError);
      expect(fixture.session.pendingPreparationCount, 0);
      expect(fixture.session.reservedViewLeases, 0);
      expect(fixture.session.activeIssuedLeases, 3);
      expect(fixture.cache.layoutBuildCount - before, 3);
      preparation.close();
      expect(preparation.state, ForumBodyTextPagePreparationState.transferred);
      expect(leases.every((lease) => lease.isActive), isTrue);
      fixture.session.close();
      expect(leases.every((lease) => !lease.isActive), isTrue);
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'warm convenience never shapes and cold misses release every temporary reservation',
    () {
      final fixture = _Fixture();
      final before = fixture.cache.layoutBuildCount;
      final warm = fixture.session.preparePageLeases(0);
      expect(fixture.cache.layoutBuildCount, before);
      for (final lease in warm) {
        lease.release();
      }
      fixture.cache.clearUnpinned();
      expect(
        () => fixture.session.preparePageLeases(0),
        _sessionFailure(ForumBodyTextPageSessionFailure.pageNotPrepared),
      );
      expect(fixture.cache.layoutBuildCount, before);
      expect(fixture.cache.activeLeases, 0);
      expect(fixture.session.reservedViewLeases, 0);
      expect(fixture.session.pendingPreparationCount, 0);
      expect(fixture.session.isComplete, isTrue);
    },
  );

  test(
    'warm partial work is retained on a miss and continues from that exact fragment',
    () {
      final fixture = _Fixture();
      final visible = fixture.session.preparePageLeases(0);
      visible[1].release();
      visible[2].release();
      fixture.cache.clearUnpinned();
      final preparation = fixture.session.openPagePreparation(0);
      final before = fixture.cache.layoutBuildCount;
      expect(preparation.tryPrepareCached(), isFalse);
      expect(preparation.preparedFragmentCount, 1);
      expect(fixture.cache.layoutBuildCount, before);
      _finish(preparation);
      expect(fixture.cache.layoutBuildCount - before, 2);
      final leases = preparation.takeLeases();
      expect(leases.first.layout, same(visible.first.layout));
      for (final lease in [...visible, ...leases]) {
        lease.release();
      }
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'canceling partial preparation releases pins and the entire reservation',
    () {
      final fixture = _Fixture();
      fixture.cache.clearUnpinned();
      final preparation = fixture.session.openPagePreparation(0);
      preparation.advance(maxFragments: 1);
      expect(fixture.cache.activeLeases, 1);
      preparation.close();
      preparation.close();
      expect(preparation.state, ForumBodyTextPagePreparationState.closed);
      expect(fixture.cache.activeLeases, 0);
      expect(fixture.session.reservedViewLeases, 0);
      expect(fixture.session.pendingPreparationCount, 0);
      expect(() => preparation.advance(maxFragments: 1), throwsStateError);
      expect(preparation.takeLeases, throwsStateError);
      expect(fixture.session.openPagePreparation(0).expectedFragmentCount, 3);
    },
  );

  test('ready-but-untransferred leases stay owned by the preparation', () {
    final fixture = _Fixture();
    final preparation = fixture.session.openPagePreparation(0);
    expect(preparation.tryPrepareCached(), isTrue);
    expect(fixture.cache.activeLeases, 3);
    expect(fixture.session.activeIssuedLeases, 0);
    preparation.close();
    expect(fixture.cache.activeLeases, 0);
    expect(fixture.session.reservedViewLeases, 0);
  });

  test('concurrent reservations include incomplete and ready preparations', () {
    final fixture = _Fixture(leases: 5);
    final first = fixture.session.openPagePreparation(0);
    expect(
      () => fixture.session.openPagePreparation(0),
      _sessionFailure(ForumBodyTextPageSessionFailure.leaseLimit),
    );
    first.tryPrepareCached();
    expect(
      () => fixture.session.preparePageLeases(0),
      _sessionFailure(ForumBodyTextPageSessionFailure.leaseLimit),
    );
    first.close();
    final second = fixture.session.openPagePreparation(0);
    expect(second.expectedFragmentCount, 3);
    expect(fixture.session.reservedViewLeases, 3);
  });

  test(
    'zero-fragment requests still obey the active-preparation count budget',
    () {
      final fixture = _Fixture(
        html: '<div style="padding:20px 0"></div>',
        preparations: 2,
        height: 20,
      );
      final first = fixture.session.openPagePreparation(0);
      final second = fixture.session.openPagePreparation(1);
      expect(fixture.session.reservedViewLeases, 0);
      expect(
        () => fixture.session.openPagePreparation(0),
        _sessionFailure(ForumBodyTextPageSessionFailure.preparationLimit),
      );
      first.close();
      expect(second.advance(maxFragments: 1).isReady, isTrue);
      expect(second.takeLeases(), isEmpty);
      expect(fixture.session.pendingPreparationCount, 0);
      expect(fixture.cache.layoutBuildCount, 0);
    },
  );

  test(
    'external native pins wait without losing completed fragments and resume after release',
    () {
      final fixture = _Fixture(
        html: '<p style="margin:0">a</p><p style="margin:0">b</p>',
        entries: 2,
      );
      fixture.cache.clearUnpinned();
      final external = fixture.cache.acquire(content: _external(), width: 100);
      final preparation = fixture.session.openPagePreparation(0);
      preparation.advance(maxFragments: 20);
      final before = fixture.cache.layoutBuildCount;
      final waiting = preparation.advance(maxFragments: 20);
      expect(waiting.waitingForLayoutBudget, isTrue);
      expect(waiting.fragmentsInspected, 2);
      expect(waiting.madeProgress, isTrue);
      final unchanged = preparation.advance(maxFragments: 20);
      expect(unchanged.waitingForLayoutBudget, isTrue);
      expect(unchanged.fragmentsInspected, 0);
      expect(unchanged.madeProgress, isFalse);
      expect(preparation.preparedFragmentCount, 1);
      expect(fixture.cache.layoutBuildCount, before);
      external.release();
      expect(preparation.advance(maxFragments: 20).isReady, isTrue);
      expect(preparation.preparedFragmentCount, 2);
      expect(fixture.cache.layoutBuildCount - before, 1);
      preparation.close();
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'a page larger than its own native entry capacity fails instead of self-waiting',
    () {
      final fixture = _Fixture(
        html: '<p style="margin:0">a</p><p style="margin:0">b</p>',
        entries: 1,
      );
      fixture.cache.clearUnpinned();
      final preparation = fixture.session.openPagePreparation(0);
      preparation.advance(maxFragments: 20);
      expect(
        () => preparation.advance(maxFragments: 20),
        throwsA(
          isA<ForumBodyTextPagePreparationException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyTextPagePreparationFailure.intrinsicBudget,
          ),
        ),
      );
      expect(preparation.state, ForumBodyTextPagePreparationState.failed);
      expect(preparation.waitingForLayoutBudget, isFalse);
      expect(fixture.cache.activeLeases, 0);
      expect(fixture.session.reservedViewLeases, 0);
      expect(fixture.session.isComplete, isTrue);
    },
  );

  test(
    'shared BR line windows can prepare multiple leases over one native entry',
    () {
      final fixture = _Fixture(html: '<span>a<br><br></span>', entries: 1);
      fixture.cache.clearUnpinned();
      final before = fixture.cache.layoutBuildCount;
      final preparation = fixture.session.openPagePreparation(0);
      _finish(preparation);
      final leases = preparation.takeLeases();
      expect(leases, hasLength(2));
      expect(leases.first.layout, same(leases.last.layout));
      expect(fixture.cache.layoutBuildCount - before, 1);
      expect(fixture.session.reservedViewLeases, 0);
    },
  );

  test('session close rolls back every concurrent pending request', () {
    final fixture = _Fixture();
    fixture.cache.clearUnpinned();
    final first = fixture.session.openPagePreparation(0);
    final second = fixture.session.openPagePreparation(0);
    first.advance(maxFragments: 1);
    second.advance(maxFragments: 1);
    fixture.session.close();
    expect(first.state, ForumBodyTextPagePreparationState.closed);
    expect(second.state, ForumBodyTextPagePreparationState.closed);
    expect(first.takeLeases, throwsStateError);
    expect(second.tryPrepareCached, throwsStateError);
    expect(fixture.cache.activeLeases, 0);
    expect(fixture.session.reservedViewLeases, 0);
    expect(fixture.session.pendingPreparationCount, 0);
    expect(fixture.cache.isClosed, isFalse);
  });

  test(
    'owner retirement invalidates half-prepared work and prevents late transfer',
    () {
      final fixture = _Fixture();
      fixture.cache.clearUnpinned();
      final preparation = fixture.session.openPagePreparation(0);
      preparation.advance(maxFragments: 1);
      fixture.cache.close();
      expect(
        () => preparation.advance(maxFragments: 1),
        _sessionFailure(ForumBodyTextPageSessionFailure.ownerRetired),
      );
      expect(preparation.state, ForumBodyTextPagePreparationState.closed);
      expect(fixture.session.isClosed, isTrue);
      expect(fixture.cache.activeLeases, 0);
      expect(fixture.cache.estimatedRetainedBytes, 0);
      expect(fixture.session.reservedViewLeases, 0);
    },
  );

  testWidgets(
    'a fully prepared cold page mounts and hits its original source order',
    (tester) async {
      final fixture = _Fixture(
        html: '<p style="margin:0">aa</p><p style="margin:0">bb</p>',
        height: 20,
      );
      fixture.cache.clearUnpinned();
      final preparation = fixture.session.openPagePreparation(0);
      _finish(preparation);
      final leases = preparation.takeLeases();
      final taps = <int>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: ForumBodyTextPageSurface(
              snapshot: preparation.snapshot,
              pageIndex: 0,
              layoutId: preparation.snapshot.layoutId,
              leases: leases,
              onSourceTap: (_, position) => taps.add(position.sourceRune),
            ),
          ),
        ),
      );
      final builds = fixture.cache.layoutBuildCount;
      await tester.tapAt(const Offset(1, 15));
      expect(taps, [2]);
      expect(fixture.cache.layoutBuildCount, builds);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'invalid work budget and premature take leave the request resumable',
    () {
      final fixture = _Fixture();
      final preparation = fixture.session.openPagePreparation(0);
      expect(() => preparation.advance(maxFragments: 0), throwsArgumentError);
      expect(preparation.takeLeases, throwsStateError);
      expect(preparation.state, ForumBodyTextPagePreparationState.active);
      expect(preparation.tryPrepareCached(), isTrue);
      final leases = preparation.takeLeases();
      expect(preparation.takeLeases, throwsStateError);
      expect(leases.every((lease) => lease.isActive), isTrue);
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
