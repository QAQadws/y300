import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_emphasis_parent_fixture.dart';

typedef _Input = ({
  MixedEmphasisParentFixture fixture,
  MixedEmphasisParentMeasurement original,
  ForumBodyInlineEmphasisRowPlacement placement,
});
typedef _Measurement = ({
  ForumBodyInlineEmphasisReflowReference reference,
  ForumBodyInlineParagraphLease parent,
  ForumBodyInlineEmphasisTextGeometry geometry,
});
ForumBodyParagraphCache _cache({int entries = 512}) {
  final cache = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: 1 << 26,
  );
  addTearDown(cache.close);
  return cache;
}

_Input _input(
  ForumBodyParagraphCache cache, {
  String? child,
  String side = 'over',
  TextDirection direction = TextDirection.ltr,
  TextScaler scaler = TextScaler.noScaling,
  double width = 300,
  String? parentStyle,
  String? prefix,
  String suffix = 'Q<br>R',
}) {
  final fixture = MixedEmphasisParentFixture(
    child ?? mixedEmphasisChildren[1],
    width: width,
    direction: direction,
    parentStyle:
        parentStyle ??
        'text-emphasis:circle;text-emphasis-position:$side;line-height:.4',
    prefix:
        prefix ?? '<span style="font-size:120px;text-emphasis:none">W</span>P',
    suffix: suffix,
  );
  final original = fixture
      .finish(fixture.open(cache, scaler: scaler), cache)
      .value;
  addTearDown(original.lease.release);
  final rows = ForumBodyInlineEmphasisRowPlacementPreparation(
    input: fixture.bands(original, cache, scaler: scaler),
    ensureOwner: () {},
  );
  try {
    while (!rows.isReady) {
      rows.advance(maxParts: 1);
    }
    return (
      fixture: fixture,
      original: original,
      placement: rows.takePlacement(),
    );
  } finally {
    rows.close();
  }
}

ForumBodyInlineEmphasisReflowPreparation _work(
  _Input input,
  ForumBodyParagraphCache cache, {
  void Function()? guard,
  Iterable<ForumBodyNativeParagraphLease> Function()? owned,
  int maxOwnedLeases = 32768,
}) => ForumBodyInlineEmphasisReflowPreparation(
  placement: input.placement,
  original: input.original.lease,
  cache: cache,
  ensureOwner: guard ?? () {},
  additionalOwnedLeases: owned,
  maxOwnedLeases: maxOwnedLeases,
);
({int parts, _Measurement value}) _finish(
  ForumBodyInlineEmphasisReflowPreparation work,
  ForumBodyParagraphCache cache, {
  int quantum = 1,
  bool cachedOnly = false,
}) {
  var parts = 0;
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(50000));
      final before = (cache.layoutBuildCount, cache.pictureBuildCount);
      final step = work.advance(maxParts: quantum, cachedOnly: cachedOnly);
      expect(step.partsPrepared, inInclusiveRange(1, quantum));
      expect(step.waitingForLayoutBudget, isFalse);
      expect(work.cacheMiss, isFalse);
      expect(step.nativeLayoutsBuilt, cache.layoutBuildCount - before.$1);
      expect(step.nativeLayoutsBuilt, inInclusiveRange(0, 1));
      expect(step.picturesRecorded, 0);
      expect(cache.pictureBuildCount, before.$2);
      parts += step.partsPrepared;
    }
    expect(work.advance(maxParts: 1).partsPrepared, 0);
    final value = work.takeMeasurement();
    expect(work.nativeLeases, isEmpty);
    return (parts: parts, value: value);
  } finally {
    work.close();
  }
}

ForumBodyParagraphLease _pin(ForumBodyParagraphCache cache) {
  final doc = const ForumBodyParser().parse(
    html: '<p>external</p>',
    sourceId: 'external-pin',
    conversionIdentity: 'none',
  );
  final content = const ForumBodyParagraphContentBuilder().build(
    document: doc,
    styles: const ForumBodyStyleResolver().resolve(
      doc,
      ForumBodyReaderStyle(
        textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20),
        fontRevision: 'external-pin',
        linkColor: const Color(0xff0000ff),
      ),
    ),
    path: '0',
  );
  final pin = cache.acquire(content: content, width: 300);
  addTearDown(pin.release);
  return pin;
}

class _MutableScaler extends TextScaler {
  const _MutableScaler(this.resolve);
  final double Function(double) resolve;
  @override
  double scale(double size) => resolve(size);

  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  final cases = [
    for (final side in ['over', 'under'])
      for (final direction in TextDirection.values)
        for (final scaler in [TextScaler.noScaling, const MixedEmphasisCurve()])
          for (final width in [70.0, 300.0])
            for (final (index, child) in mixedEmphasisChildren.indexed)
              (
                side: side,
                direction: direction,
                scaler: scaler,
                width: width,
                index: index,
                child: child,
              ),
  ];
  for (final c in cases) {
    test(
      'owned final parent transaction ${c.index}/${c.side}/${c.direction}/${c.scaler}/${c.width}',
      () {
        final cache = _cache(),
            input = _input(
              cache,
              child: c.child,
              side: c.side,
              direction: c.direction,
              scaler: c.scaler,
              width: c.width,
            );
        final before = (cache.layoutBuildCount, cache.pictureBuildCount),
            job = _work(input, cache);
        final first = _finish(job, cache), value = first.value;
        addTearDown(value.parent.release);
        expect(value.reference.children.placement, same(input.placement));
        expect(value.parent.content, same(input.original.glyphInput.glyphs));
        expect(
          value.reference.originalLines,
          same(input.original.lease.layout.lines),
        );
        expect(value.reference.finalLines, same(value.parent.layout.lines));
        expect(value.geometry.lines, same(value.parent.layout.lines));
        expect(
          value.geometry.nativeInputIdentity,
          value.parent.nativeInputIdentity,
        );
        expect(
          value.geometry.input,
          same(input.placement.input.fonts.geometry.input),
        );
        expect(
          value.geometry.atomLineIndices,
          input.placement.input.fonts.geometry.atomLineIndices,
        );
        for (final (i, target) in value.geometry.targets.indexed) {
          expect(
            target.unit,
            same(input.placement.input.fonts.geometry.targets[i].unit),
          );
        }
        expect(
          value.parent.layout.dimensions,
          value.reference.children.page.dimensions,
        );
        expect(input.original.lease.isActive, isTrue);
        expect(cache.activeLeases, 2);
        expect(cache.layoutBuildCount - before.$1, inInclusiveRange(0, 1));
        expect(cache.pictureBuildCount, before.$2);
        expect(
          value.reference.children.hasChanges,
          input.placement.childShifts.any((s) => s != null),
        );
        for (final (i, delta) in value.reference.baselineDeltas.indexed) {
          expect(
            delta,
            value.parent.layout.lines[i].baseline -
                input.original.lease.layout.lines[i].baseline,
          );
        }
        final warmBefore = (cache.layoutBuildCount, cache.pictureBuildCount);
        final second = _finish(
          _work(input, cache),
          cache,
          quantum: 7,
          cachedOnly: true,
        );
        addTearDown(second.value.parent.release);
        expect(second.parts, first.parts);
        expect(
          second.value.parent.nativeInputIdentity,
          value.parent.nativeInputIdentity,
        );
        expect(
          second.value.reference.baselineDeltas,
          value.reference.baselineDeltas,
        );
        expect((cache.layoutBuildCount, cache.pictureBuildCount), warmBefore);
        expect(
          () => value.reference.children.page.parentRequest.acquire(
            cache,
            width: c.width,
            textScaler: c.scaler,
            cachedOnly: false,
          ),
          throwsA(
            isA<ForumBodyParagraphLayoutException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyParagraphLayoutFailure.emphasis,
            ),
          ),
        );
      },
    );
  }
  test(
    'known initial limits reject before child work or a new native request',
    () {
      final cache = _cache(), input = _input(cache);
      final before = (
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.activeLeases,
      );
      for (final limit in [
        (1, 512, 1048576.0),
        (4096, 0, 1048576.0),
        (4096, 512, 1.0),
      ]) {
        expect(
          () => ForumBodyInlineEmphasisReflowPreparation(
            placement: input.placement,
            original: input.original.lease,
            cache: cache,
            ensureOwner: () {},
            maxLines: limit.$1,
            maxAtoms: limit.$2,
            maxHeight: limit.$3,
          ),
          throwsA(
            isA<ForumBodyEmphasisGeometryException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyEmphasisGeometryFailure.limit,
            ),
          ),
        );
      }
      expect((
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.activeLeases,
      ), before);
    },
  );
  test('long fractional font rows retain their actual final geometry', () {
    final cache = _cache(),
        input = _input(
          cache,
          parentStyle:
              'text-emphasis:circle;line-height:.4;white-space:pre-wrap',
          prefix:
              '<span style="text-emphasis:none;font-size:19.7px">${'A\n' * 3000}</span><span style="font-size:120px;text-emphasis:none">W</span>P',
        );
    final result = _finish(_work(input, cache), cache, quantum: 17).value;
    addTearDown(result.parent.release);
    expect(result.geometry.lineCount, greaterThan(3000));
    expect(result.reference.originalLines.last.baseline, greaterThan(20000));
    expect(result.reference.baselineDeltas.any((d) => d != 0), isTrue);
    expect(
      result.geometry.parentFontBounds,
      hasLength(result.geometry.lineCount),
    );
    expect(result.geometry.lines, same(result.parent.layout.lines));
    expect(
      result.geometry.targets,
      hasLength(input.placement.input.fonts.geometry.targets.length),
    );
    expect(cache.activeLeases, 2);
  });
  test(
    'whole styled source unit keeps its later governing row during reflow',
    () {
      final cache = _cache(),
          input = _input(
            cache,
            width: 5,
            child:
                '<ruby style="font-size:1px;text-emphasis:none">A<rt>x</rt></ruby>',
            prefix: '<span style="font-size:31px">؀</span>A',
            suffix: '',
          );
      final target = input.placement.input.fonts.geometry.targets.single;
      expect(target.lineIndex, greaterThan(target.sourceStartLine));
      final result = _finish(_work(input, cache), cache, quantum: 3).value;
      addTearDown(result.parent.release);
      final actual = result.geometry.targets.single;
      expect(actual.unit, same(target.unit));
      expect(actual.lineIndex, target.lineIndex);
      expect(actual.sourceStartLine, target.sourceStartLine);
      expect(actual.sourceEndLine, target.sourceEndLine);
    },
  );
  test(
    'cold cached-only miss resumes the completed pure plan without shaping',
    () {
      final cache = _cache(), input = _input(cache), work = _work(input, cache);
      addTearDown(work.close);
      final before = (
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.activeLeases,
      );
      for (var n = 0; !work.cacheMiss; n++) {
        expect(n, lessThan(50000));
        final s = work.advance(maxParts: 1, cachedOnly: true);
        expect(s.nativeLayoutsBuilt, 0);
        expect(s.waitingForLayoutBudget, isFalse);
      }
      expect((
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.activeLeases,
      ), before);
      expect(work.nativeLeases, isEmpty);
      final value = _finish(work, cache, quantum: 3).value;
      addTearDown(value.parent.release);
      expect(cache.layoutBuildCount, before.$1 + 1);
      expect(input.original.lease.isActive, isTrue);
    },
  );
  test('external pin wait remains stable and resumes on the same job', () {
    final cache = _cache(entries: 2),
        input = _input(cache),
        pin = _pin(cache),
        work = _work(input, cache);
    addTearDown(work.close);
    final before = (
      cache.layoutBuildCount,
      cache.pictureBuildCount,
      cache.activeLeases,
    );
    for (var n = 0; ; n++) {
      expect(n, lessThan(50000));
      final s = work.advance(maxParts: 1);
      if (s.waitingForLayoutBudget) break;
      expect(work.cacheMiss, isFalse);
    }
    expect((
      cache.layoutBuildCount,
      cache.pictureBuildCount,
      cache.activeLeases,
    ), before);
    for (var n = 0; n < 3; n++) {
      final s = work.advance(maxParts: 64);
      expect(s.partsPrepared, 0);
      expect(s.waitingForLayoutBudget, isTrue);
      expect(s.nativeLayoutsBuilt, 0);
    }
    pin.release();
    final measured = _finish(work, cache, quantum: 13).value;
    addTearDown(measured.parent.release);
    expect(cache.layoutBuildCount, before.$1 + 1);
    expect(cache.activeLeases, 2);
  });
  test(
    'complete caller-owned prefix is content pressure and never a permanent wait',
    () {
      final cache = _cache(entries: 2),
          input = _input(cache),
          pin = _pin(cache),
          work = _work(input, cache, owned: () => [pin]);
      final before = (
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.activeLeases,
      );
      expect(
        () => _finish(work, cache),
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.content,
          ),
        ),
      );
      expect((
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.activeLeases,
      ), before);
      expect(input.original.lease.isActive, isTrue);
      expect(pin.isActive, isTrue);
    },
  );
  test(
    'budget wakeup recaptures changed ownership before attempting the native target',
    () {
      final cache = _cache(entries: 2),
          input = _input(cache),
          pin = _pin(cache);
      var owned = false;
      final work = _work(input, cache, owned: () => owned ? [pin] : const []);
      addTearDown(work.close);
      for (var n = 0; ; n++) {
        expect(n, lessThan(50000));
        if (work.advance(maxParts: 1).waitingForLayoutBudget) break;
      }
      final alias = cache.acquire(content: pin.content, width: 300);
      alias.release();
      owned = true;
      expect(
        () => _finish(work, cache),
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.content,
          ),
        ),
      );
      expect(cache.activeLeases, 2);
    },
  );
  test('overlapping caller prefix deduplicates actual native keys', () {
    final cache = _cache(entries: 2), input = _input(cache);
    final result = _finish(
      _work(input, cache, owned: () => [input.original.lease]),
      cache,
    ).value;
    addTearDown(result.parent.release);
    expect(cache.activeLeases, 2);
  });
  test(
    'retired caller scaler is never sampled during child replan or parent acquire',
    () {
      var calls = 0, retired = false;
      final cache = _cache(),
          scaler = _MutableScaler((size) {
            if (retired) throw StateError('Caller scaler was retained');
            calls++;
            return size * (size < 25 ? 1.4 : 1.1);
          }),
          input = _input(cache, scaler: scaler),
          sampled = calls;
      retired = true;
      final result = _finish(_work(input, cache), cache).value;
      addTearDown(result.parent.release);
      expect(calls, sampled);
      expect(result.reference.children.hasChanges, isTrue);
    },
  );
  test(
    'every child request reference and ready boundary releases only the new parent',
    () {
      final cache = _cache(), input = _input(cache);
      final complete = _finish(_work(input, cache), cache);
      complete.value.parent.release();
      for (var boundary = 0; boundary <= complete.parts; boundary++) {
        var active = true;
        final work = _work(
          input,
          cache,
          guard: () {
            if (!active) throw StateError('Retired');
          },
        );
        for (var n = 0; n < boundary; n++) {
          work.advance(maxParts: 1);
        }
        active = false;
        expect(
          work.isReady ? work.takeMeasurement : () => work.advance(maxParts: 1),
          throwsStateError,
        );
        work.close();
        expect(cache.activeLeases, 1);
        expect(input.original.lease.isActive, isTrue);
      }
    },
  );
  test(
    'callback close reentry and acquired-before-adoption races release all owned resources',
    () {
      final cache = _cache(), input = _input(cache);
      for (final mode in [0, 1, 2, 3, 4]) {
        var armed = false;
        late ForumBodyInlineEmphasisReflowPreparation work;
        work = _work(
          input,
          cache,
          guard: () {
            if (!armed) return;
            if (mode == 0 ||
                mode == 2 && work.isReady ||
                mode == 3 &&
                    cache.activeLeases > 1 &&
                    work.nativeLeases.isEmpty ||
                mode == 4 && work.nativeLeases.isNotEmpty) {
              work.close();
            } else if (mode == 1) {
              work.advance(maxParts: 1);
            }
          },
        );
        armed = true;
        expect(() => _finish(work, cache), throwsStateError);
        expect(work.nativeLeases, isEmpty);
        expect(cache.activeLeases, 1);
      }
    },
  );
  test(
    'foreign or unbounded prefix and original retirement cannot publish a measurement',
    () {
      final cache = _cache(),
          input = _input(cache),
          foreign = _cache(),
          pin = _pin(foreign);
      expect(
        () => _finish(_work(input, cache, owned: () => [pin]), cache),
        throwsStateError,
      );
      expect(cache.activeLeases, 1);
      expect(
        () => _finish(
          _work(
            input,
            cache,
            owned: () => [input.original.lease],
            maxOwnedLeases: 1,
          ),
          cache,
        ),
        throwsA(
          isA<ForumBodyEmphasisGeometryException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyEmphasisGeometryFailure.limit,
          ),
        ),
      );
      final ready = _work(input, cache);
      for (var n = 0; !ready.isReady; n++) {
        expect(n, lessThan(50000));
        ready.advance(maxParts: 1);
      }
      expect(cache.activeLeases, 2);
      input.original.lease.release();
      expect(ready.takeMeasurement, throwsStateError);
      expect(cache.activeLeases, 0);
    },
  );
}
