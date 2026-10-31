import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_pair_fixture.dart';

void _owner() {}

({ForumBodyTextRequest base, ForumBodyTextRequest annotation}) _requests({
  bool banded = true,
  bool emptyAnnotation = false,
}) {
  final input = rubyPairInput(annotation: emptyAnnotation ? '' : 'xy');
  if (!banded) {
    return (
      base: ForumBodyTextRequest.paragraph(input.base),
      annotation: ForumBodyTextRequest.paragraph(input.annotation),
    );
  }
  final band = ForumBodyTextBandContent(
    contexts: [input.base, if (!emptyAnnotation) input.annotation],
  );
  return (
    base: ForumBodyTextRequest.bandChild(band: band, childIndex: 0),
    annotation: emptyAnnotation
        ? ForumBodyTextRequest.paragraph(input.annotation)
        : ForumBodyTextRequest.bandChild(band: band, childIndex: 1),
  );
}

ForumBodyRubyGroupPreparation _prepare(
  ForumBodyParagraphCache cache, {
  bool banded = true,
  bool emptyAnnotation = false,
  void Function() ensureOwner = _owner,
  TextScaler textScaler = TextScaler.noScaling,
  Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
}) {
  final input = _requests(banded: banded, emptyAnnotation: emptyAnnotation);
  final preparation = ForumBodyRubyGroupPreparation.forMetrics(
    cache: cache,
    base: input.base,
    annotation: input.annotation,
    ensureOwner: ensureOwner,
    additionalOwnedLeases: additionalOwnedLeases,
    textScaler: textScaler,
  );
  addTearDown(preparation.close);
  return preparation;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ForumBodyParagraphCache cache;
  setUp(() {
    cache = ForumBodyParagraphCache(maxEntries: 2, maxEstimatedBytes: 1 << 22);
  });
  tearDown(() => cache.close());

  test(
    'cold metrics yield after one shape, never paint, and release ready pins',
    () {
      final prepare = _prepare(cache);
      expect(prepare.tryPrepareCached(), isFalse);
      expect(cache.layoutBuildCount, 0);
      final first = prepare.advance();
      expect(first.layoutsBuilt, 1);
      expect(first.partsPrepared, 1);
      expect(first.picturesBuilt, 0);
      expect(first.isReady, isFalse);
      expect(cache.activeLeases, 1);
      expect(() => prepare.takeMetrics(), throwsStateError);
      expect(prepare.state, ForumBodyRubyGroupPreparationState.active);
      final ready = prepare.advance();
      expect(ready.layoutsBuilt, 0);
      expect(ready.partsPrepared, 1);
      expect(ready.isReady, isTrue);
      expect(cache.pictureBuildCount, 0);
      expect(cache.activeLeases, 0);
      expect(prepare.nativeLeases, isEmpty);
      expect(() => prepare.takeLayout(), throwsStateError);
      expect(prepare.isReady, isTrue);
      final metrics = prepare.takeMetrics();
      expect(metrics.size, const Size(40, 30));
      expect(prepare.state, ForumBodyRubyGroupPreparationState.transferred);
      expect(() => prepare.takeMetrics(), throwsStateError);
      prepare.close();
      cache.close();
      expect(metrics.placeholderDimensions.size, const Size(40, 30));
      expect(cache.estimatedRetainedBytes, 0);
    },
  );

  test('warm unpainted band is enough for cached-only metrics', () {
    final input = _requests();
    input.base
        .acquire(
          cache,
          width: 100,
          textScaler: TextScaler.noScaling,
          cachedOnly: false,
        )!
        .release();
    final prepare = ForumBodyRubyGroupPreparation.forMetrics(
      cache: cache,
      base: input.base,
      annotation: input.annotation,
      ensureOwner: _owner,
    );
    addTearDown(prepare.close);
    expect(prepare.tryPrepareCached(), isTrue);
    expect(prepare.tryPrepareCached(), isTrue);
    expect(cache.layoutBuildCount, 1);
    expect(cache.pictureBuildCount, 0);
    expect(cache.activeLeases, 0);
    expect(prepare.takeMetrics().size, const Size(40, 30));
  });

  test(
    'cached partial metrics retain only this request and resume cold work',
    () {
      final input = _requests(banded: false);
      final external = input.base.acquire(
        cache,
        width: 100,
        textScaler: TextScaler.noScaling,
        cachedOnly: false,
      )!;
      addTearDown(external.release);
      final prepare = ForumBodyRubyGroupPreparation.forMetrics(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
        ensureOwner: _owner,
      );
      addTearDown(prepare.close);
      expect(prepare.tryPrepareCached(), isFalse);
      expect(cache.activeLeases, 2);
      expect(prepare.preparedPartCount, 1);
      final ready = prepare.advance();
      expect(ready.layoutsBuilt, 1);
      expect(ready.isReady, isTrue);
      expect(cache.activeLeases, 1);
      expect(external.isActive, isTrue);
      prepare.takeMetrics();
      expect(external.isActive, isTrue);
    },
  );

  test('readable preparations cannot transfer an unpainted numeric result', () {
    final input = rubyPairInput();
    final readable = ForumBodyRubyGroupPreparation(
      cache: cache,
      base: input.base,
      annotation: input.annotation,
      ensureOwner: _owner,
    );
    addTearDown(readable.close);
    readable.advance();
    readable.advance();
    expect(readable.isReady, isTrue);
    expect(() => readable.takeMetrics(), throwsStateError);
    expect(readable.isReady, isTrue);
    expect(cache.activeLeases, 2);
    readable.takeLayout().close();
    expect(cache.activeLeases, 0);
  });

  test('empty annotation completes in one glyph unit without an upper row', () {
    final prepare = _prepare(cache, emptyAnnotation: true);
    final step = prepare.advance();
    expect(step.layoutsBuilt, 1);
    expect(step.isReady, isTrue);
    expect(prepare.expectedPartCount, 1);
    expect(cache.activeLeases, 0);
    expect(cache.pictureBuildCount, 0);
    final metrics = prepare.takeMetrics();
    expect(metrics.size, const Size(40, 20));
    expect(metrics.hasAnnotation, isFalse);
  });

  test('foreign pressure waits and releases all metric pins after resume', () {
    final foreign = rubyPairInput(base: 'ZZ');
    final external = cache.acquire(content: foreign.base, width: 100);
    addTearDown(external.release);
    final prepare = _prepare(cache, banded: false);
    expect(prepare.advance().layoutsBuilt, 1);
    final blocked = prepare.advance();
    expect(blocked.waitingForLayoutBudget, isTrue);
    expect(blocked.partsInspected, 2);
    expect(blocked.layoutsBuilt, 0);
    final waiting = prepare.advance();
    expect(waiting.waitingForLayoutBudget, isTrue);
    expect(waiting.madeProgress, isFalse);
    external.release();
    final resumed = prepare.advance();
    expect(resumed.layoutsBuilt, 1);
    expect(resumed.isReady, isTrue);
    expect(cache.activeLeases, 0);
    expect(cache.pictureBuildCount, 0);
    expect(prepare.takeMetrics().size, const Size(40, 30));
  });

  test('all-own pressure fails without waiting on the outer planner pins', () {
    final foreign = rubyPairInput(base: 'ZZ');
    final outer = cache.acquire(content: foreign.base, width: 100);
    addTearDown(outer.release);
    final prepare = _prepare(
      cache,
      banded: false,
      additionalOwnedLeases: () => [outer],
    );
    prepare.advance();
    expect(
      () => prepare.advance(),
      throwsA(
        isA<ForumBodyRubyGroupPreparationException>().having(
          (e) => e.failure,
          'failure',
          ForumBodyRubyGroupPreparationFailure.intrinsicBudget,
        ),
      ),
    );
    expect(prepare.state, ForumBodyRubyGroupPreparationState.failed);
    expect(prepare.waitingForLayoutBudget, isFalse);
    expect(prepare.nativeLeases, isEmpty);
    expect(outer.isActive, isTrue);
    expect(cache.activeLeases, 1);
  });

  test(
    'generation cancellation between glyph units drops only partial pins',
    () {
      var current = true;
      final prepare = _prepare(
        cache,
        ensureOwner: () {
          if (!current) throw StateError('Retired generation');
        },
      );
      prepare.advance();
      expect(cache.activeLeases, 1);
      current = false;
      expect(() => prepare.advance(), throwsStateError);
      expect(prepare.state, ForumBodyRubyGroupPreparationState.failed);
      expect(cache.activeLeases, 0);
      expect(cache.pictureBuildCount, 0);
      expect(cache.isClosed, isFalse);
      cache.clearUnpinned();
      expect(cache.estimatedRetainedBytes, 0);
    },
  );

  test(
    'cancellation after metric pin release cannot publish a numeric result',
    () {
      late ForumBodyRubyGroupPreparation prepare;
      prepare = _prepare(
        cache,
        ensureOwner: () {
          if (prepare.preparedPartCount == 2 && cache.activeLeases == 0) {
            prepare.close();
          }
        },
      );
      prepare.advance();
      expect(() => prepare.advance(), throwsStateError);
      expect(prepare.state, ForumBodyRubyGroupPreparationState.closed);
      expect(cache.activeLeases, 0);
      expect(prepare.isReady, isFalse);
      expect(() => prepare.takeMetrics(), throwsStateError);
    },
  );

  test('owner retirement before transfer rejects already measured metrics', () {
    final prepare = _prepare(cache);
    prepare.advance();
    prepare.advance();
    expect(prepare.isReady, isTrue);
    cache.close();
    expect(() => prepare.takeMetrics(), throwsStateError);
    expect(prepare.state, ForumBodyRubyGroupPreparationState.failed);
    expect(cache.activeLeases, 0);
    expect(cache.estimatedRetainedBytes, 0);
  });

  test('reentrant metric preparation is retired before any native work', () {
    late ForumBodyRubyGroupPreparation prepare;
    prepare = _prepare(cache, ensureOwner: () => prepare.tryPrepareCached());
    expect(() => prepare.advance(), throwsStateError);
    expect(prepare.state, ForumBodyRubyGroupPreparationState.failed);
    expect(cache.layoutBuildCount, 0);
    expect(cache.activeLeases, 0);
  });

  test(
    '120 actual flow groups plan with four shapes and only two pins at once',
    () {
      final document = const ForumBodyParser().parse(
        html:
            '<ruby>${List.generate(120, (i) => 'b$i<rt>r$i</rt>').join()}</ruby>',
        sourceId: 'dense-glyph-planning',
        conversionIdentity: 'none',
      );
      final flow = ForumBodyTextFlowCursor(
        document: document,
        reader: ForumBodyReaderStyle(
          textStyle: const TextStyle(
            fontFamily: 'Ahem',
            fontSize: 20,
            height: 1,
          ),
          fontRevision: 'ahem',
          linkColor: const Color(0xff0000ff),
        ),
      );
      addTearDown(flow.close);
      ForumBodyInlineFlowContent? content;
      while (!flow.isComplete) {
        flow.advance(maxEvents: 8);
        if (flow.current case ForumBodyTextFlowInline(content: final input)) {
          content = input;
        }
      }
      final groups = content!.parts
          .whereType<ForumBodyInlineFlowRuby>()
          .map((p) => p.group)
          .toList();
      final contexts = [
        for (final group in groups) ...[
          (group.base.single as ForumBodyRubyTextContent).content,
          (group.annotations.single.parts.single as ForumBodyRubyTextContent)
              .content,
        ],
      ];
      final bands = [
        for (var start = 0; start < contexts.length; start += 64)
          ForumBodyTextBandContent(
            contexts: contexts.sublist(
              start,
              start + 64 < contexts.length ? start + 64 : contexts.length,
            ),
          ),
      ];
      final dimensions = <PlaceholderDimensions>[];
      var units = 0;
      for (var i = 0; i < groups.length; i++) {
        final baseIndex = i * 2;
        final rtIndex = baseIndex + 1;
        final prepare = ForumBodyRubyGroupPreparation.forMetrics(
          cache: cache,
          base: ForumBodyTextRequest.bandChild(
            band: bands[baseIndex ~/ 64],
            childIndex: baseIndex % 64,
          ),
          annotation: ForumBodyTextRequest.bandChild(
            band: bands[rtIndex ~/ 64],
            childIndex: rtIndex % 64,
          ),
          ensureOwner: _owner,
        );
        try {
          while (!prepare.isReady) {
            final step = prepare.advance();
            units++;
            expect(step.layoutsBuilt, lessThanOrEqualTo(1));
            expect(step.picturesBuilt, 0);
            expect(step.madeProgress, isTrue);
            expect(cache.activeLeases, lessThanOrEqualTo(2));
            expect(units, lessThanOrEqualTo(124));
          }
          dimensions.add(prepare.takeMetrics().placeholderDimensions);
          expect(cache.activeLeases, 0);
        } finally {
          prepare.close();
        }
      }
      expect(dimensions, hasLength(120));
      expect(
        dimensions.every((dimension) => dimension.size.height == 30),
        isTrue,
      );
      expect(units, 124);
      expect(cache.layoutBuildCount, 4);
      expect(cache.pictureBuildCount, 0);
      expect(cache.entryCount, 2);
      cache.clearUnpinned();
      expect(cache.estimatedRetainedBytes, 0);
    },
  );
}
