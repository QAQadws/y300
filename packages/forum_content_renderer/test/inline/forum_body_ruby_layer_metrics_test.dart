import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_column_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ForumBodyParagraphCache cache;
  setUp(
    () => cache = ForumBodyParagraphCache(
      maxEntries: 16,
      maxEstimatedBytes: 1 << 23,
    ),
  );
  tearDown(() => cache.close());

  ({ForumBodyRubyGroupMetrics metrics, List<ForumBodyTextLease?> leases})
  measure({
    List<ForumBodyParagraphContent>? input,
    List<ForumBodyRubySide> sides = const [
      ForumBodyRubySide.over,
      ForumBodyRubySide.under,
      ForumBodyRubySide.over,
    ],
    List<double>? gaps,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final parts = input ?? rubyColumnInput();
    // Empty input is not a native band child. The base still needs its actual
    // font strut; empty annotation ranks borrow no native resource.
    final glyphs = parts
        .where((part) => part.projection.text.isNotEmpty)
        .toList();
    final band = ForumBodyTextBandContent(contexts: glyphs);
    final leases = <ForumBodyTextLease?>[
      for (final (index, part) in parts.indexed)
        part.projection.text.isNotEmpty
            ? cache.acquireBandChild(
                content: band,
                childIndex: glyphs.indexOf(part),
                textScaler: textScaler,
              )
            : index == 0
            ? cache.acquire(content: part, width: 16384, textScaler: textScaler)
            : null,
    ];
    addTearDown(() {
      for (final lease in leases) {
        lease?.release();
      }
    });
    final before = (
      cache.layoutBuildCount,
      cache.pictureBuildCount,
      cache.activeLeases,
    );
    final metrics = ForumBodyRubyGroupMetrics.measureLayers(
      cache: cache,
      baseLease: leases.first!,
      annotations: [
        for (var i = 1; i < parts.length; i++)
          (
            content: parts[i],
            lease: leases[i],
            gap: gaps?[i - 1] ?? 0.0,
            side: sides[i - 1],
          ),
      ],
    );
    expect((
      cache.layoutBuildCount,
      cache.pictureBuildCount,
      cache.activeLeases,
    ), before);
    return (metrics: metrics, leases: leases);
  }

  for (final lineHeight in [1.0, .25]) {
    test(
      'three ranks share one base and stack outward with glyph overhang, height=$lineHeight',
      () {
        final result = measure(
          input: rubyColumnInput(
            annotations: const [('xy', 10), ('z', 15), ('qqqqqqqqqq', 5)],
            lineHeight: lineHeight,
          ),
          gaps: [1, 2, 3],
        );
        final metrics = result.metrics;
        expect(metrics.size, const Size(50, 56));
        expect(metrics.baseOffset.dx, 5);
        // RT rank 2 is above rank 0; rank 1 is below the base.
        expect(
          metrics.annotations.map((item) => (item.bandTop, item.bandBottom)),
          [(8.0, 18.0), (41.0, 56.0), (0.0, 5.0)],
        );
        for (final (index, annotation) in metrics.annotations.indexed) {
          final native = result.leases[index + 1]!.layout;
          expect(annotation.fontBaseline, native.alphabeticBaseline);
          expect(
            annotation.bounds.shift(annotation.offset).top,
            annotation.bandTop,
          );
          expect(
            annotation.bounds.shift(annotation.offset).bottom,
            annotation.bandBottom,
          );
        }
        expect(
          metrics.baseline,
          metrics.baseOffset.dy +
              result.leases.first!.layout.alphabeticBaseline,
        );
        expect(cache.layoutBuildCount, 1);
        expect(cache.pictureBuildCount, 0);
        expect(cache.activeLeases, 4);
        expect(metrics.annotations[2].offset.dx, 0);
        expect(() => metrics.annotationOffset, throwsStateError);
        expect(() => metrics.side, throwsStateError);
        expect(() => metrics.annotations.clear(), throwsUnsupportedError);
      },
    );
  }

  for (final side in ForumBodyRubySide.values) {
    test('three fixed $side ranks never merge or overlap', () {
      final metrics = measure(
        sides: [side, side, side],
        gaps: [1, 2, 3],
      ).metrics;
      expect(metrics.size, const Size(40, 56));
      final levels = metrics.annotations;
      if (side == ForumBodyRubySide.over) {
        expect(levels.map((item) => (item.bandTop, item.bandBottom)), [
          (25.0, 35.0),
          (8.0, 23.0),
          (0.0, 5.0),
        ]);
      } else {
        expect(levels.map((item) => (item.bandTop, item.bandBottom)), [
          (21.0, 31.0),
          (33.0, 48.0),
          (51.0, 56.0),
        ]);
      }
    });
  }

  test(
    'per-rank unions align actual font baselines and propagate inner height outward',
    () {
      final large = measure(
        input: rubyColumnInput(
          base: 'A',
          baseSize: 30,
          annotations: const [('x', 10), ('y', 15), ('z', 5)],
        ),
      );
      final small = measure(
        input: rubyColumnInput(
          base: 'B',
          annotations: const [('a', 15), ('b', 5), ('c', 10)],
        ),
      );
      final before = (
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.activeLeases,
      );
      final level = ForumBodyRubyLevelMetrics.single(
        large.metrics,
      ).include(small.metrics);
      expect(level.annotations.map((item) => item.ascent + item.descent), [
        15,
        15,
        10,
      ]);
      expect(() => level.annotations.clear(), throwsUnsupportedError);
      expect(() => level.side, throwsStateError);
      expect(large.metrics.needsLevelAlignment(level), isTrue);
      expect(small.metrics.needsLevelAlignment(level), isTrue);
      final a = large.metrics.alignedTo(level);
      final b = small.metrics.alignedTo(level);
      expect(a.size.height, 70);
      expect(b.size.height, 70);
      expect(a.baseline, b.baseline);
      for (var i = 0; i < 3; i++) {
        expect(
          a.annotations[i].offset.dy +
              large.leases[i + 1]!.layout.alphabeticBaseline,
          b.annotations[i].offset.dy +
              small.leases[i + 1]!.layout.alphabeticBaseline,
        );
      }
      final again = b.alignedTo(level);
      expect(again.baseOffset, b.baseOffset);
      expect(
        again.annotations.map((item) => item.offset),
        b.annotations.map((item) => item.offset),
      );
      expect(again.size, b.size);
      expect(again.needsLevelAlignment(level), isFalse);
      expect((
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.activeLeases,
      ), before);
    },
  );

  test(
    'missing inner RT keeps outer rank and does not create a handle or gap',
    () {
      final missing = measure(
        input: rubyColumnInput(
          annotations: const [('', 10), ('', 15), ('q', 5)],
        ),
        gaps: [100, 200, 3],
      );
      expect(missing.metrics.size.height, 28);
      expect(missing.metrics.annotations.map((item) => item.hasAnnotation), [
        false,
        false,
        true,
      ]);
      expect(missing.leases.whereType<ForumBodyTextLease>().length, 2);
      final complete = measure(gaps: [1, 2, 3]);
      final level = ForumBodyRubyLevelMetrics.single(
        complete.metrics,
      ).include(missing.metrics);
      expect(level.annotations.map((item) => item.gap), [1, 2, 3]);
      expect(missing.metrics.needsLevelAlignment(level), isTrue);
      final aligned = missing.metrics.alignedTo(level);
      expect(
        aligned.annotations[2].bandTop,
        complete.metrics.annotations[2].bandTop,
      );
      expect(
        aligned.annotations[2].offset,
        complete.metrics.annotations[2].offset,
      );
      expect(aligned.size, complete.metrics.size);
      expect(cache.activeLeases, 6);
    },
  );

  test(
    'empty base with only an outer annotation retains its one native font strut',
    () {
      final result = measure(
        input: rubyColumnInput(
          base: '',
          annotations: const [('', 10), ('', 15), ('q', 5)],
        ),
      );
      expect(result.metrics.size, const Size(5, 25));
      expect(result.metrics.annotations.map((item) => item.hasAnnotation), [
        false,
        false,
        true,
      ]);
      expect(cache.activeLeases, 2);
    },
  );

  test('nonlinear scaling is independently resolved before stack placement', () {
    final result = measure(textScaler: const _Scaler());
    // Native rows round 22.5/12.5 to 23/13. Preserve those actual bounds rather
    // than uniformly scaling a finished box or guessing fractional row sizes.
    expect(result.metrics.size, const Size(60, 91));
    expect(result.metrics.annotations.map((item) => item.bounds.height), [
      25,
      23,
      13,
    ]);
    expect(
      result.metrics.annotations[2].bandBottom,
      result.metrics.annotations[0].bandTop,
    );
    expect(cache.layoutBuildCount, 1);
  });

  test(
    'unions reject different rank counts and side order without borrowing ownership',
    () {
      final result = measure();
      final swapped = measure(
        sides: const [
          ForumBodyRubySide.under,
          ForumBodyRubySide.over,
          ForumBodyRubySide.over,
        ],
      );
      final fewer = measure(
        input: rubyColumnInput(annotations: const [('x', 10)]),
        sides: const [ForumBodyRubySide.over],
      );
      final level = ForumBodyRubyLevelMetrics.single(result.metrics);
      for (final other in [swapped.metrics, fewer.metrics]) {
        expect(level.contains(other), isFalse);
        expect(
          () => level.include(other),
          throwsA(isA<ForumBodyRubyGroupException>()),
        );
        expect(
          () => other.alignedTo(level),
          throwsA(isA<ForumBodyRubyGroupException>()),
        );
      }
      expect(result.leases.every((lease) => lease!.isActive), isTrue);
    },
  );

  test('failed outer-layer admission preserves all caller leases', () {
    final result = measure();
    final fresh = rubyColumnInput();
    final foreign = ForumBodyParagraphCache(
      maxEntries: 4,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(foreign.close);
    final foreignRT = foreign.acquire(content: fresh[3], width: 100);
    addTearDown(foreignRT.release);
    final parts = result.leases.map((lease) => lease!.content).toList();
    Matcher failure(ForumBodyRubyGroupFailure value) =>
        isA<ForumBodyRubyGroupException>().having(
          (error) => error.failure,
          'failure',
          value,
        );
    for (final (gap, width, outer, content, matcher) in [
      (
        0.0,
        30.0,
        result.leases[3],
        parts[3],
        failure(ForumBodyRubyGroupFailure.overflow),
      ),
      (
        double.nan,
        100.0,
        result.leases[3],
        parts[3],
        failure(ForumBodyRubyGroupFailure.geometry),
      ),
      (
        0.0,
        100.0,
        result.leases[3],
        fresh[3],
        failure(ForumBodyRubyGroupFailure.content),
      ),
      (0.0, 100.0, null, parts[3], failure(ForumBodyRubyGroupFailure.content)),
      (0.0, 100.0, foreignRT, fresh[3], isA<StateError>()),
    ]) {
      expect(
        () => ForumBodyRubyGroupMetrics.measureLayers(
          cache: cache,
          baseLease: result.leases.first!,
          maxWidth: width,
          annotations: [
            (
              content: parts[1],
              lease: result.leases[1],
              gap: 0.0,
              side: ForumBodyRubySide.over,
            ),
            (
              content: parts[2],
              lease: result.leases[2],
              gap: 0.0,
              side: ForumBodyRubySide.under,
            ),
            (
              content: content,
              lease: outer,
              gap: gap,
              side: ForumBodyRubySide.over,
            ),
          ],
        ),
        throwsA(matcher),
      );
      expect(result.leases.every((lease) => lease!.isActive), isTrue);
      expect(foreignRT.isActive, isTrue);
      expect(cache.activeLeases, 4);
      expect(cache.pictureBuildCount, 0);
    }
    // Finite individual gaps may still overflow the aggregate stack.
    expect(
      () => ForumBodyRubyGroupMetrics.measureLayers(
        cache: cache,
        baseLease: result.leases.first!,
        annotations: [
          for (var i = 1; i < parts.length; i++)
            (
              content: parts[i],
              lease: result.leases[i],
              gap: 10000.0,
              side: ForumBodyRubySide.over,
            ),
        ],
      ),
      throwsA(failure(ForumBodyRubyGroupFailure.geometry)),
    );
    expect(result.leases.every((lease) => lease!.isActive), isTrue);
  });

  test(
    'empty columns and empty annotations with spurious leases are rejected',
    () {
      final empty = rubyColumnInput(
        base: '',
        annotations: const [('', 10), ('', 15), ('', 5)],
      );
      final base = cache.acquire(content: empty.first, width: 100);
      addTearDown(base.release);
      expect(
        () => ForumBodyRubyGroupMetrics.measureLayers(
          cache: cache,
          baseLease: base,
          annotations: [
            for (final item in empty.skip(1))
              (
                content: item,
                lease: null,
                gap: 0.0,
                side: ForumBodyRubySide.over,
              ),
          ],
        ),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
      expect(
        () => ForumBodyRubyGroupMetrics.measureLayers(
          cache: cache,
          baseLease: base,
          annotations: [],
        ),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
      final nonempty = measure();
      expect(
        () => ForumBodyRubyGroupMetrics.measureLayers(
          cache: cache,
          baseLease: nonempty.leases.first!,
          annotations: [
            (
              content: empty[1],
              lease: base,
              gap: 0.0,
              side: ForumBodyRubySide.over,
            ),
          ],
        ),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
      expect(base.isActive, isTrue);
    },
  );

  test(
    'numeric stack remains usable after every borrowed handle and owner retire',
    () {
      final result = measure();
      for (final lease in result.leases) {
        lease?.release();
      }
      cache.close();
      final aligned = result.metrics.alignedTo(
        ForumBodyRubyLevelMetrics.single(result.metrics),
      );
      expect(aligned.size, const Size(40, 50));
      expect(aligned.annotations.length, 3);
      expect(cache.activeLeases, 0);
      expect(cache.estimatedRetainedBytes, 0);
    },
  );
}

final class _Scaler extends TextScaler {
  const _Scaler();
  @override
  double scale(double fontSize) =>
      fontSize <= 10 ? fontSize * 2.5 : fontSize * 1.5;
  @override
  double get textScaleFactor => 1.5;
}
