import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final _reader = ForumBodyReaderStyle(
  textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
  fontRevision: 'session-emphasis-ahem',
  linkColor: Color(0xff0000ff),
);
const _limits = ForumBodyTextPageSessionLimits(
  maxPages: 100,
  maxFragments: 1000,
  maxParagraphs: 100,
  maxTextCodeUnits: 200000,
  maxRuns: 20000,
  maxIssuedLeases: 32,
);

final class _Fixture {
  _Fixture(String html, {int entries = 32}) {
    document = const ForumBodyParser().parse(
      html: html,
      sourceId: 'emphasis-session',
      conversionIdentity: 'none',
    );
    cache = ForumBodyParagraphCache(
      maxEntries: entries,
      maxEstimatedBytes: 1 << 24,
    );
    addTearDown(cache.close);
  }
  late final ForumBodyDocument document;
  late final ForumBodyParagraphCache cache;
  ForumBodyTextPageSession open({
    double width = 140,
    double height = 80,
    String id = 'session-layout',
    TextScaler scaler = TextScaler.noScaling,
    ForumBodyTextPageSessionLimits limits = _limits,
    int? pageEntries,
  }) {
    final session = ForumBodyTextPageSession(
      document: document,
      reader: _reader,
      cache: cache,
      limits: limits,
      layoutId: id,
      width: width,
      height: height,
      textScaler: scaler,
      maxNativeEntriesPerPage: pageEntries,
    );
    addTearDown(session.close);
    return session;
  }

  ForumBodyParagraphLease pin(double width) {
    final document = const ForumBodyParser().parse(
      html: '<p>foreign</p>',
      sourceId: 'foreign-source',
      conversionIdentity: 'none',
    );
    final content = const ForumBodyParagraphContentBuilder().build(
      document: document,
      path: '0',
      styles: const ForumBodyStyleResolver().resolve(document, _reader),
    );
    final lease = cache.acquire(content: content, width: width);
    addTearDown(lease.release);
    return lease;
  }
}

ForumBodyTextPageSessionStep _step(
  _Fixture fixture,
  ForumBodyTextPageSession session,
) {
  final pictures = fixture.cache.pictureBuildCount;
  final step = session.advance(maxEvents: 2, maxLines: 1, maxFormatParts: 1);
  expect(step.eventsRead, lessThanOrEqualTo(2));
  expect(step.flowWorkDone, lessThanOrEqualTo(2));
  expect(step.formatUnitsPrepared, lessThanOrEqualTo(1));
  expect(step.layoutsBuilt, lessThanOrEqualTo(1));
  expect(step.linesInspected, lessThanOrEqualTo(1));
  expect(step.paragraphsAdmitted, lessThanOrEqualTo(1));
  expect(step.pagesPublished, lessThanOrEqualTo(1));
  expect(fixture.cache.pictureBuildCount, pictures);
  expect(step.madeProgress || step.waitingForLayoutBudget, isTrue);
  return step;
}

void _finish(_Fixture fixture, ForumBodyTextPageSession session, {int? pages}) {
  for (var n = 0; !session.isComplete; n++) {
    if (pages != null && session.snapshot.length >= pages) return;
    if (n > 50000) fail('Session did not finish bounded preparation');
    expect(_step(fixture, session).waitingForLayoutBudget, isFalse);
  }
}

List<ForumBodyPreparedTextFragment> _page(
  _Fixture fixture,
  ForumBodyTextPageSession session,
  int index,
) {
  final job = session.openPagePreparation(index);
  addTearDown(job.close);
  for (var n = 0; !job.isReady; n++) {
    if (n > 50000) fail('Page did not finish bounded preparation');
    final before =
        fixture.cache.layoutBuildCount + fixture.cache.pictureBuildCount;
    final step = job.advance(maxFragments: 1, maxParts: 1);
    expect(step.partsInspected + step.partsPrepared, lessThanOrEqualTo(1));
    expect(step.waitingForLayoutBudget, isFalse);
    expect(
      fixture.cache.layoutBuildCount + fixture.cache.pictureBuildCount - before,
      lessThanOrEqualTo(1),
    );
  }
  final fragments = job.takeFragments();
  job.close();
  addTearDown(() {
    for (final fragment in fragments) {
      fragment.close();
    }
  });
  validateForumBodyPreparedTextPageBinding(
    snapshot: session.snapshot,
    pageIndex: index,
    layoutId: session.snapshot.layoutId,
    fragments: fragments,
  );
  return fragments;
}

String _copy(
  ForumBodyTextPage page,
  List<ForumBodyPreparedTextFragment> bindings,
) => [
  for (var n = 0; n < bindings.length; n++)
    bindings[n].projection.text.substring(
      page.fragments[n].coverageStartUtf16,
      page.fragments[n].coverageEndUtf16,
    ),
].join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('actual flow admits emphasis between ordinary and ruby paragraphs', () {
    final fixture = _Fixture(
      '<p style="margin:0">plain</p>'
      '<p style="margin:0;text-emphasis:\'X\' red">A<b>B</b>C</p>'
      '<p style="margin:0">x<ruby>D<rt>d</rt></ruby>y</p>',
    );
    final session = fixture.open(height: 1000);
    _finish(fixture, session);
    expect(session.retainedParagraphCount, 3);
    expect(fixture.cache.activeLeases, 0);
    expect(session.snapshot, hasLength(1));
    expect(session.snapshot.single.fragments.map((f) => f.kind), [
      ForumBodyTextPageFragmentKind.paragraph,
      ForumBodyTextPageFragmentKind.emphasis,
      ForumBodyTextPageFragmentKind.inline,
    ]);
    final bindings = _page(fixture, session, 0);
    expect(bindings[1], isA<ForumBodyPreparedEmphasisFragment>());
    expect(_copy(session.snapshot.single, bindings), 'plainABCxDdy');
    final emphasis = (bindings[1] as ForumBodyPreparedEmphasisFragment).view;
    expect(emphasis.input.paragraph.content.projection.text, 'ABC');
    expect(emphasis.glyphBoxes(1, 2), isNotEmpty);
    expect(session.activeIssuedLeases, greaterThan(2));
    session.close();
    expect(fixture.cache.activeLeases, 0);
    expect(fixture.cache.isClosed, isFalse);
  });

  for (final body in ['AB\nCD\nEF', 'A\n', '؀A e<b>́</b> 👩‍👩‍👧‍👦']) {
    test('complete source coverage survives narrow pages: $body', () {
      final fixture = _Fixture(
        '<p style="margin:0;white-space:pre-wrap;line-height:.4;'
        'text-emphasis:\'X\' red">$body</p>',
      );
      final session = fixture.open(
        width: 40,
        height: body.contains('👩') ? 512 : 40,
      );
      _finish(fixture, session);
      final text = StringBuffer();
      var offset = 0;
      for (var index = 0; index < session.snapshot.length; index++) {
        final page = session.snapshot[index],
            bindings = _page(fixture, session, index);
        for (final fragment in page.fragments) {
          expect(fragment.coverageStartUtf16, offset);
          offset = fragment.coverageEndUtf16;
          expect(fragment.kind, ForumBodyTextPageFragmentKind.emphasis);
        }
        text.write(_copy(page, bindings));
        final builds = fixture.cache.layoutBuildCount,
            pictures = fixture.cache.pictureBuildCount;
        for (final binding in bindings) {
          final view = (binding as ForumBodyPreparedEmphasisFragment).view;
          final recorder = ui.PictureRecorder();
          view.paint(Canvas(recorder), Offset.zero);
          recorder.endRecording().dispose();
          binding.close();
        }
        expect(fixture.cache.layoutBuildCount, builds);
        expect(fixture.cache.pictureBuildCount, pictures);
        expect(fixture.cache.activeLeases, 0);
      }
      final original = const ForumBodyParagraphContentBuilder().build(
        document: fixture.document,
        path: '0',
        styles: const ForumBodyStyleResolver().resolve(
          fixture.document,
          _reader,
        ),
      );
      expect(text.toString(), original.projection.text);
      expect(offset, original.projection.text.length);
    });
  }

  test(
    'foreign pins suspend numeric measurement and the same session resumes',
    () {
      final fixture = _Fixture(
        '<p style="text-emphasis:\'X\'">ABC</p>',
        entries: 6,
      );
      final pins = [fixture.pin(2), fixture.pin(3)];
      final session = fixture.open();
      for (var n = 0; !session.waitingForLayoutBudget; n++) {
        if (n > 20000) fail('Expected a bounded foreign-pin wait');
        _step(fixture, session);
      }
      final nodes = session.resolvedNodeCount,
          builds = fixture.cache.layoutBuildCount,
          prefix = session.snapshot;
      for (var n = 0; n < 3; n++) {
        expect(_step(fixture, session).waitingForLayoutBudget, isTrue);
        expect(fixture.cache.layoutBuildCount, builds);
        expect(session.resolvedNodeCount, nodes);
        expect(session.snapshot, same(prefix));
      }
      for (final pin in pins) {
        pin.release();
      }
      _finish(fixture, session);
      expect(session.resolvedNodeCount, nodes);
      expect(session.retainedParagraphCount, 1);
      final binding = _page(fixture, session, 0).single;
      expect(binding, isA<ForumBodyPreparedEmphasisFragment>());
      binding.close();
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'an intrinsically insufficient numeric cache fails without native work',
    () {
      final fixture = _Fixture(
        '<p style="text-emphasis:\'X\'">A</p>',
        entries: 4,
      );
      final session = fixture.open();
      expect(
        () => _finish(fixture, session),
        throwsA(isA<ForumBodyParagraphBudgetException>()),
      );
      expect(session.state, ForumBodyTextPageSessionState.failed);
      expect(session.snapshot, isEmpty);
      expect(fixture.cache.layoutBuildCount, 0);
      expect(fixture.cache.pictureBuildCount, 0);
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'a late format failure preserves and rematerializes the emphasis prefix',
    () {
      final fixture = _Fixture(
        '<p style="margin:0;text-emphasis:\'X\'">AB CD EF</p>'
        '<div style="position:absolute">unsupported container</div>',
      );
      final session = fixture.open(width: 40, height: 40);
      _finish(fixture, session, pages: 1);
      final prefix = session.snapshot;
      final first = _page(fixture, session, 0);
      expect(
        () => _finish(fixture, session),
        throwsA(isA<ForumBodyBlockFlowException>()),
      );
      expect(session.state, ForumBodyTextPageSessionState.failed);
      expect(session.snapshot.first, same(prefix.first));
      expect(
        (first.single as ForumBodyPreparedEmphasisFragment).view.glyphBoxes(
          0,
          1,
        ),
        isNotEmpty,
      );
      final second = _page(fixture, session, 0);
      expect(_copy(session.snapshot.first, second), _copy(prefix.first, first));
      session.close();
      expect(first.single.isActive, isFalse);
      expect(second.single.isActive, isFalse);
      expect(fixture.cache.activeLeases, 0);
    },
  );

  for (final retireOwner in [false, true]) {
    test(
      'retirement during emphasis scale resolution drains work: $retireOwner',
      () {
        final fixture = _Fixture('<p style="text-emphasis:\'X\'">ABC</p>');
        late final ForumBodyTextPageSession session;
        var retired = false;
        session = fixture.open(
          scaler: _Scaler((size) {
            if (!retired) {
              retired = true;
              if (retireOwner) {
                fixture.cache.close();
              } else {
                session.close();
              }
            }
            return size;
          }),
        );
        expect(() => _finish(fixture, session), throwsA(anything));
        expect(session.isClosed, isTrue);
        expect(session.retainedParagraphCount, 0);
        expect(fixture.cache.activeLeases, 0);
        expect(fixture.cache.layoutBuildCount, 0);
      },
    );
  }

  test(
    'closing in-flight numeric measurement releases only this generation',
    () {
      final fixture = _Fixture('<p style="text-emphasis:\'X\'">ABC DEF</p>');
      final old = fixture.open();
      for (var n = 0; fixture.cache.activeLeases < 3; n++) {
        if (n > 20000) fail('Expected active numeric resources');
        _step(fixture, old);
      }
      old.close();
      expect(fixture.cache.activeLeases, 0);
      expect(fixture.cache.isClosed, isFalse);
      expect(() => old.advance(maxEvents: 1, maxLines: 1), throwsStateError);
      final replacement = fixture.open(id: 'replacement');
      _finish(fixture, replacement);
      expect(_page(fixture, replacement, 0).single.isActive, isTrue);
      replacement.close();
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'the session accounts for all retained emphasis projections and styles',
    () {
      final fixture = _Fixture('<p style="text-emphasis:\'X\'">ABC</p>');
      const limits = ForumBodyTextPageSessionLimits(
        maxPages: 10,
        maxFragments: 10,
        maxParagraphs: 10,
        maxTextCodeUnits: 3,
        maxRuns: 100,
        maxIssuedLeases: 10,
      );
      final session = fixture.open(limits: limits);
      expect(
        () => _finish(fixture, session),
        throwsA(
          isA<ForumBodyTextPageSessionException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyTextPageSessionFailure.textLimit,
          ),
        ),
      );
      expect(fixture.cache.layoutBuildCount, greaterThan(0));
      expect(fixture.cache.pictureBuildCount, 0);
      expect(session.retainedTextCodeUnits, 0);
      expect(session.retainedRuns, 0);
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'pending typed delivery reserves two handles and releases on cancellation',
    () {
      final fixture = _Fixture('<p style="text-emphasis:\'X\'">ABC</p>');
      const limits = ForumBodyTextPageSessionLimits(
        maxPages: 10,
        maxFragments: 10,
        maxParagraphs: 10,
        maxTextCodeUnits: 1000,
        maxRuns: 100,
        maxIssuedLeases: 3,
      );
      final session = fixture.open(limits: limits);
      _finish(fixture, session);
      final job = session.openPagePreparation(0);
      expect(session.reservedViewLeases, 2);
      expect(
        () => session.openPagePreparation(0),
        throwsA(
          isA<ForumBodyTextPageSessionException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyTextPageSessionFailure.leaseLimit,
          ),
        ),
      );
      job.close();
      expect(session.reservedViewLeases, 0);
      expect(() => session.preparePageLeases(0), throwsStateError);
      final first = _page(fixture, session, 0);
      expect(session.activeIssuedLeases, 2);
      first.single.close();
      final builds = fixture.cache.layoutBuildCount,
          pictures = fixture.cache.pictureBuildCount;
      final warm = session.preparePageFragments(0);
      expect(warm.single, isA<ForumBodyPreparedEmphasisFragment>());
      expect(session.activeIssuedLeases, 2);
      expect(fixture.cache.layoutBuildCount, builds);
      expect(fixture.cache.pictureBuildCount, pictures);
      warm.single.close();
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test('ruby emphasis retains its explicit unsupported-format guard', () {
    for (final html in [
      '<p style="text-emphasis:\'X\'">A<ruby>B<rt>b</rt></ruby>C</p>',
    ]) {
      final fixture = _Fixture(html), session = fixture.open();
      expect(() => _finish(fixture, session), throwsA(anything));
      expect(session.state, ForumBodyTextPageSessionState.failed);
      expect(session.snapshot, isEmpty);
      expect(fixture.cache.activeLeases, 0);
    }
  });

  test('an indivisible Unicode group cannot be split to fit a small page', () {
    final fixture = _Fixture(
      '<p style="text-emphasis:\'X\';line-height:.4">👩‍👩‍👧‍👦</p>',
    );
    final session = fixture.open(width: 40, height: 40);
    expect(
      () => _finish(fixture, session),
      throwsA(
        isA<ForumBodyTextPageException>().having(
          (e) => e.failure,
          'failure',
          ForumBodyTextPageFailure.oversizedGroup,
        ),
      ),
    );
    expect(session.snapshot, isEmpty);
    expect(fixture.cache.activeLeases, 0);
  });

  test(
    'the page quota includes the final scene independently of measurement',
    () {
      final fixture = _Fixture('<p style="text-emphasis:\'X\'">A</p>');
      final session = fixture.open(pageEntries: 5);
      expect(
        () => _finish(fixture, session),
        throwsA(
          isA<ForumBodyTextPageException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyTextPageFailure.nativeEntryLimit,
          ),
        ),
      );
      expect(session.state, ForumBodyTextPageSessionState.failed);
      expect(session.snapshot, isEmpty);
      expect(fixture.cache.pictureBuildCount, 0);
      expect(fixture.cache.activeLeases, 0);
    },
  );
}

final class _Scaler extends TextScaler {
  const _Scaler(this.callback);
  final double Function(double) callback;
  @override
  double scale(double fontSize) => callback(fontSize);
  @override
  double get textScaleFactor => throw StateError('Use actual font sizes');
}
