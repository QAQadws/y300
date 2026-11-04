import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_emphasis_parent_fixture.dart';

ForumBodyParagraphCache _cache({int entries = 512, int bytes = 1 << 26}) {
  final c = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: bytes,
  );
  addTearDown(c.close);
  return c;
}

MixedEmphasisAllocatedSource _input(
  ForumBodyParagraphCache cache, {
  String? child,
  double width = 300,
  TextDirection direction = TextDirection.ltr,
  TextScaler scaler = TextScaler.noScaling,
  String prefix = 'P',
  String suffix = 'Q',
  ForumBodyParagraphLayoutMode? mode,
}) {
  final result = measureMixedEmphasisAllocatedSource(
    MixedEmphasisParentFixture(
      child ?? mixedEmphasisChildren.first,
      width: width,
      direction: direction,
      prefix: prefix,
      suffix: suffix,
      layoutMode: mode,
      readerTextStyle: const TextStyle(
        fontFamily: 'Ahem',
        fontSize: 20,
        color: Color(0xff123456),
        backgroundColor: Color(0x44226688),
        decoration: TextDecoration.underline,
      ),
    ),
    cache,
    scaler: scaler,
  );
  result.natural.release();
  cache.clearUnpinned();
  expect(cache.activeLeases, 1);
  expect(cache.entryCount, 1);
  return result;
}

ForumBodyInlineEmphasisPaintPreparation _work(
  MixedEmphasisAllocatedSource input,
  ForumBodyParagraphCache cache, {
  TextScaler scaler = TextScaler.noScaling,
  bool paint = true,
  void Function()? guard,
  void Function()? visible,
  Iterable<ForumBodyNativeParagraphLease> Function()? owned,
  int maxOwned = 32768,
  int maxGlyphQueries = 65536,
}) => ForumBodyInlineEmphasisPaintPreparation(
  allocation: input.allocation,
  source: input.source,
  cache: cache,
  expectedTextScaler: scaler,
  ensureOwner: guard ?? () {},
  ensureVisibleOwner: visible,
  additionalOwnedLeases: owned,
  preparePaint: paint,
  maxOwnedLeases: maxOwned,
  maxGlyphQueries: maxGlyphQueries,
);

({
  ForumBodyInlineEmphasisPaintBinding binding,
  int parts,
  int shapes,
  int pictures,
})
_finish(
  ForumBodyInlineEmphasisPaintPreparation work,
  ForumBodyParagraphCache cache, {
  int quantum = 1,
  bool cachedOnly = false,
}) {
  final builds = cache.layoutBuildCount, pictures = cache.pictureBuildCount;
  var parts = 0;
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(200000));
      final before = (cache.layoutBuildCount, cache.pictureBuildCount);
      final step = work.advance(maxParts: quantum, cachedOnly: cachedOnly);
      expect(step.partsPrepared, inInclusiveRange(1, quantum));
      expect(step.nativeLayoutsBuilt, cache.layoutBuildCount - before.$1);
      expect(step.picturesRecorded, cache.pictureBuildCount - before.$2);
      expect(
        step.nativeLayoutsBuilt + step.picturesRecorded,
        inInclusiveRange(0, 1),
      );
      expect(step.waitingForLayoutBudget, isFalse);
      expect(work.cacheMiss, isFalse);
      parts += step.partsPrepared;
    }
    expect(work.advance(maxParts: 1).partsPrepared, 0);
    final binding = work.takeBinding();
    expect(work.nativeLeases, isEmpty);
    return (
      binding: binding,
      parts: parts,
      shapes: cache.layoutBuildCount - builds,
      pictures: cache.pictureBuildCount - pictures,
    );
  } finally {
    work.close();
  }
}

void _miss(
  ForumBodyInlineEmphasisPaintPreparation work,
  ForumBodyParagraphCache cache,
) {
  final before = (cache.layoutBuildCount, cache.pictureBuildCount);
  for (var n = 0; !work.cacheMiss; n++) {
    expect(n, lessThan(100000));
    expect(work.isReady, isFalse);
    final step = work.advance(maxParts: 1, cachedOnly: true);
    expect(step.partsPrepared, 1);
    expect(step.waitingForLayoutBudget, isFalse);
  }
  expect((cache.layoutBuildCount, cache.pictureBuildCount), before);
}

Matcher _budget(ForumBodyParagraphBudgetFailure f) => throwsA(
  isA<ForumBodyParagraphBudgetException>().having(
    (e) => e.failure,
    'failure',
    f,
  ),
);
Matcher _limit() => throwsA(
  isA<ForumBodyEmphasisAllocationException>().having(
    (e) => e.failure,
    'failure',
    ForumBodyEmphasisAllocationFailure.limit,
  ),
);

ForumBodyParagraphLease _pin(ForumBodyParagraphCache cache, int id) {
  final doc = const ForumBodyParser().parse(
    html: '<p>pin$id</p>',
    sourceId: 'phase-pin$id',
    conversionIdentity: 'none',
  );
  final content = const ForumBodyParagraphContentBuilder().build(
    document: doc,
    path: '0',
    styles: const ForumBodyStyleResolver().resolve(
      doc,
      ForumBodyReaderStyle(
        textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20),
        fontRevision: 'phase-pin',
        linkColor: const Color(0xff0000ff),
      ),
    ),
  );
  final p = cache.acquire(content: content, width: 300);
  addTearDown(p.release);
  return p;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final (i, child) in mixedEmphasisChildren.indexed) {
    for (final direction in TextDirection.values) {
      for (final scaler in [TextScaler.noScaling, const MixedEmphasisCurve()]) {
        for (final width in [70.0, 300.0]) {
          test(
            'whole phase cold/warm transaction $i/$direction/$scaler/$width',
            () {
              final cache = _cache(),
                  input = _input(
                    cache,
                    child: child,
                    width: width,
                    direction: direction,
                    scaler: scaler,
                  );
              final cold = _finish(_work(input, cache, scaler: scaler), cache);
              expect(cold.shapes, 3);
              expect(cold.pictures, 3);
              expect(cold.binding.isPaintPrepared, isTrue);
              expect(cold.binding.nativeLeases, hasLength(3));
              expect(cold.binding.view.nativeLeases, hasLength(4));
              expect(
                cold.binding.view.reference.allocation,
                same(input.allocation),
              );
              expect(input.source.layout.isPaintPrepared, isFalse);
              expect(() => cold.binding.phases.clear(), throwsUnsupportedError);
              final identities = cold.binding.phases
                  .map((p) => p.nativeInputIdentity)
                  .toList();
              cold.binding.close();
              cold.binding.close();
              expect(cache.activeLeases, 1);
              expect(cold.binding.isPaintPrepared, isFalse);
              expect(cold.binding.nativeLeases, isEmpty);
              final warm = _finish(
                _work(input, cache, scaler: scaler),
                cache,
                quantum: 32,
                cachedOnly: true,
              );
              expect(warm.shapes, 0);
              expect(warm.pictures, 0);
              expect(
                warm.binding.phases.map((p) => p.nativeInputIdentity),
                identities,
              );
              warm.binding.close();
              expect(cache.activeLeases, 1);
              expect(input.source.isActive, isTrue);
            },
          );
        }
      }
    }
  }

  test(
    'cached-only miss resumes the same worker without hidden native work',
    () {
      final cache = _cache(), input = _input(cache), work = _work(input, cache);
      _miss(work, cache);
      expect(work.nativeLeases, isEmpty);
      expect(cache.activeLeases, 1);
      final result = _finish(work, cache, quantum: 512);
      expect(result.shapes, 3);
      expect(result.pictures, 3);
      result.binding.close();
      expect(cache.activeLeases, 1);
    },
  );

  test(
    'measurement phases do not record; cached first-paint miss retains pending lease',
    () {
      final cache = _cache(), input = _input(cache);
      final pure = _finish(
        _work(input, cache, paint: false),
        cache,
        quantum: 512,
      );
      expect(pure.shapes, 3);
      expect(pure.pictures, 0);
      expect(pure.binding.isPaintPrepared, isFalse);
      pure.binding.close();
      final work = _work(input, cache);
      _miss(work, cache);
      expect(work.nativeLeases, hasLength(1));
      expect(cache.activeLeases, 2);
      final result = _finish(work, cache, quantum: 512);
      expect(result.shapes, 0);
      expect(result.pictures, 3);
      result.binding.close();
      expect(cache.activeLeases, 1);
    },
  );

  test(
    'a partial warm prefix survives a later miss without duplicate phase acquisition',
    () {
      final cache = _cache(),
          input = _input(cache),
          first = _finish(_work(input, cache), cache).binding;
      final request = first.view.reference.requests.first,
          alias = request.acquire(
            cache,
            width: input.allocation.input.natural.requestWidth,
            textScaler: input.allocation.input.natural.textScaler,
            cachedOnly: true,
          )!;
      addTearDown(alias.release);
      first.close();
      cache.clearUnpinned();
      expect(cache.entryCount, 2);
      final work = _work(input, cache);
      _miss(work, cache);
      expect(work.nativeLeases, hasLength(1));
      expect(cache.activeLeases, 3);
      final result = _finish(work, cache, quantum: 512);
      expect(result.shapes, 2);
      expect(result.pictures, 2);
      result.binding.close();
      expect(cache.activeLeases, 2);
      alias.release();
      expect(cache.activeLeases, 1);
    },
  );

  test(
    'external pins wait on one revision and resume all acquired phases in place',
    () {
      final cache = _cache(entries: 16),
          input = _input(cache),
          pins = [for (var i = 0; i < 13; i++) _pin(cache, i)],
          work = _work(input, cache);
      var waiting = false;
      for (var n = 0; !waiting; n++) {
        expect(n, lessThan(10000));
        waiting = work.advance(maxParts: 32).waitingForLayoutBudget;
      }
      expect(work.nativeLeases, hasLength(2));
      expect(work.lastBudgetRejection, isNotNull);
      final before = (
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.hitCount,
        cache.activeLeases,
      );
      for (var n = 0; n < 4; n++) {
        final s = work.advance(maxParts: 32);
        expect(s.partsPrepared, 0);
        expect(s.waitingForLayoutBudget, isTrue);
      }
      expect((
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.hitCount,
        cache.activeLeases,
      ), before);
      pins.first.release();
      final result = _finish(work, cache, quantum: 32);
      expect(result.shapes, 1);
      expect(result.pictures, 1);
      result.binding.close();
      expect(input.source.isActive, isTrue);
    },
  );

  test('caller-owned prefix cannot masquerade as external pressure', () {
    final cache = _cache(entries: 16),
        input = _input(cache),
        pins = [for (var i = 0; i < 13; i++) _pin(cache, i)],
        before = (
          cache.layoutBuildCount,
          cache.pictureBuildCount,
          cache.activeLeases,
        );
    final work = _work(input, cache, owned: () => pins);
    expect(
      () => _finish(work, cache),
      _budget(ForumBodyParagraphBudgetFailure.content),
    );
    expect((
      cache.layoutBuildCount,
      cache.pictureBuildCount,
      cache.activeLeases,
    ), before);
    expect(input.source.isActive, isTrue);
  });

  test(
    'complete four-input byte footprint fails before first phase acquisition',
    () {
      final warmCache = _cache(),
          large = 'P' * 256,
          measure = _input(warmCache, prefix: large),
          probe = warmCache.createBudgetProbe(captureInputEstimates: true);
      late int sourceBytes;
      try {
        probe.includeLease(measure.source);
        sourceBytes = probe.snapshotNativeEstimates().single.estimatedBytes;
      } finally {
        probe.close();
      }
      final cache = _cache(bytes: sourceBytes * 3 + 20000),
          input = _input(cache, prefix: large),
          before = (
            cache.layoutBuildCount,
            cache.pictureBuildCount,
            cache.activeLeases,
          ),
          work = _work(input, cache);
      expect(
        () => _finish(work, cache),
        _budget(ForumBodyParagraphBudgetFailure.content),
      );
      expect((
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.activeLeases,
      ), before);
    },
  );

  test(
    'prefix callback release retires stale rejection before classifying ownership',
    () {
      final cache = _cache(entries: 16),
          input = _input(cache),
          pins = [for (var i = 0; i < 13; i++) _pin(cache, i)];
      var calls = 0;
      final work = _work(
        input,
        cache,
        owned: () {
          if (++calls == 4) pins.first.release();
          return const <ForumBodyNativeParagraphLease>[];
        },
      );
      final result = _finish(work, cache, quantum: 32);
      expect(calls, greaterThanOrEqualTo(4));
      result.binding.close();
      expect(input.source.isActive, isTrue);
    },
  );

  test(
    'complete expected font scales sampled once; mismatches and callback retirement reject',
    () {
      final cache = _cache(), input = _input(cache), scaler = _CountingScaler();
      final result = _finish(_work(input, cache, scaler: scaler), cache);
      expect(
        scaler.counts.keys.toSet(),
        input.allocation.input.natural.effectiveScales.keys.toSet(),
      );
      expect(scaler.counts.values.every((n) => n == 1), isTrue);
      result.binding.close();
      expect(
        () => _finish(_work(input, cache, scaler: TextScaler.linear(2)), cache),
        throwsA(
          isA<ForumBodyEmphasisAllocationException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyEmphasisAllocationFailure.source,
          ),
        ),
      );
      expect(cache.activeLeases, 1);
      ForumBodyInlineEmphasisPaintPreparation? active;
      active = _work(
        input,
        cache,
        scaler: _CountingScaler(() => active!.close()),
      );
      expect(() => active!.advance(maxParts: 1), throwsStateError);
      expect(cache.activeLeases, 1);
    },
  );

  test('every cancellation slice releases only owned phases', () {
    final cache = _cache(),
        input = _input(cache),
        full = _finish(_work(input, cache), cache),
        parts = full.parts;
    full.binding.close();
    for (var stop = 0; stop <= parts; stop++) {
      final job = _work(input, cache);
      for (var n = 0; n < stop && !job.isReady; n++) {
        job.advance(maxParts: 1);
      }
      job.close();
      expect(job.nativeLeases, isEmpty);
      expect(() => job.advance(maxParts: 1), throwsStateError);
      expect(job.takeBinding, throwsStateError);
      expect(cache.activeLeases, 1, reason: 'stop $stop');
    }
  });

  test('retirement while adopting new phase releases the unassigned alias', () {
    final cache = _cache(), input = _input(cache);
    ForumBodyInlineEmphasisPaintPreparation? active;
    var retired = false;
    active = _work(
      input,
      cache,
      guard: () {
        if (active != null &&
            cache.activeLeases > 1 + active.nativeLeases.length) {
          retired = true;
          active.close();
        }
      },
    );
    expect(() => _finish(active!, cache), throwsStateError);
    expect(retired, isTrue);
    expect(cache.activeLeases, 1);
    expect(input.source.isActive, isTrue);
  });

  test(
    'visible ownership survives transfer and closes independently of preparing owner',
    () {
      final cache = _cache(), input = _input(cache);
      var preparing = true, visible = true;
      final work = _work(
            input,
            cache,
            guard: () {
              if (!preparing) throw StateError('preparing');
            },
            visible: () {
              if (!visible) throw StateError('visible');
            },
          ),
          result = _finish(work, cache).binding;
      preparing = false;
      work.close();
      expect(cache.activeLeases, 4);
      final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
      try {
        result.view.paintPhaseRow(
          canvas,
          Offset.zero,
          0,
          ForumBodyParagraphPaintLayer.foreground,
        );
        visible = false;
        expect(
          () => result.view.paintPhaseRow(
            canvas,
            Offset.zero,
            0,
            ForumBodyParagraphPaintLayer.foreground,
          ),
          throwsStateError,
        );
      } finally {
        recorder.endRecording().dispose();
      }
      result.close();
      expect(cache.activeLeases, 1);
      expect(input.source.isActive, isTrue);
    },
  );

  test(
    'retirement at final handoff closes prepared phases and preserves caller source',
    () {
      final cache = _cache(), input = _input(cache);
      var retire = false;
      ForumBodyInlineEmphasisPaintPreparation? active;
      active = _work(
        input,
        cache,
        visible: () {
          if (retire) active!.close();
        },
      );
      while (!active.isReady) {
        active.advance(maxParts: 32);
      }
      expect(cache.activeLeases, 4);
      retire = true;
      expect(active.takeBinding, throwsStateError);
      expect(cache.activeLeases, 1);
    },
  );

  test(
    'limits and intrinsic input retain current source identity and original constraint',
    () {
      final cache = _cache(),
          input = _input(
            cache,
            width: 800,
            mode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
          );
      final result = _finish(_work(input, cache), cache).binding;
      expect(
        result.view.reference.nativeFootprint.every((r) => r.width == 800),
        isTrue,
      );
      expect(input.source.layout.width, lessThan(800));
      result.close();
      expect(() => _work(input, cache, maxOwned: 3), _limit());
      expect(
        () => _finish(_work(input, cache, maxGlyphQueries: 0), cache),
        _limit(),
      );
      expect(cache.activeLeases, 1);
      final alias = input.allocation.input.request.acquire(
        cache,
        width: 800,
        textScaler: input.allocation.input.natural.textScaler,
        cachedOnly: true,
      )!;
      addTearDown(alias.release);
      expect(
        () => _finish(
          _work(input, cache, maxOwned: 4, owned: () => [alias]),
          cache,
        ),
        _limit(),
      );
      expect(alias.isActive, isTrue);
      expect(input.source.isActive, isTrue);
    },
  );
}

final class _CountingScaler extends TextScaler {
  _CountingScaler([this.onSample]);
  final void Function()? onSample;
  final counts = <double, int>{};
  @override
  double scale(double size) {
    counts.update(size, (n) => n + 1, ifAbsent: () => 1);
    onSample?.call();
    return size;
  }

  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}
