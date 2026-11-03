import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_emphasis_parent_fixture.dart';

typedef _Case = ({
  MixedEmphasisParentFixture fixture,
  MixedEmphasisParentMeasurement original,
  ForumBodyInlineEmphasisChildrenPlan children,
  ForumBodyInlineParagraphLease finalParent,
});
ForumBodyParagraphCache _cache() {
  final cache = ForumBodyParagraphCache(
    maxEntries: 512,
    maxEstimatedBytes: 1 << 26,
  );
  addTearDown(cache.close);
  return cache;
}

_Case _case(
  ForumBodyParagraphCache cache, {
  String? child,
  String side = 'over',
  bool large = true,
  TextDirection direction = TextDirection.ltr,
  TextScaler scaler = TextScaler.noScaling,
  double width = 300,
  String suffix = 'Q<br>R',
}) {
  final f = MixedEmphasisParentFixture(
    child ?? mixedEmphasisChildren[1],
    parentStyle:
        'text-emphasis:circle;text-emphasis-position:$side;line-height:.4',
    prefix:
        '${large ? '<span style="font-size:120px;text-emphasis:none">W</span>' : ''}P',
    suffix: suffix,
    direction: direction,
    width: width,
  );
  final original = f.finish(f.open(cache, scaler: scaler), cache).value;
  addTearDown(original.lease.release);
  final rowWork = ForumBodyInlineEmphasisRowPlacementPreparation(
    input: f.bands(original, cache, scaler: scaler),
    ensureOwner: () {},
  );
  late ForumBodyInlineEmphasisRowPlacement rows;
  try {
    while (!rowWork.isReady) {
      rowWork.advance(maxParts: 1);
    }
    rows = rowWork.takePlacement();
  } finally {
    rowWork.close();
  }
  final childWork = ForumBodyInlineEmphasisChildrenPlanPreparation(
    placement: rows,
    ensureOwner: () {},
  );
  late ForumBodyInlineEmphasisChildrenPlan children;
  try {
    while (!childWork.isReady) {
      childWork.advance(maxParts: 1);
    }
    children = childWork.takePlan();
  } finally {
    childWork.close();
  }
  final finalParent = cache.acquireInline(
    content: original.glyphInput.glyphs,
    width: width,
    dimensions: children.page.dimensions,
    layoutMode: children.page.layoutMode,
    textScaler: rows.input.fonts.textScaler,
  );
  addTearDown(finalParent.release);
  return (
    fixture: f,
    original: original,
    children: children,
    finalParent: finalParent,
  );
}

({ForumBodyInlineEmphasisReflowReference value, int parts}) _finish(
  ForumBodyInlineEmphasisReflowReferencePreparation work, {
  int quantum = 1,
}) {
  var parts = 0;
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(30000));
      final used = work.advance(maxParts: quantum);
      expect(used, inInclusiveRange(1, quantum));
      parts += used;
    }
    expect(work.advance(maxParts: 1), 0);
    return (value: work.takeReference(), parts: parts);
  } finally {
    work.close();
  }
}

ForumBodyInlineEmphasisReflowReferencePreparation _work(
  _Case actual, {
  ForumBodyInlineParagraphLease? finalParent,
  void Function()? guard,
}) => ForumBodyInlineEmphasisReflowReferencePreparation(
  children: actual.children,
  original: actual.original.lease,
  finalParent: finalParent ?? actual.finalParent,
  ensureOwner: guard ?? () {},
);
void _rect(Rect a, Rect b) {
  expect(a.left, closeTo(b.left, 1e-3));
  expect(a.top, closeTo(b.top, 1e-3));
  expect(a.right, closeTo(b.right, 1e-3));
  expect(a.bottom, closeTo(b.bottom, 1e-3));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final side in ['over', 'under']) {
    for (final large in [false, true]) {
      for (final direction in TextDirection.values) {
        for (final scaler in [
          TextScaler.noScaling,
          const MixedEmphasisCurve(),
        ]) {
          for (final width in [70.0, 300.0]) {
            for (final (index, child) in mixedEmphasisChildren.indexed) {
              test(
                'owned natural reflow reference $index/$side/$large/$direction/$scaler/$width',
                () {
                  final cache = _cache(),
                      actual = _case(
                        cache,
                        child: child,
                        side: side,
                        large: large,
                        direction: direction,
                        scaler: scaler,
                        width: width,
                      );
                  final before = (
                    cache.layoutBuildCount,
                    cache.pictureBuildCount,
                    cache.hitCount,
                    cache.activeLeases,
                  );
                  final result = _finish(_work(actual)),
                      batch = _finish(_work(actual), quantum: 7),
                      ref = result.value;
                  expect(result.parts, batch.parts);
                  expect(ref.baselineDeltas, batch.value.baselineDeltas);
                  expect(ref.children, same(actual.children));
                  expect(
                    ref.originalLines,
                    same(actual.original.lease.layout.lines),
                  );
                  expect(ref.finalLines, same(actual.finalParent.layout.lines));
                  expect(
                    ref.originalAtomBoxes,
                    same(actual.original.lease.layout.atomBoxes),
                  );
                  expect(
                    ref.finalAtomBoxes,
                    same(actual.finalParent.layout.atomBoxes),
                  );
                  expect(
                    ref.originalInputIdentity,
                    actual.original.lease.nativeInputIdentity,
                  );
                  expect(
                    ref.finalInputIdentity,
                    actual.finalParent.nativeInputIdentity,
                  );
                  expect(
                    ref.originalHeight,
                    actual.original.lease.layout.height,
                  );
                  expect(ref.finalHeight, actual.finalParent.layout.height);
                  expect(ref.width, width);
                  for (final (i, delta) in ref.baselineDeltas.indexed) {
                    expect(
                      delta,
                      ref.finalLines[i].baseline -
                          ref.originalLines[i].baseline,
                    );
                  }
                  expect(
                    () => ref.baselineDeltas.clear(),
                    throwsUnsupportedError,
                  );
                  expect((
                    cache.layoutBuildCount,
                    cache.pictureBuildCount,
                    cache.hitCount,
                    cache.activeLeases,
                  ), before);
                  // Compare against freshly queried final glyphs. A baseline delta cannot
                  // be used to invent source ownership or replace a changed font input.
                  final job = ForumBodyInlineEmphasisGeometryPreparation(
                    input: actual.fixture.text,
                    parent: actual.finalParent,
                    ensureOwner: () {},
                  );
                  late ForumBodyInlineEmphasisTextGeometry geometry;
                  try {
                    while (!job.isReady) {
                      job.advance(maxParts: 1);
                    }
                    geometry = job.takeGeometry();
                  } finally {
                    job.close();
                  }
                  final old = actual.children.placement.input.fonts.geometry;
                  expect(geometry.atomLineIndices, old.atomLineIndices);
                  expect(geometry.targets, hasLength(old.targets.length));
                  for (final (i, font) in geometry.parentFontBounds.indexed) {
                    if (font == null) {
                      expect(old.parentFontBounds[i], isNull);
                    } else {
                      _rect(
                        font,
                        old.parentFontBounds[i]!.shift(
                          Offset(0, ref.baselineDeltas[i]),
                        ),
                      );
                    }
                  }
                  for (final (i, t) in geometry.targets.indexed) {
                    expect(t.unit, same(old.targets[i].unit));
                    expect(t.lineIndex, old.targets[i].lineIndex);
                    _rect(
                      t.governingFontBounds,
                      old.targets[i].governingFontBounds.shift(
                        Offset(0, ref.baselineDeltas[t.lineIndex]),
                      ),
                    );
                  }
                  expect(cache.activeLeases, 2);
                },
              );
            }
          }
        }
      }
    }
  }
  test(
    'vertical slot exception keeps all actual horizontal font and source inputs strict',
    () {
      final cache = _cache(),
          actual = _case(cache),
          old = actual.original.lease,
          target = actual.finalParent;
      expect(actual.children.hasChanges, isTrue);
      expect(
        old.hasSameSourceAndInputsExceptSlotVerticalGeometry(target),
        isTrue,
      );
      final content = old.content, dims = actual.children.page.dimensions;
      final foreign = _cache(), other = _case(cache);
      final variants = [
        foreign.acquireInline(content: content, width: 300, dimensions: dims),
        other.finalParent,
        cache.acquireInline(content: content, width: 301, dimensions: dims),
        cache.acquireInline(
          content: content,
          width: 300,
          dimensions: dims,
          textScaler: TextScaler.linear(1.1),
        ),
        cache.acquireInline(
          content: content,
          width: 300,
          dimensions: dims,
          rowIsolationPitch: 256,
        ),
        cache.acquireInline(
          content: content,
          width: 300,
          dimensions: [
            for (final (i, d) in dims.indexed)
              i == 0
                  ? PlaceholderDimensions(
                      size: Size(d.size.width + 1, d.size.height),
                      alignment: d.alignment,
                      baseline: d.baseline,
                      baselineOffset: d.baselineOffset,
                    )
                  : d,
          ],
        ),
      ];
      for (final parent in variants) {
        addTearDown(parent.release);
        expect(
          old.hasSameSourceAndInputsExceptSlotVerticalGeometry(parent),
          isFalse,
        );
        expect(
          () => _work(actual, finalParent: parent),
          throwsA(
            isA<ForumBodyParagraphRowReferenceException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyParagraphRowReferenceFailure.source,
            ),
          ),
        );
      }
      expect(old.isActive, isTrue);
      expect(target.isActive, isTrue);
      expect(
        _finish(_work(actual)).value.baselineDeltas.any((d) => d != 0),
        isTrue,
      );
      final single = _case(cache, suffix: 'Q');
      final intrinsic = cache.acquireInline(
        content: single.original.lease.content,
        width: 300,
        dimensions: single.children.page.dimensions,
        layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
      );
      addTearDown(intrinsic.release);
      expect(
        single.original.lease.hasSameSourceAndInputsExceptSlotVerticalGeometry(
          intrinsic,
        ),
        isFalse,
      );
      expect(
        () => _work(single, finalParent: intrinsic),
        throwsA(isA<ForumBodyParagraphRowReferenceException>()),
      );
    },
  );
  test(
    'allowed vertical key change still requires exact actual planned target dimensions',
    () {
      final cache = _cache(),
          actual = _case(cache),
          old = actual.original.lease;
      final wrong = cache.acquireInline(
        content: old.content,
        width: 300,
        dimensions: [
          for (final (i, d) in actual.children.page.dimensions.indexed)
            i == 0
                ? PlaceholderDimensions(
                    size: Size(d.size.width, d.size.height + 2),
                    alignment: d.alignment,
                    baseline: d.baseline,
                    baselineOffset: d.baselineOffset! + 1,
                  )
                : d,
        ],
      );
      addTearDown(wrong.release);
      expect(
        old.hasSameSourceAndInputsExceptSlotVerticalGeometry(wrong),
        isTrue,
      );
      final before = (
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.hitCount,
        cache.activeLeases,
      );
      expect(
        () => _finish(_work(actual, finalParent: wrong)),
        throwsA(
          isA<ForumBodyParagraphRowReferenceException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphRowReferenceFailure.source,
          ),
        ),
      );
      expect((
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.hitCount,
        cache.activeLeases,
      ), before);
    },
  );
  test(
    'all actual row slot and ready boundaries preserve both borrowed callers',
    () {
      final cache = _cache(), actual = _case(cache);
      final parts = _finish(_work(actual)).parts;
      for (var boundary = 0; boundary <= parts; boundary++) {
        var active = true;
        final work = _work(
          actual,
          guard: () {
            if (!active) throw StateError('Retired');
          },
        );
        for (var n = 0; n < boundary; n++) {
          work.advance(maxParts: 1);
        }
        active = false;
        expect(
          work.isReady ? work.takeReference : () => work.advance(maxParts: 1),
          throwsStateError,
        );
        work.close();
        expect(cache.activeLeases, 2);
      }
      for (final mode in [0, 1, 2]) {
        var armed = false;
        late ForumBodyInlineEmphasisReflowReferencePreparation work;
        work = _work(
          actual,
          guard: () {
            if (armed) {
              if (mode == 0 || mode == 2 && work.isReady) {
                work.close();
              } else if (mode == 1) {
                work.advance(maxParts: 1);
              }
            }
          },
        );
        armed = true;
        expect(() => _finish(work), throwsStateError);
        expect(work.isReady, isFalse);
        expect(cache.activeLeases, 2);
      }
      final ready = _work(actual);
      while (!ready.isReady) {
        ready.advance(maxParts: 1);
      }
      actual.finalParent.release();
      expect(ready.takeReference, throwsStateError);
      expect(cache.activeLeases, 1);
    },
  );
  test('original handle retirement rejects an otherwise ready relation', () {
    final cache = _cache(), actual = _case(cache), ready = _work(actual);
    while (!ready.isReady) {
      ready.advance(maxParts: 1);
    }
    actual.original.lease.release();
    expect(ready.takeReference, throwsStateError);
    expect(cache.activeLeases, 1);
    expect(
      actual.original.lease.hasSameSourceAndInputsExceptSlotVerticalGeometry(
        actual.finalParent,
      ),
      isFalse,
    );
  });
  test(
    'bounded numeric reference survives eviction without authorizing a new owner',
    () {
      final cache = _cache(),
          actual = _case(cache),
          ref = _finish(_work(actual)).value;
      for (final limits in [
        (1, 512, 1048576.0),
        (4096, 0, 1048576.0),
        (4096, 512, 1.0),
      ]) {
        expect(
          () => ForumBodyInlineEmphasisReflowReferencePreparation(
            children: actual.children,
            original: actual.original.lease,
            finalParent: actual.finalParent,
            ensureOwner: () {},
            maxLines: limits.$1,
            maxAtoms: limits.$2,
            maxHeight: limits.$3,
          ),
          throwsA(
            isA<ForumBodyParagraphRowReferenceException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyParagraphRowReferenceFailure.limit,
            ),
          ),
        );
      }
      final before = List<double>.of(ref.baselineDeltas),
          boxes = ref.finalAtomBoxes.map((b) => b.toRect()).toList();
      actual.original.lease.release();
      actual.finalParent.release();
      cache.clearUnpinned();
      expect(cache.entryCount, 0);
      expect(ref.baselineDeltas, before);
      expect(ref.finalAtomBoxes.map((b) => b.toRect()), boxes);
      expect(() => _work(actual), throwsStateError);
      expect(cache.activeLeases, 0);
    },
  );
}
