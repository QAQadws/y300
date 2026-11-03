import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_emphasis_parent_fixture.dart';

ForumBodyParagraphCache _cache() {
  final cache = ForumBodyParagraphCache(
    maxEntries: 512,
    maxEstimatedBytes: 1 << 26,
  );
  addTearDown(cache.close);
  return cache;
}

ForumBodyInlineEmphasisRowPlacement _placement(
  MixedEmphasisParentFixture f,
  MixedEmphasisParentMeasurement measured,
  ForumBodyParagraphCache cache, {
  TextScaler scaler = TextScaler.noScaling,
}) {
  final work = ForumBodyInlineEmphasisRowPlacementPreparation(
    input: f.bands(measured, cache, scaler: scaler),
    ensureOwner: () {},
  );
  try {
    while (!work.isReady) {
      work.advance(maxParts: 1);
    }
    return work.takePlacement();
  } finally {
    work.close();
  }
}

({ForumBodyInlineEmphasisChildrenPlan plan, int parts}) _finish(
  ForumBodyInlineEmphasisChildrenPlanPreparation work, {
  int quantum = 1,
}) {
  var parts = 0;
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(50000));
      final used = work.advance(maxParts: quantum);
      expect(used, inInclusiveRange(1, quantum));
      parts += used;
    }
    expect(work.advance(maxParts: 1), 0);
    return (plan: work.takePlan(), parts: parts);
  } finally {
    work.close();
  }
}

List<Object?> _line(ForumBodyParagraphLine l) => [
  l.startUtf16,
  l.endUtf16,
  l.coverageStartUtf16,
  l.coverageEndUtf16,
  l.engineStartUtf16,
  l.engineEndUtf16,
  l.engineCoverageStartUtf16,
  l.engineCoverageEndUtf16,
  l.unpaintedTrailingSpaceStartUtf16,
  l.engineUnpaintedTrailingSpaceStartUtf16,
  l.canBreakBefore,
  l.canBreakAfter,
  l.left,
  l.width,
];
List<Object?> _snapshot(ForumBodyInlineEmphasisChildrenPlan p) => [
  ...p.changedAtoms,
  for (final d in p.page.dimensions) [d.size, d.baselineOffset],
  for (final atom in p.page.rubyAtoms)
    if (atom is ForumBodyRubyTreeEmphasisAtomPlan)
      [
        atom.request,
        atom.format.frame.size,
        atom.format.frame.baseline,
        for (final m in atom.format.placement.marks)
          [
            m.source,
            m.mark,
            m.row,
            m.baselineOrigin,
            m.fontOffset,
            m.fontBounds,
          ],
      ],
];
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
            for (final (fixture, child) in mixedEmphasisChildren.indexed) {
              test(
                'complete child root replan $fixture/$side/$large/$direction/$scaler/$width',
                () {
                  final cache = _cache(),
                      f = MixedEmphasisParentFixture(
                        child,
                        width: width,
                        direction: direction,
                        parentStyle:
                            'text-emphasis:circle;text-emphasis-position:$side;line-height:.4',
                        prefix:
                            '${large ? '<span style="font-size:120px;text-emphasis:none">W</span>' : ''}P',
                      );
                  final measured = f
                      .finish(f.open(cache, scaler: scaler), cache)
                      .value;
                  addTearDown(measured.lease.release);
                  final placement = _placement(
                    f,
                    measured,
                    cache,
                    scaler: scaler,
                  );
                  final before = (
                    cache.layoutBuildCount,
                    cache.pictureBuildCount,
                    cache.hitCount,
                    cache.activeLeases,
                  );
                  final first = _finish(
                    ForumBodyInlineEmphasisChildrenPlanPreparation(
                      placement: placement,
                      ensureOwner: () {},
                    ),
                  );
                  final batched = _finish(
                    ForumBodyInlineEmphasisChildrenPlanPreparation(
                      placement: placement,
                      ensureOwner: () {},
                    ),
                    quantum: 7,
                  );
                  expect(first.parts, batched.parts);
                  expect(_snapshot(first.plan), _snapshot(batched.plan));
                  expect((
                    cache.layoutBuildCount,
                    cache.pictureBuildCount,
                    cache.hitCount,
                    cache.activeLeases,
                  ), before);
                  final result = first.plan,
                      page = result.page,
                      old = measured.plan;
                  expect(result.placement, same(placement));
                  expect(page.content, same(old.content));
                  expect(page.trimmedAtomIndices, old.trimmedAtomIndices);
                  expect(page.layoutMode, old.layoutMode);
                  expect(page.content.projection, same(old.content.projection));
                  expect(result.changedAtoms, [
                    for (final (i, s) in placement.childShifts.indexed)
                      if (s != null) i,
                  ]);
                  expect(
                    result.hasChanges,
                    placement.childShifts.any((s) => s != null),
                  );
                  expect(
                    () => result.changedAtoms.clear(),
                    throwsUnsupportedError,
                  );
                  for (final (i, atom) in page.rubyAtoms.indexed) {
                    final source = old.rubyAtoms[i],
                        shift = placement.childShifts[i];
                    expect(page.rootFonts[i], same(old.rootFonts[i]));
                    expect(
                      page.containerBackgrounds[i],
                      same(old.containerBackgrounds[i]),
                    );
                    expect(
                      page.dimensions[i].size.width,
                      old.dimensions[i].size.width,
                    );
                    if (shift == null) {
                      expect(atom, same(source));
                      expect(page.dimensions[i], same(old.dimensions[i]));
                      continue;
                    }
                    final original =
                            source as ForumBodyRubyTreeEmphasisAtomPlan,
                        next = atom as ForumBodyRubyTreeEmphasisAtomPlan;
                    expect(next.request, same(original.request));
                    expect(
                      next.format.placement.input,
                      same(original.format.placement.input),
                    );
                    expect(
                      next.format.frame.size.width,
                      original.format.frame.size.width,
                    );
                    final root =
                            shift.original.input.contexts.first.physicalRow,
                        oldRow = shift.original.rowForId(root),
                        newRow = next.format.placement.rowForId(root);
                    expect(
                      newRow.overBaseline,
                      oldRow.overBaseline == null
                          ? null
                          : oldRow.overBaseline! + shift.over,
                    );
                    expect(
                      newRow.underBaseline,
                      oldRow.underBaseline == null
                          ? null
                          : oldRow.underBaseline! + shift.under,
                    );
                    expect(
                      next.format.placement.marks,
                      hasLength(original.format.placement.marks.length),
                    );
                    for (final (n, m) in next.format.placement.marks.indexed) {
                      final previous = original.format.placement.marks[n];
                      expect(m.source, same(previous.source));
                      expect(m.mark, same(previous.mark));
                      expect(m.fontOffset, previous.fontOffset);
                      final delta = m.row == root
                          ? (side == 'over' ? shift.over : shift.under)
                          : 0.0;
                      expect(
                        m.baselineOrigin,
                        previous.baselineOrigin + Offset(0, delta),
                      );
                    }
                  }
                  // Exercise the actual next native parent, not just equal
                  // dimensions: a vertical replan must preserve physical rows.
                  final parent = cache.acquireInline(
                    content: measured.glyphInput.glyphs,
                    width: width,
                    dimensions: page.dimensions,
                    textScaler: placement.input.fonts.textScaler,
                    layoutMode: page.layoutMode,
                  );
                  try {
                    expect(
                      parent.layout.lineCount,
                      measured.lease.layout.lineCount,
                    );
                    expect(
                      parent.layout.lines.map(_line),
                      measured.lease.layout.lines.map(_line),
                    );
                    for (final (i, atom)
                        in parent.layout.projection.atoms.indexed) {
                      expect(
                        parent.layout.isAtomTrimmed(i),
                        old.trimmedAtomIndices.contains(i),
                      );
                      final row = parent.layout.lines.indexWhere(
                        (l) =>
                            atom.engineUtf16 >= l.engineCoverageStartUtf16 &&
                            atom.engineUtf16 < l.engineCoverageEndUtf16,
                      );
                      expect(
                        row,
                        placement.input.fonts.geometry.atomLineIndices[i],
                      );
                      expect(
                        parent.layout.atomBoxes[i].left,
                        measured.lease.layout.atomBoxes[i].left,
                      );
                      expect(
                        parent.layout.atomBoxes[i].right,
                        measured.lease.layout.atomBoxes[i].right,
                      );
                      final child = page.rubyAtoms[i],
                          band = placement.input.children[i];
                      if (child is ForumBodyRubyTreeEmphasisAtomPlan &&
                          band != null) {
                        final outer = page.rootFonts[i]?.enclose(
                          childSize: child.format.frame.size,
                          childBaseline: child.format.frame.baseline,
                        );
                        final origin =
                            parent.layout.atomBoxes[i].toRect().topLeft +
                            (outer?.childOffset ?? Offset.zero) +
                            child.format.frame.childOffset;
                        final delta =
                            parent.layout.lines[row].baseline -
                            measured.lease.layout.lines[row].baseline;
                        expect(origin.dx, closeTo(band.glyphOrigin.dx, 1e-3));
                        expect(
                          origin.dy,
                          closeTo(band.glyphOrigin.dy + delta, 1e-3),
                        );
                      }
                    }
                  } finally {
                    parent.release();
                  }
                  expect(cache.activeLeases, 1);
                },
              );
            }
          }
        }
      }
    }
  }
  test(
    'every child writer and publication boundary retires without consuming the caller',
    () {
      final cache = _cache(),
          f = MixedEmphasisParentFixture(
            mixedEmphasisChildren[1],
            prefix:
                '<span style="font-size:120px;text-emphasis:none">W</span>P',
          );
      final measured = f.finish(f.open(cache), cache).value;
      addTearDown(measured.lease.release);
      final placement = _placement(f, measured, cache);
      expect(
        placement.childShifts.whereType<ForumBodyRubyRootEmphasisShift>(),
        isNotEmpty,
      );
      final parts = _finish(
        ForumBodyInlineEmphasisChildrenPlanPreparation(
          placement: placement,
          ensureOwner: () {},
        ),
      ).parts;
      for (var boundary = 0; boundary <= parts; boundary++) {
        var active = true;
        final work = ForumBodyInlineEmphasisChildrenPlanPreparation(
          placement: placement,
          ensureOwner: () {
            if (!active) throw StateError('Retired');
          },
        );
        for (var n = 0; n < boundary; n++) {
          work.advance(maxParts: 1);
        }
        active = false;
        expect(
          work.isReady ? work.takePlan : () => work.advance(maxParts: 1),
          throwsStateError,
        );
        work.close();
        expect(cache.activeLeases, 1);
      }
      expect(
        () => ForumBodyInlineEmphasisChildrenPlanPreparation(
          placement: placement,
          ensureOwner: () {},
          maxAtoms: 0,
        ),
        throwsA(
          isA<ForumBodyEmphasisGeometryException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyEmphasisGeometryFailure.limit,
          ),
        ),
      );
      for (final mode in [0, 1, 2]) {
        var armed = false;
        late ForumBodyInlineEmphasisChildrenPlanPreparation work;
        work = ForumBodyInlineEmphasisChildrenPlanPreparation(
          placement: placement,
          ensureOwner: () {
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
        expect(cache.activeLeases, 1);
      }
    },
  );
  test(
    'numeric child replan survives eviction while later visible binding owns actual glyphs and scene',
    () {
      final cache = _cache(),
          f = MixedEmphasisParentFixture(
            mixedEmphasisChildren[1],
            prefix:
                '<span style="font-size:120px;text-emphasis:none">W</span>P',
          );
      final measured = f.finish(f.open(cache), cache).value;
      final placement = _placement(f, measured, cache);
      measured.lease.release();
      cache.clearUnpinned();
      expect(cache.entryCount, 0);
      final before = (cache.layoutBuildCount, cache.pictureBuildCount);
      final result = _finish(
        ForumBodyInlineEmphasisChildrenPlanPreparation(
          placement: placement,
          ensureOwner: () {},
        ),
      ).plan;
      expect(result.hasChanges, isTrue);
      expect((cache.layoutBuildCount, cache.pictureBuildCount), before);
      for (final i in result.changedAtoms) {
        final atom =
            result.page.rubyAtoms[i] as ForumBodyRubyTreeEmphasisAtomPlan;
        final job = ForumBodyRubyTreeEmphasisScenePreparation(
          input: atom.request,
          plan: atom.format,
          cache: cache,
          ensureOwner: () {},
          width: atom.maxWidth,
          expectedTextScaler: TextScaler.noScaling,
        );
        late ForumBodyRubyTreeEmphasisLayout layout;
        try {
          for (var n = 0; !job.isReady; n++) {
            expect(n, lessThan(50000));
            final s = job.advance(maxParts: 1);
            expect(s.waitingForLayoutBudget, isFalse);
          }
          layout = job.takeLayout();
        } finally {
          job.close();
        }
        try {
          for (final mark in atom.format.placement.marks) {
            final hit = layout.sourceAt(
              mark.fontBounds.center + layout.contentOffset,
            );
            expect(hit.content, same(mark.source.source.source.content));
            expect(hit.position.isExact, isFalse);
          }
          final recorder = ui.PictureRecorder();
          try {
            layout.paint(Canvas(recorder), const Offset(3.2, 5.4));
          } finally {
            recorder.endRecording().dispose();
          }
        } finally {
          layout.close();
        }
        expect(cache.activeLeases, 0);
      }
    },
  );
}
