import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final class _Input {
  _Input(
    String html, {
    double fontSize = 10,
    double lineHeight = 1,
    String sourceId = 'pages',
  }) {
    document = const ForumBodyParser().parse(
      html: html,
      sourceId: sourceId,
      conversionIdentity: 'none',
    );
    styles = const ForumBodyStyleResolver().resolve(
      document,
      ForumBodyReaderStyle(
        textStyle: TextStyle(
          fontSize: fontSize,
          height: lineHeight,
          fontFamily: 'Ahem',
        ),
        fontRevision: 'synthetic-ahem',
        linkColor: const Color(0xff0000ff),
      ),
    );
    cache = ForumBodyParagraphCache(maxEntries: 4, maxEstimatedBytes: 1 << 20);
    addTearDown(cache.close);
  }
  late final ForumBodyDocument document;
  late final ForumBodyStyleResult styles;
  late final ForumBodyParagraphCache cache;
  ForumBodyParagraphContent content(int index) =>
      const ForumBodyParagraphContentBuilder().build(
        document: document,
        styles: styles,
        path: '$index',
      );
  ForumBodyParagraphLease lease(int index, {double width = 100}) =>
      cache.acquire(content: content(index), width: width);
  ForumBodyTextPageComposer composer({
    double width = 100,
    double height = 20,
    int maxPages = 20,
    int maxFragments = 40,
  }) {
    final composer = ForumBodyTextPageComposer(
      identity: document.identity,
      layoutId: 'layout-generation-1',
      width: width,
      height: height,
      maxPages: maxPages,
      maxFragments: maxFragments,
    );
    addTearDown(composer.close);
    return composer;
  }
}

void _append(
  ForumBodyTextPageComposer composer,
  ForumBodyParagraphLease lease,
  int index,
) => composer.append(
  lease: lease,
  paragraphIndex: index,
  left: 0,
  spaceBefore: 0,
  spaceAtPageStart: 0,
);

void _consume(ForumBodyTextPageComposer composer, {int maxLines = 2}) {
  var calls = 0;
  while (!composer.needsInput) {
    if (++calls > 100) fail('Composition did not make bounded progress');
    final step = composer.advance(maxLines: maxLines);
    expect(step.linesInspected, lessThanOrEqualTo(maxLines));
    expect(step.pagesPublished, lessThanOrEqualTo(1));
    expect(
      step.linesInspected > 0 ||
          step.pagesPublished > 0 ||
          step.paragraphCompleted,
      isTrue,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'published source hints retain hidden gaps without claiming their visibility',
    () {
      final input = _Input('<p>a<span style="display:none">hidden</span>b</p>');
      final composer = input.composer(height: 10);
      final lease = input.lease(0);
      expect(lease.content.projection.text, 'ab');
      _append(composer, lease, 0);
      _consume(composer);
      composer.finish();
      expect(composer.snapshot.single.fragments.single.sourceHint, (
        runeStart: 0,
        runeEnd: 8,
      ));
      expect(composer.snapshot.composerRevision, 12);
    },
  );

  test(
    'source hints count raw codepoints instead of display UTF16 or clipped ink',
    () {
      final unicode = _Input('<p>A🙂</p>');
      final full = unicode.composer(height: 100);
      _append(full, unicode.lease(0), 0);
      _consume(full);
      full.finish();
      final fragment = full.snapshot.single.fragments.single;
      expect(fragment.coverageEndUtf16, 3);
      expect(fragment.sourceHint, (runeStart: 0, runeEnd: 2));
      final narrow = _Input('<p>a</p>');
      final clipped = narrow.composer(width: 3, height: 10);
      _append(clipped, narrow.lease(0, width: 3), 0);
      _consume(clipped);
      clipped.finish();
      expect(clipped.snapshot.single.fragments.single.sourceHint, (
        runeStart: 0,
        runeEnd: 1,
      ));
    },
  );

  test('a terminal empty native window has no source hint of its own', () {
    final input = _Input('<p>a<br></p>');
    final composer = input.composer(height: 10);
    for (final (index, window) in [
      ForumBodyParagraphWindow.beforeTerminalEmptyLine,
      ForumBodyParagraphWindow.terminalEmptyLine,
    ].indexed) {
      composer.append(
        lease: input.lease(0),
        paragraphIndex: index,
        left: 0,
        spaceBefore: 0,
        spaceAtPageStart: 0,
        window: window,
      );
      _consume(composer);
    }
    composer.finish();
    expect(composer.snapshot[0].fragments.single.sourceHint, (
      runeStart: 0,
      runeEnd: 2,
    ));
    expect(composer.snapshot[1].fragments.single.sourceHint, isNull);
  });

  test(
    'margin before padding is trimmed on a break instead of becoming physical blank pages',
    () {
      final input = _Input('<p>a</p>');
      final composer = input.composer(height: 20);
      _append(composer, input.lease(0), 0);
      _consume(composer);
      composer.appendPadding(25, spaceBefore: 100, spaceAtPageStart: 3);
      expect(composer.advancePadding(), (
        extentConsumed: 0.0,
        pagesPublished: 1,
        isComplete: false,
      ));
      final prefix = composer.snapshot;
      expect(prefix.single.usedHeight, 10);
      expect(composer.advancePadding(), (
        extentConsumed: 17.0,
        pagesPublished: 1,
        isComplete: false,
      ));
      expect(prefix, hasLength(1));
      expect(composer.advancePadding(), (
        extentConsumed: 8.0,
        pagesPublished: 0,
        isComplete: true,
      ));
      composer.finish();
      expect(composer.snapshot.map((page) => page.usedHeight), [10, 20, 8]);
      expect(input.cache.layoutBuildCount, 1);
    },
  );

  test(
    'signed margin before padding applies once and preserves earlier fragment height',
    () {
      final input = _Input('<p style="font-size:30px">a</p><p>b</p>');
      final composer = input.composer(height: 100);
      _append(composer, input.lease(0), 0);
      _consume(composer);
      composer.appendPadding(5, spaceBefore: -25);
      expect(composer.advancePadding().isComplete, isTrue);
      _append(composer, input.lease(1), 1);
      _consume(composer);
      composer.finish();
      expect(
        composer.snapshot.single.fragments.map((fragment) => fragment.top),
        [0, 10],
      );
      expect(composer.snapshot.single.usedHeight, 30);
    },
  );

  test(
    'padding margin input is checked before admission and a huge page-start gap fails safely',
    () {
      final composer = _Input('').composer(height: 20);
      for (final (before, atStart) in [
        (double.nan, 0.0),
        (0.0, -1.0),
        (0.0, double.infinity),
      ]) {
        expect(
          () => composer.appendPadding(
            1,
            spaceBefore: before,
            spaceAtPageStart: atStart,
          ),
          throwsArgumentError,
        );
        expect(composer.needsInput, isTrue);
      }
      composer.appendPadding(1, spaceAtPageStart: 20);
      expect(
        composer.advancePadding,
        throwsA(
          isA<ForumBodyTextPageException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyTextPageFailure.oversizedGroup,
          ),
        ),
      );
      expect(composer.isClosed, isTrue);
      expect(composer.snapshot, isEmpty);
    },
  );

  test('zero padding does not apply a margin or create a collapse barrier', () {
    final composer = _Input('').composer();
    composer.appendPadding(0, spaceBefore: 1000, spaceAtPageStart: 1000);
    expect(composer.advancePadding().isComplete, isTrue);
    composer.finish();
    expect(composer.snapshot, isEmpty);
  });

  test(
    'padding alone publishes bounded fixed page prefixes with no native resources',
    () {
      final input = _Input('');
      final composer = input.composer(height: 20, maxFragments: 1);
      composer.appendPadding(45);
      expect(composer.hasPendingPadding, isTrue);
      expect(composer.needsInput, isFalse);
      expect(composer.advancePadding(), (
        extentConsumed: 20.0,
        pagesPublished: 1,
        isComplete: false,
      ));
      final prefix = composer.snapshot;
      expect(prefix, hasLength(1));
      expect(composer.advancePadding(), (
        extentConsumed: 20.0,
        pagesPublished: 1,
        isComplete: false,
      ));
      expect(prefix, hasLength(1));
      expect(composer.advancePadding(), (
        extentConsumed: 5.0,
        pagesPublished: 0,
        isComplete: true,
      ));
      expect(composer.needsInput, isTrue);
      expect(composer.snapshot, hasLength(2));
      composer.finish();
      expect(composer.snapshot.map((page) => page.usedHeight), [20, 20, 5]);
      expect(composer.snapshot.every((page) => page.fragments.isEmpty), isTrue);
      expect(composer.nextParagraphIndex, 0);
      expect(composer.retainedFragmentCount, 0);
      expect(input.cache.layoutBuildCount, 0);
      expect(input.cache.activeLeases, 0);
    },
  );

  test(
    'padding separates a physical page start from the first text fragment',
    () {
      final input = _Input('<p>a</p>');
      final composer = input.composer(height: 30);
      composer.appendPadding(5);
      composer.advancePadding();
      composer.append(
        lease: input.lease(0),
        paragraphIndex: 0,
        left: 0,
        spaceBefore: 3,
        spaceAtPageStart: 99,
      );
      _consume(composer);
      composer.appendPadding(7);
      composer.advancePadding();
      composer.finish();
      expect(composer.snapshot.single.fragments.single.top, 8);
      expect(composer.snapshot.single.usedHeight, 25);
      expect(input.cache.activeLeases, 0);
    },
  );

  test(
    'a text group following partial padding resumes on a new page with its real start policy',
    () {
      final input = _Input('<p>a</p>');
      final composer = input.composer(height: 20);
      composer.appendPadding(15);
      composer.advancePadding();
      final lease = input.lease(0);
      composer.append(
        lease: lease,
        paragraphIndex: 0,
        left: 0,
        spaceBefore: 0,
        spaceAtPageStart: 2,
      );
      expect(composer.advance(maxLines: 1), (
        linesInspected: 1,
        pagesPublished: 1,
        paragraphCompleted: false,
      ));
      expect(composer.snapshot.single.fragments, isEmpty);
      expect(composer.snapshot.single.usedHeight, 15);
      expect(lease.isActive, isTrue);
      expect(composer.advance(maxLines: 1), (
        linesInspected: 0,
        pagesPublished: 0,
        paragraphCompleted: true,
      ));
      composer.finish();
      expect(composer.snapshot.last.fragments.single.top, 2);
      expect(composer.snapshot.last.usedHeight, 12);
      expect(input.cache.activeLeases, 0);
    },
  );

  test('trailing padding can span pages after text and survives finish', () {
    final input = _Input('<p>a</p>');
    final composer = input.composer(height: 20);
    _append(composer, input.lease(0), 0);
    _consume(composer);
    composer.appendPadding(25);
    expect(composer.advancePadding(), (
      extentConsumed: 10.0,
      pagesPublished: 1,
      isComplete: false,
    ));
    expect(composer.advancePadding(), (
      extentConsumed: 15.0,
      pagesPublished: 0,
      isComplete: true,
    ));
    composer.finish();
    expect(composer.snapshot.map((page) => page.usedHeight), [20, 15]);
    expect(composer.snapshot.first.fragments, hasLength(1));
    expect(composer.snapshot.last.fragments, isEmpty);
    expect(input.cache.layoutBuildCount, 1);
  });

  test(
    'padding continues from signed flow position without erasing occupied extent',
    () {
      final input = _Input('<p style="font-size:30px">a</p><p>b</p><p>c</p>');
      final composer = input.composer(height: 100);
      _append(composer, input.lease(0), 0);
      _consume(composer);
      composer.append(
        lease: input.lease(1),
        paragraphIndex: 1,
        left: 0,
        spaceBefore: -30,
        spaceAtPageStart: 0,
      );
      _consume(composer);
      composer.appendPadding(5);
      composer.advancePadding();
      _append(composer, input.lease(2), 2);
      _consume(composer);
      composer.finish();
      expect(
        composer.snapshot.single.fragments.map((fragment) => fragment.top),
        [0, 0, 15],
      );
      expect(composer.snapshot.single.usedHeight, 30);
    },
  );

  test(
    'zero padding completes without a phantom page and invalid padding keeps admission open',
    () {
      final composer = _Input('').composer();
      for (final extent in [-1.0, double.nan, double.infinity]) {
        expect(() => composer.appendPadding(extent), throwsArgumentError);
        expect(composer.needsInput, isTrue);
      }
      composer.appendPadding(0);
      expect(composer.advancePadding(), (
        extentConsumed: 0.0,
        pagesPublished: 0,
        isComplete: true,
      ));
      composer.finish();
      expect(composer.snapshot, isEmpty);
    },
  );

  test(
    'fractional page remainders do not create an extra padding-only page',
    () {
      final composer = _Input('').composer(height: .3);
      composer.appendPadding(.1);
      composer.advancePadding();
      composer.appendPadding(.2);
      expect(composer.advancePadding().isComplete, isTrue);
      composer.finish();
      expect(composer.snapshot, hasLength(1));
      expect(composer.snapshot.single.usedHeight, .3);
    },
  );

  test(
    'padding obeys page metadata limits and preserves the published prefix on failure',
    () {
      final composer = _Input('').composer(height: 20, maxPages: 1);
      composer.appendPadding(50);
      composer.advancePadding();
      final prefix = composer.snapshot;
      expect(
        () => composer.advancePadding(),
        throwsA(
          isA<ForumBodyTextPageException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyTextPageFailure.pageLimit,
          ),
        ),
      );
      expect(composer.snapshot, same(prefix));
      expect(prefix.single.usedHeight, 20);
      expect(composer.isClosed, isTrue);
      expect(composer.hasPendingPadding, isFalse);
    },
  );

  test(
    'pending padding rejects conflicting work without taking a paragraph lease',
    () {
      final input = _Input('<p>a</p>');
      final composer = input.composer();
      final lease = input.lease(0);
      composer.appendPadding(5);
      expect(() => _append(composer, lease, 0), throwsStateError);
      expect(() => composer.appendPadding(1), throwsStateError);
      expect(() => composer.advance(maxLines: 1), throwsStateError);
      expect(composer.finish, throwsStateError);
      expect(lease.isActive, isTrue);
      composer.advancePadding();
      _append(composer, lease, 0);
      expect(composer.advancePadding, throwsStateError);
      _consume(composer);
      composer.finish();
      expect(input.cache.activeLeases, 0);
    },
  );

  test('close retires only unpublished padding and pending metadata', () {
    final composer = _Input('').composer();
    composer.appendPadding(25);
    composer.advancePadding();
    final prefix = composer.snapshot;
    composer.close();
    expect(composer.hasPendingPadding, isFalse);
    expect(composer.snapshot, same(prefix));
    expect(composer.advancePadding, throwsStateError);
    expect(composer.finish, throwsStateError);
  });

  test(
    'signed gaps move the flow cursor without erasing earlier occupied ink',
    () {
      final input = _Input('<p style="font-size:30px">a</p><p>b</p><p>c</p>');
      final composer = input.composer(height: 100);
      for (var index = 0; index < 3; index++) {
        composer.append(
          lease: input.lease(index),
          paragraphIndex: index,
          left: 0,
          spaceBefore: index == 1 ? -25 : 0,
          spaceAtPageStart: 0,
        );
        _consume(composer, maxLines: 1);
      }
      composer.finish();
      expect(
        composer.snapshot.single.fragments.map((fragment) => fragment.top),
        [0, 5, 15],
      );
      expect(composer.snapshot.single.usedHeight, 30);
      expect(
        composer.snapshot.composerRevision,
        ForumBodyTextPageComposer.revision,
      );
      expect(input.cache.layoutBuildCount, 3);
      expect(input.cache.activeLeases, 0);
    },
  );

  test('negative gap is bounded by the current page top', () {
    final input = _Input('<p>a</p><p>b</p><p>c</p>');
    final composer = input.composer(height: 100);
    for (var index = 0; index < 3; index++) {
      composer.append(
        lease: input.lease(index),
        paragraphIndex: index,
        left: 0,
        spaceBefore: index == 1 ? -1000 : 0,
        spaceAtPageStart: 0,
      );
      _consume(composer);
    }
    composer.finish();
    expect(composer.snapshot.single.fragments.map((fragment) => fragment.top), [
      0,
      0,
      10,
    ]);
    expect(composer.snapshot.single.usedHeight, 20);
  });

  test(
    'a later negative gap cannot change a sealed page or bypass page-start policy',
    () {
      final input = _Input('<p>a<br>b</p><p>c</p>');
      final composer = input.composer(height: 20);
      _append(composer, input.lease(0), 0);
      _consume(composer);
      final prefix = composer.snapshot;
      expect(prefix.single.usedHeight, 20);
      composer.append(
        lease: input.lease(1),
        paragraphIndex: 1,
        left: 0,
        spaceBefore: -1000,
        spaceAtPageStart: 3,
      );
      _consume(composer);
      expect(composer.snapshot, same(prefix));
      composer.finish();
      expect(composer.snapshot, hasLength(2));
      expect(composer.snapshot.first, same(prefix.single));
      expect(prefix, hasLength(1));
      expect(composer.snapshot.last.fragments.single.top, 3);
      expect(composer.snapshot.last.usedHeight, 13);
      expect(input.cache.activeLeases, 0);
    },
  );

  test(
    'overlapping multi-line fragments still fit using actual growing line geometry',
    () {
      final input = _Input('<p>a</p><p>b<br>c</p>');
      final composer = input.composer(height: 25);
      _append(composer, input.lease(0), 0);
      _consume(composer);
      composer.append(
        lease: input.lease(1),
        paragraphIndex: 1,
        left: 0,
        spaceBefore: -5,
        spaceAtPageStart: 0,
      );
      _consume(composer, maxLines: 1);
      composer.finish();
      final page = composer.snapshot.single;
      expect(
        page.fragments.map((fragment) => (fragment.top, fragment.height)),
        [(0, 10), (5, 20)],
      );
      expect(page.usedHeight, 25);
      expect(page.fragments.last.coverageEndUtf16, 3);
      expect(input.cache.layoutBuildCount, 2);
      expect(input.cache.activeLeases, 0);
    },
  );

  test(
    'negative page-start placement is rejected while the lease remains caller-owned',
    () {
      final input = _Input('<p>a</p>');
      final composer = input.composer();
      final lease = input.lease(0);
      addTearDown(lease.release);
      expect(
        () => composer.append(
          lease: lease,
          paragraphIndex: 0,
          left: 0,
          spaceBefore: -5,
          spaceAtPageStart: -5,
        ),
        throwsArgumentError,
      );
      expect(lease.isActive, isTrue);
      expect(composer.needsInput, isTrue);
    },
  );

  test(
    'hard-break windows share real layout and preserve one final empty row',
    () {
      final input = _Input('<p>a<br></p>');
      final first = input.lease(0);
      final tail = input.lease(0);
      final layout = first.layout;
      expect(layout.height, 20);
      final composer = input.composer(height: 40);
      composer.append(
        lease: first,
        paragraphIndex: 0,
        left: 0,
        spaceBefore: 0,
        spaceAtPageStart: 0,
        window: ForumBodyParagraphWindow.beforeTerminalEmptyLine,
      );
      _consume(composer);
      composer.append(
        lease: tail,
        paragraphIndex: 1,
        left: 0,
        spaceBefore: 0,
        spaceAtPageStart: 0,
        window: ForumBodyParagraphWindow.terminalEmptyLine,
      );
      _consume(composer);
      composer.finish();
      final fragments = composer.snapshot.single.fragments;
      expect(
        fragments.map((fragment) => (fragment.startLine, fragment.endLine)),
        [(0, 1), (1, 2)],
      );
      expect(
        fragments.map(
          (fragment) =>
              (fragment.coverageStartUtf16, fragment.coverageEndUtf16),
        ),
        [(0, 2), (2, 2)],
      );
      expect(fragments.map((fragment) => fragment.top), [0, 10]);
      expect(composer.snapshot.single.usedHeight, layout.height);
      expect(input.cache.layoutBuildCount, 1);
      expect(input.cache.activeLeases, 0);
    },
  );

  test(
    'nonexistent terminal windows are rejected without consuming the lease',
    () {
      final input = _Input('<p>x</p>');
      final lease = input.lease(0);
      addTearDown(lease.release);
      final composer = input.composer();
      for (final window in [
        ForumBodyParagraphWindow.beforeTerminalEmptyLine,
        ForumBodyParagraphWindow.terminalEmptyLine,
      ]) {
        expect(
          () => composer.append(
            lease: lease,
            paragraphIndex: 0,
            left: 0,
            spaceBefore: 0,
            spaceAtPageStart: 0,
            window: window,
          ),
          throwsA(isA<ForumBodyParagraphLayoutException>()),
        );
        expect(lease.isActive, isTrue);
        expect(composer.needsInput, isTrue);
      }
    },
  );

  test(
    'bounded composition reuses one layout and publishes fixed native-free prefixes',
    () {
      final input = _Input('<p>a<br>b<br>c<br>d<br>e<br>f</p>');
      final lease = input.lease(0);
      final layout = lease.layout;
      expect(layout.height, 60);
      final composer = input.composer();
      final empty = composer.snapshot;
      _append(composer, lease, 0);
      expect(composer.advance(maxLines: 1), (
        linesInspected: 1,
        pagesPublished: 0,
        paragraphCompleted: false,
      ));
      expect(composer.snapshot, isEmpty);
      expect(composer.advance(maxLines: 1), (
        linesInspected: 1,
        pagesPublished: 1,
        paragraphCompleted: false,
      ));
      final first = composer.snapshot;
      expect(first, hasLength(1));
      expect(first.isComplete, isFalse);
      expect(first.single.fragments.single.endLine, 2);
      expect(first.single.fragments.single.coverageEndUtf16, 4);
      expect(first.single.usedHeight, 20);
      expect(composer.snapshot, same(first));
      expect(() => first.clear(), throwsUnsupportedError);
      expect(() => first.single.fragments.clear(), throwsUnsupportedError);
      expect(composer.advance(maxLines: 100).pagesPublished, 1);
      expect(first, hasLength(1));
      expect(() => first[1], throwsRangeError);
      expect(composer.advance(maxLines: 100).paragraphCompleted, isTrue);
      expect(input.cache.activeLeases, 0);
      expect(input.cache.layoutBuildCount, 1);
      final beforeFinish = composer.snapshot;
      composer.finish();
      final complete = composer.snapshot;
      expect(complete, hasLength(3));
      expect(complete.isComplete, isTrue);
      expect(beforeFinish.isComplete, isFalse);
      expect(complete.first, same(first.single));
      expect(empty, isEmpty);
      expect(complete.identity, input.document.identity);
      expect(complete.layoutId, 'layout-generation-1');
      expect(
        complete.backendRevision,
        ForumBodyParagraphLayout.backendRevision,
      );
      final text = layout.projection.text;
      expect(
        complete
            .expand((page) => page.fragments)
            .map(
              (fragment) => text.substring(
                fragment.coverageStartUtf16,
                fragment.coverageEndUtf16,
              ),
            )
            .join(),
        text,
      );
      input.cache.clearUnpinned();
      expect(layout.isDisposed, isTrue);
      expect(complete.last.fragments.single.endLine, 6);
      composer.close();
      expect(composer.snapshot, same(complete));
    },
  );

  test(
    'resolved spacing is placed once and a known pending group needs no rescan',
    () {
      final input = _Input('<p>a</p><p>b<br>c</p><p>d</p>');
      final composer = input.composer(width: 120, height: 35);
      composer.append(
        lease: input.lease(0, width: 80),
        paragraphIndex: 0,
        left: 20,
        spaceBefore: 100,
        spaceAtPageStart: 5,
      );
      _consume(composer);
      composer.append(
        lease: input.lease(1, width: 120),
        paragraphIndex: 1,
        left: 0,
        spaceBefore: 3,
        spaceAtPageStart: 7,
      );
      final first = composer.advance(maxLines: 10);
      expect(first, (
        linesInspected: 2,
        pagesPublished: 1,
        paragraphCompleted: false,
      ));
      expect(composer.snapshot.single.usedHeight, 28);
      expect(
        composer.snapshot.single.fragments.map((fragment) => fragment.top),
        [5, 18],
      );
      expect(composer.snapshot.single.fragments.first.left, 20);
      final second = composer.advance(maxLines: 1);
      expect(second, (
        linesInspected: 0,
        pagesPublished: 0,
        paragraphCompleted: true,
      ));
      composer.append(
        lease: input.lease(2, width: 70),
        paragraphIndex: 2,
        left: 30,
        spaceBefore: 4,
        spaceAtPageStart: 8,
      );
      _consume(composer);
      composer.finish();
      expect(composer.snapshot, hasLength(2));
      expect(composer.snapshot.last.fragments.map((fragment) => fragment.top), [
        0,
        14,
      ]);
      expect(composer.snapshot.last.usedHeight, 24);
      expect(input.cache.activeLeases, 0);
    },
  );

  test(
    'a protected fallback cluster can be scanned across calls but never split across pages',
    () {
      final input = _Input(
        '<p>中文日文かな 👨‍👩‍👧‍👦 é abc def</p>',
        fontSize: 20,
        lineHeight: 1.5,
      );
      final lease = input.lease(0, width: 60);
      final layout = lease.layout;
      expect(layout.lines[2].canBreakAfter, isFalse);
      final composer = input.composer(width: 60, height: 60);
      _append(composer, lease, 0);
      expect(composer.advance(maxLines: 2).pagesPublished, 1);
      expect(composer.advance(maxLines: 1), (
        linesInspected: 1,
        pagesPublished: 0,
        paragraphCompleted: false,
      ));
      expect(input.cache.activeLeases, 1);
      expect(composer.advance(maxLines: 1).pagesPublished, 1);
      final cluster = composer.snapshot[1].fragments.single;
      expect((cluster.startLine, cluster.endLine), (2, 4));
      _consume(composer, maxLines: 1);
      composer.finish();
      var previous = 0;
      for (final fragment in composer.snapshot.expand(
        (page) => page.fragments,
      )) {
        expect(fragment.coverageStartUtf16, previous);
        final view = layout.fragment(fragment.startLine, fragment.endLine);
        expect(view.height, fragment.height);
        expect(view.coverageStartUtf16, fragment.coverageStartUtf16);
        expect(view.coverageEndUtf16, fragment.coverageEndUtf16);
        previous = fragment.coverageEndUtf16;
      }
      expect(previous, layout.projection.text.length);
      expect(input.cache.activeLeases, 0);
    },
  );

  test(
    'an oversized protected group fails without changing an already sealed prefix',
    () {
      final input = _Input(
        '<p>中文日文かな 👨‍👩‍👧‍👦 é abc def</p>',
        fontSize: 20,
        lineHeight: 1.5,
      );
      final composer = input.composer(width: 60, height: 30);
      _append(composer, input.lease(0, width: 60), 0);
      composer.advance(maxLines: 10);
      composer.advance(maxLines: 10);
      final prefix = composer.snapshot;
      expect(prefix, hasLength(2));
      expect(
        () => composer.advance(maxLines: 10),
        throwsA(
          isA<ForumBodyTextPageException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyTextPageFailure.oversizedGroup,
          ),
        ),
      );
      expect(composer.isClosed, isTrue);
      expect(composer.snapshot, same(prefix));
      expect(input.cache.activeLeases, 0);
      expect(composer.retainedFragmentCount, 2);
      expect(() => composer.advance(maxLines: 1), throwsStateError);
    },
  );

  test(
    'close discards only unpublished tail and releases the active paragraph',
    () {
      for (final rows in [1, 3]) {
        final input = _Input('<p>a<br>b<br>c<br>d<br>e<br>f</p>');
        final composer = input.composer();
        _append(composer, input.lease(0), 0);
        for (var index = 0; index < rows; index++) {
          composer.advance(maxLines: 1);
        }
        final prefix = composer.snapshot;
        composer.close();
        composer.close();
        expect(composer.snapshot, same(prefix));
        expect(prefix.length, rows ~/ 2);
        expect(composer.retainedFragmentCount, prefix.length);
        expect(input.cache.activeLeases, 0);
        expect(composer.needsInput, isFalse);
      }
    },
  );

  test(
    'explicit metadata budgets preserve the readable prefix on late failure',
    () {
      for (final failure in [
        ForumBodyTextPageFailure.pageLimit,
        ForumBodyTextPageFailure.fragmentLimit,
      ]) {
        final input = _Input('<p>a<br>b<br>c<br>d<br>e<br>f</p>');
        final composer = input.composer(
          maxPages: failure == ForumBodyTextPageFailure.pageLimit ? 1 : 20,
          maxFragments: failure == ForumBodyTextPageFailure.fragmentLimit
              ? 1
              : 20,
        );
        _append(composer, input.lease(0), 0);
        composer.advance(maxLines: 20);
        final prefix = composer.snapshot;
        expect(
          () => composer.advance(maxLines: 20),
          throwsA(
            isA<ForumBodyTextPageException>().having(
              (error) => error.failure,
              'failure',
              failure,
            ),
          ),
        );
        expect(composer.snapshot, same(prefix));
        expect(prefix, hasLength(1));
        expect(composer.retainedFragmentCount, 1);
        expect(input.cache.activeLeases, 0);
      }
      final input = _Input('<p>a<br>b<br>c</p>');
      final composer = input.composer(maxPages: 1);
      _append(composer, input.lease(0), 0);
      _consume(composer);
      expect(
        () => composer.finish(),
        throwsA(isA<ForumBodyTextPageException>()),
      );
      expect(composer.snapshot, hasLength(1));
      expect(composer.isComplete, isFalse);
    },
  );

  test(
    'rejected admission retains caller ownership and invalid advance leaves work resumable',
    () {
      final input = _Input('<p>one</p>');
      final composer = input.composer();
      final lease = input.lease(0);
      for (final (index, left, before) in [
        (1, 0.0, 0.0),
        (0, 1.0, 0.0),
        (0, 0.0, double.nan),
      ]) {
        expect(
          () => composer.append(
            lease: lease,
            paragraphIndex: index,
            left: left,
            spaceBefore: before,
            spaceAtPageStart: 0,
          ),
          throwsArgumentError,
        );
        expect(lease.isActive, isTrue);
      }
      final foreign = _Input('<p>one</p>', sourceId: 'foreign');
      final foreignLease = foreign.lease(0);
      expect(() => _append(composer, foreignLease, 0), throwsArgumentError);
      expect(foreignLease.isActive, isTrue);
      foreignLease.release();
      _append(composer, lease, 0);
      final second = input.lease(0);
      expect(() => _append(composer, second, 0), throwsStateError);
      expect(second.isActive, isTrue);
      second.release();
      expect(() => composer.finish(), throwsStateError);
      expect(() => composer.advance(maxLines: 0), throwsArgumentError);
      expect(lease.isActive, isTrue);
      _consume(composer);
      composer.finish();
      expect(input.cache.activeLeases, 0);
    },
  );

  test(
    'empty paragraphs consume bounded work without inventing an empty document page',
    () {
      final input = _Input('<p></p><p>x</p>');
      final composer = input.composer(height: 40);
      final empty = input.lease(0);
      expect(empty.layout.lines, isEmpty);
      expect(empty.layout.height, 10);
      composer.append(
        lease: empty,
        paragraphIndex: 0,
        left: 0,
        spaceBefore: 0,
        spaceAtPageStart: 4,
      );
      expect(composer.advance(maxLines: 1).paragraphCompleted, isTrue);
      composer.append(
        lease: input.lease(1),
        paragraphIndex: 1,
        left: 0,
        spaceBefore: 2,
        spaceAtPageStart: 0,
      );
      _consume(composer);
      composer.finish();
      expect(
        composer.snapshot.single.fragments.map((fragment) => fragment.top),
        [4, 16],
      );
      expect(composer.snapshot.single.usedHeight, 26);
      final noInput = _Input('').composer();
      noInput.finish();
      expect(noInput.snapshot, isEmpty);
      expect(noInput.snapshot.isComplete, isTrue);
    },
  );

  test(
    'retired native cache rejects late work while sealed numeric pages remain readable',
    () {
      final input = _Input('<p>a<br>b<br>c<br>d</p>');
      final composer = input.composer();
      _append(composer, input.lease(0), 0);
      composer.advance(maxLines: 10);
      final prefix = composer.snapshot;
      input.cache.close();
      expect(() => composer.advance(maxLines: 1), throwsStateError);
      expect(composer.snapshot, same(prefix));
      expect(prefix.single.fragments.single.coverageEndUtf16, 4);
      expect(input.cache.activeLeases, 0);
    },
  );
}
