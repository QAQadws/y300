import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_inline_fixture.dart';

const _dimensions = [
  PlaceholderDimensions(
    size: Size(40, 30),
    alignment: ui.PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    baselineOffset: 26,
  ),
];

ForumBodyReaderStyle _reader(Color link) => ForumBodyReaderStyle(
  textStyle: const TextStyle(
    fontFamily: 'Ahem',
    fontSize: 20,
    height: 1,
    color: Color(0xff000000),
  ),
  fontRevision: 'ahem',
  linkColor: link,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('last provisional alias retires only its own native entry', () {
    final cache = ForumBodyParagraphCache(
      maxEntries: 2,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(cache.close);
    final input = mixedInlineInput();
    final keep = cache.acquireInline(
      content: input.content,
      width: 200,
      dimensions: _dimensions,
    );
    final probe = cache.acquireInline(
      content: input.content,
      width: 100,
      dimensions: _dimensions,
    );
    final discarded = probe.layout;
    final bytes = cache.estimatedRetainedBytes;
    probe.releaseProvisional();
    probe.releaseProvisional();
    expect(discarded.isDisposed, isTrue);
    expect(keep.isActive, isTrue);
    expect(cache.entryCount, 1);
    expect(cache.activeLeases, 1);
    expect(cache.estimatedRetainedBytes, lessThan(bytes));
    expect(
      cache.tryAcquireInlineCached(
        content: input.content,
        width: 100,
        dimensions: _dimensions,
      ),
      isNull,
    );
    keep.release();
  });

  test('provisional release preserves a live alias and its warm cache', () {
    final cache = ForumBodyParagraphCache(
      maxEntries: 1,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(cache.close);
    final input = mixedInlineInput();
    final probe = cache.acquireInline(
      content: input.content,
      width: 100,
      dimensions: _dimensions,
    );
    final alias = cache.acquireInline(
      content: input.content,
      width: 100,
      dimensions: _dimensions,
    );
    final native = alias.layout;
    probe.releaseProvisional();
    expect(native.isDisposed, isFalse);
    expect(alias.isActive, isTrue);
    expect(cache.entryCount, 1);
    expect(cache.activeLeases, 1);
    alias.release();
    final warm = cache.tryAcquireInlineCached(
      content: input.content,
      width: 100,
      dimensions: _dimensions,
    );
    expect(warm, isNotNull);
    expect(identical(warm!.layout, native), isTrue);
    cache.close();
    warm.releaseProvisional();
    expect(cache.activeLeases, 0);
    expect(cache.estimatedRetainedBytes, 0);
  });

  test(
    'mixed aliases share one native entry but retain current child metadata',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      const annotation = '<a href="https://example.org/">xy</a>';
      final before = mixedInlineInput(
        annotation: annotation,
        reader: _reader(const Color(0xff0000ff)),
      );
      final after = mixedInlineInput(
        annotation: annotation,
        reader: _reader(const Color(0xffff0000)),
      );
      final first = cache.acquireInline(
        content: before.content,
        width: 100,
        dimensions: _dimensions,
      );
      final second = cache.acquireInline(
        content: after.content,
        width: 100,
        dimensions: _dimensions,
      );
      expect(identical(first.layout, second.layout), isTrue);
      expect(identical(first.content, before.content), isTrue);
      expect(identical(second.content, after.content), isTrue);
      expect(
        second.content.runs[2].style.textStyle.color,
        const Color(0xffff0000),
      );
      expect(
        first.content.runs[2].style.textStyle.color,
        const Color(0xff0000ff),
      );
      expect(cache.entryCount, 1);
      expect(cache.activeLeases, 2);
      expect(cache.layoutBuildCount, 1);
      expect(cache.hitCount, 1);
      final native = first.layout;
      final fragment = native.fragment(0, 1);
      first.release();
      first.release();
      expect(first.isActive, isFalse);
      expect(second.isActive, isTrue);
      expect(() => first.layout, throwsStateError);
      cache.close();
      expect(second.isActive, isFalse);
      expect(native.isDisposed, isTrue);
      expect(() => fragment.hitAt(Offset.zero), throwsStateError);
      expect(cache.activeLeases, 0);
      expect(cache.estimatedRetainedBytes, 0);
      second.release();
    },
  );

  test(
    'cache-only mixed lookup neither shapes nor changes budget on a miss',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 1,
        maxEstimatedBytes: 100,
      );
      addTearDown(cache.close);
      final input = mixedInlineInput();
      expect(
        cache.tryAcquireInlineCached(
          content: input.content,
          width: 100,
          dimensions: _dimensions,
        ),
        isNull,
      );
      expect(cache.layoutBuildCount, 0);
      expect(cache.entryCount, 0);
      expect(
        () => cache.acquireInline(
          content: input.content,
          width: 100,
          dimensions: _dimensions,
        ),
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (error) => error.failure,
            'input budget',
            ForumBodyParagraphBudgetFailure.content,
          ),
        ),
      );
      expect(cache.layoutBuildCount, 0);
    },
  );

  test(
    'ordinary and mixed resources share pins, eviction and owner budget',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final input = mixedInlineInput();
      final plain = cache.acquire(content: input.base, width: 100);
      final parent = cache.acquireInline(
        content: input.content,
        width: 100,
        dimensions: _dimensions,
      );
      expect(cache.entryCount, 2);
      expect(cache.activeLeases, 2);
      ForumBodyParagraphBudgetException? rejection;
      try {
        cache.acquire(content: input.annotation, width: 100);
      } on ForumBodyParagraphBudgetException catch (error) {
        rejection = error;
      }
      expect(rejection!.failure, ForumBodyParagraphBudgetFailure.pinned);
      expect(cache.layoutBuildCount, 2);
      expect(cache.isBlockedByExternalPins(rejection, [parent]), isTrue);
      expect(
        cache.isBlockedByExternalPins(rejection, [parent, plain]),
        isFalse,
      );
      final baseEngine = plain.layout;
      plain.release();
      final child = cache.acquire(content: input.annotation, width: 100);
      expect(baseEngine.isDisposed, isTrue);
      expect(parent.isActive, isTrue);
      expect(cache.entryCount, 2);
      child.release();
      cache.clearUnpinned();
      expect(cache.entryCount, 1);
      expect(parent.isActive, isTrue);
      parent.release();
      cache.clearUnpinned();
      expect(cache.entryCount, 0);
      expect(cache.estimatedRetainedBytes, 0);
    },
  );

  test(
    'mixed native identity includes child geometry and snapshots caller lists',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 8,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final input = mixedInlineInput();
      final dimensions = [..._dimensions];
      final first = cache.acquireInline(
        content: input.content,
        width: 100,
        dimensions: dimensions,
      );
      first.release();
      dimensions.clear();
      final same = cache.tryAcquireInlineCached(
        content: input.content,
        width: 100,
        dimensions: _dimensions,
      )!;
      expect(cache.layoutBuildCount, 1);
      expect(same.layout.atomBoxes.single.toRect().size, const Size(40, 30));
      same.release();
      for (final dimension in const [
        PlaceholderDimensions(
          size: Size(50, 30),
          alignment: ui.PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          baselineOffset: 26,
        ),
        PlaceholderDimensions(
          size: Size(40, 35),
          alignment: ui.PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          baselineOffset: 26,
        ),
        PlaceholderDimensions(
          size: Size(40, 30),
          alignment: ui.PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          baselineOffset: 20,
        ),
      ]) {
        expect(
          cache.tryAcquireInlineCached(
            content: input.content,
            width: 100,
            dimensions: [dimension],
          ),
          isNull,
        );
        cache
            .acquireInline(
              content: input.content,
              width: 100,
              dimensions: [dimension],
            )
            .release();
      }
      expect(cache.entryCount, 4);
      expect(cache.layoutBuildCount, 4);
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'intrinsic aliases ignore valid requested widths but still validate warm inputs',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final input = mixedInlineInput();
      final first = cache.acquireInline(
        content: input.content,
        width: 10,
        dimensions: _dimensions,
        layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
      );
      final second = cache.acquireInline(
        content: input.content,
        width: 300,
        dimensions: _dimensions,
        layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
      );
      expect(identical(first.layout, second.layout), isTrue);
      expect(first.layout.width, 80);
      expect(cache.layoutBuildCount, 1);
      expect(
        () => cache.tryAcquireInlineCached(
          content: input.content,
          width: 0,
          dimensions: _dimensions,
          layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
        ),
        throwsA(isA<ForumBodyParagraphLayoutException>()),
      );
      expect(
        () => cache.tryAcquireInlineCached(
          content: input.content,
          width: 300,
          dimensions: [],
          layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
        ),
        throwsArgumentError,
      );
      final wrapped = cache.acquireInline(
        content: input.content,
        width: 100,
        dimensions: _dimensions,
      );
      expect(identical(wrapped.layout, first.layout), isFalse);
      expect(cache.layoutBuildCount, 2);
      first.release();
      second.release();
      wrapped.release();
    },
  );

  test(
    'effective parent scales determine cache hits rather than scaler equality',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final input = mixedInlineInput();
      final first = cache.acquireInline(
        content: input.content,
        width: 120,
        dimensions: _dimensions,
        textScaler: _Scaler((size) => size * 1.5),
      );
      final same = cache.acquireInline(
        content: input.content,
        width: 120,
        dimensions: _dimensions,
        textScaler: _Scaler((size) => size == 20 ? 30 : 200),
      );
      final different = cache.acquireInline(
        content: input.content,
        width: 120,
        dimensions: _dimensions,
        textScaler: _Scaler((size) => size * 2),
      );
      expect(identical(first.layout, same.layout), isTrue);
      expect(identical(first.layout, different.layout), isFalse);
      expect(cache.layoutBuildCount, 2);
      expect(first.layout.atomBoxes.single.toRect().size, const Size(40, 30));
      first.release();
      same.release();
      different.release();
    },
  );

  test(
    'combined pure budget probe deduplicates both resource kinds without shaping',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 1,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final input = mixedInlineInput();
      final probe = cache.createBudgetProbe();
      addTearDown(probe.close);
      void include() => probe.includeInline(
        content: input.content,
        width: 100,
        dimensions: _dimensions,
        minimumLineCount: 1,
        textScaler: TextScaler.noScaling,
      );
      include();
      include();
      expect(cache.entryCount, 0);
      expect(cache.layoutBuildCount, 0);
      expect(cache.activeLeases, 0);
      expect(
        () => probe.include(
          content: input.base,
          width: 100,
          minimumLineCount: 1,
          textScaler: TextScaler.noScaling,
        ),
        throwsA(isA<ForumBodyParagraphBudgetException>()),
      );
      expect(cache.layoutBuildCount, 0);
      probe.close();
      expect(include, throwsStateError);
    },
  );

  test(
    'estimated-byte budget includes mixed resident entries and deduplicates aliases',
    () {
      final measured = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      final input = mixedInlineInput();
      measured
          .acquireInline(
            content: input.content,
            width: 100,
            dimensions: _dimensions,
          )
          .release();
      final footprint = measured.estimatedRetainedBytes;
      measured.close();
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: footprint,
      );
      addTearDown(cache.close);
      final first = cache.acquireInline(
        content: input.content,
        width: 100,
        dimensions: _dimensions,
      );
      final alias = cache.acquireInline(
        content: input.content,
        width: 100,
        dimensions: _dimensions,
      );
      expect(cache.estimatedRetainedBytes, footprint);
      expect(cache.activeLeases, 2);
      expect(
        () => cache.acquire(content: input.base, width: 100),
        throwsA(isA<ForumBodyParagraphBudgetException>()),
      );
      final probe = cache.createBudgetProbe();
      addTearDown(probe.close);
      probe.includeInline(
        content: input.content,
        width: 100,
        dimensions: _dimensions,
        minimumLineCount: 0,
        textScaler: TextScaler.noScaling,
      );
      expect(
        () => probe.include(
          content: input.base,
          width: 100,
          minimumLineCount: 0,
          textScaler: TextScaler.noScaling,
        ),
        throwsA(isA<ForumBodyParagraphBudgetException>()),
      );
      first.release();
      alias.release();
    },
  );

  test(
    'owner closure during input validation prevents any late native build',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      final input = mixedInlineInput();
      expect(
        () => cache.acquireInline(
          content: input.content,
          width: 100,
          dimensions: _dimensions,
          textScaler: _Scaler((size) {
            cache.close();
            return size;
          }),
        ),
        throwsStateError,
      );
      expect(cache.isClosed, isTrue);
      expect(cache.layoutBuildCount, 0);
      expect(cache.activeLeases, 0);
      expect(cache.estimatedRetainedBytes, 0);
    },
  );

  test(
    'owner closure during actual shaping retires the unadmitted native parent',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      final input = mixedInlineInput();
      var calls = 0;
      expect(
        () => cache.acquireInline(
          content: input.content,
          width: 100,
          dimensions: _dimensions,
          textScaler: _Scaler((size) {
            if (++calls == 2) cache.close();
            return size;
          }),
        ),
        throwsStateError,
      );
      expect(cache.isClosed, isTrue);
      expect(cache.layoutBuildCount, 1);
      expect(cache.activeLeases, 0);
      expect(cache.estimatedRetainedBytes, 0);
    },
  );

  test('pins acquired during shaping cannot escape the shared budget', () {
    final cache = ForumBodyParagraphCache(
      maxEntries: 1,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(cache.close);
    final input = mixedInlineInput();
    ForumBodyParagraphLease? nested;
    var calls = 0;
    expect(
      () => cache.acquireInline(
        content: input.content,
        width: 100,
        dimensions: _dimensions,
        textScaler: _Scaler((size) {
          if (++calls == 2) {
            nested = cache.acquire(content: input.base, width: 100);
          }
          return size;
        }),
      ),
      throwsA(
        isA<ForumBodyParagraphBudgetException>().having(
          (error) => error.failure,
          'nested pins',
          ForumBodyParagraphBudgetFailure.pinned,
        ),
      ),
    );
    expect(nested!.isActive, isTrue);
    expect(cache.entryCount, 1);
    expect(cache.activeLeases, 1);
    expect(cache.layoutBuildCount, 2);
    nested!.release();
    cache.clearUnpinned();
    expect(cache.estimatedRetainedBytes, 0);
  });

  test(
    'reentrant same-key shaping cannot overwrite a live native cache entry',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final input = mixedInlineInput();
      var calls = 0;
      expect(
        () => cache.acquireInline(
          content: input.content,
          width: 100,
          dimensions: _dimensions,
          textScaler: _Scaler((size) {
            if (++calls == 2) {
              cache.acquireInline(
                content: input.content,
                width: 100,
                dimensions: _dimensions,
              );
            }
            return size;
          }),
        ),
        throwsStateError,
      );
      expect(cache.entryCount, 0);
      expect(cache.activeLeases, 0);
      expect(cache.layoutBuildCount, 0);
      final recovered = cache.acquireInline(
        content: input.content,
        width: 100,
        dimensions: _dimensions,
      );
      expect(cache.layoutBuildCount, 1);
      recovered.release();
    },
  );
}

final class _Scaler extends TextScaler {
  const _Scaler(this.resolve);
  final double Function(double) resolve;
  @override
  double scale(double size) => resolve(size);
  @override
  double get textScaleFactor => 1;
}
