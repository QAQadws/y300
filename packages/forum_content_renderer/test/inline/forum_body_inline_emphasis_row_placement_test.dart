import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_emphasis_parent_fixture.dart';

ForumBodyParagraphCache _cache() {
  final value = ForumBodyParagraphCache(
    maxEntries: 512,
    maxEstimatedBytes: 1 << 26,
  );
  addTearDown(value.close);
  return value;
}

({ForumBodyInlineEmphasisRowPlacement value, int parts}) _finish(
  ForumBodyInlineEmphasisRowPlacementPreparation job, {
  int quantum = 1,
}) {
  var parts = 0;
  try {
    for (var n = 0; !job.isReady; n++) {
      expect(n, lessThan(50000));
      final used = job.advance(maxParts: quantum);
      expect(used, inInclusiveRange(1, quantum));
      parts += used;
    }
    expect(job.advance(maxParts: 1), 0);
    return (value: job.takePlacement(), parts: parts);
  } finally {
    job.close();
  }
}

List<Object?> _values(ForumBodyInlineEmphasisRowPlacement value) => [
  for (final r in value.rows)
    [
      r.lineIndex,
      r.baseTop,
      r.baseBottom,
      r.overEdge,
      r.underEdge,
      r.overBaseline,
      r.underBaseline,
    ],
  for (final m in value.marks)
    [
      m.unitIndex,
      m.fontIndex,
      m.lineIndex,
      m.baselineOrigin,
      m.fontOffset,
      m.fontBounds,
    ],
  for (final s in value.childShifts)
    s == null ? null : [s.original, s.over, s.under],
];
ForumBodyRubyTreeEmphasisPlan _replan(
  ForumBodyRubyRootEmphasisShift shift, {
  int quantum = 1,
}) {
  final job = ForumBodyRubyTreeEmphasisPlacementPreparation(
    input: shift.original.input,
    rootShift: shift,
    ensureOwner: () {},
  );
  late ForumBodyRubyTreeEmphasisPlacement p;
  try {
    while (!job.isReady) {
      expect(job.advance(maxParts: quantum), inInclusiveRange(1, quantum));
    }
    p = job.takePlacement();
  } finally {
    job.close();
  }
  final plan = ForumBodyRubyTreeEmphasisPlanPreparation(
    placement: p,
    ensureOwner: () {},
  );
  try {
    while (!plan.isReady) {
      plan.advance(maxParts: quantum);
    }
    return plan.takePlan();
  } finally {
    plan.close();
  }
}

ForumBodyRubyTreeEmphasisLayout _scene(
  ForumBodyRubyTreeEmphasisAtomPlan atom,
  ForumBodyRubyTreeEmphasisPlan plan,
  ForumBodyParagraphCache cache,
  Iterable<ForumBodyNativeParagraphLease> Function() prefix,
) {
  final job = ForumBodyRubyTreeEmphasisScenePreparation(
    input: atom.request,
    plan: plan,
    cache: cache,
    ensureOwner: () {},
    width: atom.maxWidth,
    expectedTextScaler: TextScaler.noScaling,
    additionalOwnedLeases: prefix,
  );
  try {
    for (var n = 0; !job.isReady; n++) {
      expect(n, lessThan(30000));
      final s = job.advance(maxParts: 1);
      expect(s.waitingForLayoutBudget, isFalse);
    }
    return job.takeLayout();
  } finally {
    job.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final side in ['over', 'under']) {
    for (final direction in TextDirection.values) {
      for (final scaler in [TextScaler.noScaling, const MixedEmphasisCurve()]) {
        for (final width in [70.0, 300.0]) {
          for (final (fixture, html) in mixedEmphasisChildren.indexed) {
            test(
              'common actual root rows $fixture $side/$direction/$scaler/$width',
              () {
                final f = MixedEmphasisParentFixture(
                      html,
                      direction: direction,
                      width: width,
                      parentStyle:
                          'text-emphasis:circle;text-emphasis-position:$side;line-height:.4',
                    ),
                    cache = _cache();
                final measured = f
                    .finish(f.open(cache, scaler: scaler), cache)
                    .value;
                addTearDown(measured.lease.release);
                final bands = f.bands(measured, cache, scaler: scaler);
                final before = (
                  cache.layoutBuildCount,
                  cache.pictureBuildCount,
                  cache.hitCount,
                  cache.activeLeases,
                );
                final result = _finish(
                  ForumBodyInlineEmphasisRowPlacementPreparation(
                    input: bands,
                    ensureOwner: () {},
                  ),
                ).value;
                final batch = _finish(
                  ForumBodyInlineEmphasisRowPlacementPreparation(
                    input: bands,
                    ensureOwner: () {},
                  ),
                  quantum: 7,
                ).value;
                expect(_values(result), _values(batch));
                expect(result.input, same(bands));
                expect(result.rows, hasLength(measured.lease.layout.lineCount));
                expect(
                  result.marks,
                  hasLength(bands.fonts.geometry.targets.length),
                );
                final upper = <int, List<double>>{},
                    lower = <int, List<double>>{};
                void constraint(
                  int row,
                  double ascent,
                  double descent,
                  ForumBodyEmphasisSide side,
                ) {
                  final r = result.rows[row];
                  if (side == ForumBodyEmphasisSide.over) {
                    (upper[row] ??= []).add(r.baseTop! - descent);
                    if (r.overEdge != null) {
                      upper[row]!.add(r.overEdge! - descent);
                    }
                  } else {
                    (lower[row] ??= []).add(r.baseBottom! + ascent);
                    if (r.underEdge != null) {
                      lower[row]!.add(r.underEdge! + ascent);
                    }
                  }
                }

                for (final (i, target)
                    in bands.fonts.geometry.targets.indexed) {
                  final font = bands.fonts.fontForUnit(i),
                      mark = result.marks[i];
                  final side = f
                      .text
                      .content
                      .runs[target.unit.runIndex]
                      .style
                      .textEmphasis
                      .side;
                  constraint(
                    target.lineIndex,
                    font.alphabeticBaseline - font.fontBounds.top,
                    font.fontBounds.bottom - font.alphabeticBaseline,
                    side,
                  );
                  expect(mark.unitIndex, i);
                  expect(mark.lineIndex, target.lineIndex);
                  expect(
                    mark.fontBounds.center.dx,
                    closeTo(target.governingFontBounds.center.dx, 1e-9),
                  );
                  expect(
                    mark.baselineOrigin.dy,
                    side == ForumBodyEmphasisSide.over
                        ? result.rows[target.lineIndex].overBaseline
                        : result.rows[target.lineIndex].underBaseline,
                  );
                }
                for (final child in bands.children) {
                  if (child == null) continue;
                  if (child.source case ForumBodyRubyTreeEmphasisAtomPlan(
                    :final format,
                  )) {
                    final root =
                        format.placement.input.contexts.first.physicalRow;
                    for (final m in format.placement.marks.where(
                      (m) => m.row == root,
                    )) {
                      final line = m.source.line, mark = m.mark;
                      constraint(
                        child.lineIndex,
                        mark.scaledAlphabeticBaseline -
                            mark.scaledFontBounds.top,
                        mark.scaledFontBounds.bottom -
                            mark.scaledAlphabeticBaseline,
                        line
                            .input
                            .content
                            .runs[line.input.units[mark.unitIndex].runIndex]
                            .style
                            .textEmphasis
                            .side,
                      );
                    }
                    if (child.overBaseline != null) {
                      (upper[child.lineIndex] ??= []).add(child.overBaseline!);
                    }
                    if (child.underBaseline != null) {
                      (lower[child.lineIndex] ??= []).add(child.underBaseline!);
                    }
                  }
                }
                for (final r in result.rows) {
                  expect(r.overBaseline, upper[r.lineIndex]?.reduce(math.min));
                  expect(r.underBaseline, lower[r.lineIndex]?.reduce(math.max));
                }
                for (final (i, shift) in result.childShifts.indexed) {
                  if (shift == null) continue;
                  final child = bands.children[i]!;
                  expect(shift.over, lessThanOrEqualTo(0));
                  expect(shift.under, greaterThanOrEqualTo(0));
                  final updated = _replan(shift);
                  expect(updated.placement.input, same(shift.original.input));
                  final root = updated.placement.rowForId(
                    updated.placement.input.contexts.first.physicalRow,
                  );
                  if (child.overBaseline != null) {
                    expect(
                      child.overBaseline! + shift.over,
                      result.rows[child.lineIndex].overBaseline,
                    );
                  }
                  if (child.underBaseline != null) {
                    expect(
                      child.underBaseline! + shift.under,
                      result.rows[child.lineIndex].underBaseline,
                    );
                  }
                  expect(
                    root.overAnnotationMarkerBounds,
                    shift.original.rowForId(root.id).overAnnotationMarkerBounds,
                  );
                  expect(
                    root.underAnnotationMarkerBounds,
                    shift.original
                        .rowForId(root.id)
                        .underAnnotationMarkerBounds,
                  );
                }
                expect((
                  cache.layoutBuildCount,
                  cache.pictureBuildCount,
                  cache.hitCount,
                  cache.activeLeases,
                ), before);
                expect(() => result.rows.clear(), throwsUnsupportedError);
                expect(() => result.marks.clear(), throwsUnsupportedError);
                expect(
                  () => result.childShifts.clear(),
                  throwsUnsupportedError,
                );
                measured.lease.release();
                cache.clearUnpinned();
                expect(cache.activeLeases, 0);
                expect(_values(result), _values(batch));
              },
            );
          }
        }
      }
    }
  }
  for (final side in ['over', 'under']) {
    test(
      'actual child replan shifts only root marks and preserves visible source $side',
      () {
        final f = MixedEmphasisParentFixture(
              '<ruby style="ruby-position:$side">A<rt style="text-emphasis:triangle;text-emphasis-position:$side">x</rt></ruby>',
              parentStyle:
                  'text-emphasis:circle;text-emphasis-position:$side;line-height:.4',
              prefix:
                  '<span style="font-size:120px;text-emphasis:none">W</span>P',
            ),
            cache = _cache();
        final measured = f.finish(f.open(cache), cache).value;
        addTearDown(measured.lease.release);
        final bands = f.bands(measured, cache);
        final result = _finish(
          ForumBodyInlineEmphasisRowPlacementPreparation(
            input: bands,
            ensureOwner: () {},
          ),
        ).value;
        final shift = result.childShifts.single!;
        expect(
          side == 'over' ? shift.over : shift.under,
          side == 'over' ? lessThan(0) : greaterThan(0),
        );
        final atom =
            measured.plan.rubyAtoms.single as ForumBodyRubyTreeEmphasisAtomPlan;
        final plan = _replan(shift),
            root = shift.original.input.contexts.first.physicalRow;
        expect(plan.frame.size.width, atom.format.frame.size.width);
        expect(plan.placement.marks, hasLength(shift.original.marks.length));
        for (final (i, m) in plan.placement.marks.indexed) {
          final old = shift.original.marks[i];
          expect(m.source, same(old.source));
          expect(m.mark, same(old.mark));
          expect(m.fontOffset, old.fontOffset);
          final delta = m.row == root
              ? (side == 'over' ? shift.over : shift.under)
              : 0.0;
          expect(m.baselineOrigin, old.baselineOrigin + Offset(0, delta));
          expect(m.fontBounds.top, closeTo(old.fontBounds.top + delta, 1e-9));
        }
        final second = _replan(
          ForumBodyRubyRootEmphasisShift(
            original: plan.placement,
            over: side == 'over' ? -3.25 : 0,
            under: side == 'under' ? 3.25 : 0,
          ),
        );
        final firstRoot = plan.placement.rowForId(root),
            secondRoot = second.placement.rowForId(root);
        expect(
          secondRoot.overBaseline,
          firstRoot.overBaseline == null
              ? null
              : firstRoot.overBaseline! + (side == 'over' ? -3.25 : 0),
        );
        expect(
          secondRoot.underBaseline,
          firstRoot.underBaseline == null
              ? null
              : firstRoot.underBaseline! + (side == 'under' ? 3.25 : 0),
        );
        final oldLayout = _scene(
          atom,
          atom.format,
          cache,
          () => [measured.lease],
        );
        try {
          final layout = _scene(
            atom,
            second,
            cache,
            () => [measured.lease, ...oldLayout.nativeLeases],
          );
          try {
            for (final m in second.placement.marks) {
              final hit = layout.sourceAt(
                m.fontBounds.center + layout.contentOffset,
              );
              expect(hit.content, same(m.source.source.source.content));
              expect(hit.position.isExact, isFalse);
            }
            for (final source in layout.sources) {
              final id = source.source.id,
                  length = source.source.content.projection.text.length;
              final original = oldLayout.selectionBoxes(
                sourceId: id,
                startUtf16: 0,
                endUtf16: length,
              );
              final current = layout.selectionBoxes(
                sourceId: id,
                startUtf16: 0,
                endUtf16: length,
              );
              expect(
                current.map((b) => b.toRect().shift(-layout.contentOffset)),
                original.map((b) => b.toRect().shift(-oldLayout.contentOffset)),
              );
            }
            final recorder = ui.PictureRecorder();
            layout.paint(Canvas(recorder), const Offset(3.2, 5.4));
            recorder.endRecording().dispose();
          } finally {
            layout.close();
          }
        } finally {
          oldLayout.close();
        }
        expect(cache.activeLeases, 1);
      },
    );
  }
  test(
    'whole styled source unit keeps its actual later governing row and center',
    () {
      final f = MixedEmphasisParentFixture(
            '<ruby style="font-size:1px;text-emphasis:none">A<rt>x</rt></ruby>',
            width: 5,
            prefix: '<span style="font-size:31px">؀</span>A',
            suffix: '',
          ),
          cache = _cache();
      final measured = f.finish(f.open(cache), cache).value;
      addTearDown(measured.lease.release);
      final bands = f.bands(measured, cache),
          target = bands.fonts.geometry.targets.single;
      expect(target.lineIndex, greaterThan(target.sourceStartLine));
      final mark = _finish(
        ForumBodyInlineEmphasisRowPlacementPreparation(
          input: bands,
          ensureOwner: () {},
        ),
      ).value.marks.single;
      expect(mark.unitIndex, 0);
      expect(mark.lineIndex, target.lineIndex);
      expect(mark.fontBounds.center.dx, target.governingFontBounds.center.dx);
      expect(target.unit, same(f.text.units.single));
    },
  );
  test(
    'no eligible targets produce no invented baseline or shift with zero budget',
    () {
      final f = MixedEmphasisParentFixture(
            mixedEmphasisChildren[0],
            parentStyle: 'line-height:.4',
          ),
          cache = _cache();
      final measured = f.finish(f.open(cache), cache).value;
      addTearDown(measured.lease.release);
      final bands = f.bands(measured, cache),
          result = _finish(
            ForumBodyInlineEmphasisRowPlacementPreparation(
              input: bands,
              ensureOwner: () {},
              maxInspectedMarks: 0,
            ),
          ).value;
      expect(result.marks, isEmpty);
      expect(result.childShifts, everyElement(isNull));
      expect(
        result.rows.every(
          (r) => r.overBaseline == null && r.underBaseline == null,
        ),
        isTrue,
      );
    },
  );
  test(
    'limit, reentry and every work/ready boundary retire pure work without caller release',
    () {
      final f = MixedEmphasisParentFixture(mixedEmphasisChildren[1]),
          cache = _cache();
      final measured = f.finish(f.open(cache), cache).value;
      addTearDown(measured.lease.release);
      final bands = f.bands(measured, cache);
      expect(
        () => _finish(
          ForumBodyInlineEmphasisRowPlacementPreparation(
            input: bands,
            ensureOwner: () {},
            maxInspectedMarks: 0,
          ),
        ),
        throwsA(
          isA<ForumBodyEmphasisGeometryException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyEmphasisGeometryFailure.limit,
          ),
        ),
      );
      final parts = _finish(
        ForumBodyInlineEmphasisRowPlacementPreparation(
          input: bands,
          ensureOwner: () {},
        ),
      ).parts;
      for (var boundary = 0; boundary <= parts; boundary++) {
        var active = true;
        final work = ForumBodyInlineEmphasisRowPlacementPreparation(
          input: bands,
          ensureOwner: () {
            if (!active) throw StateError('Retired');
          },
        );
        for (var n = 0; n < boundary; n++) {
          work.advance(maxParts: 1);
        }
        active = false;
        expect(
          work.isReady ? work.takePlacement : () => work.advance(maxParts: 1),
          throwsStateError,
        );
        expect(work.isReady, isFalse);
        work.close();
        expect(cache.activeLeases, 1);
      }
      for (final mode in [0, 1, 2]) {
        var armed = false;
        late ForumBodyInlineEmphasisRowPlacementPreparation work;
        work = ForumBodyInlineEmphasisRowPlacementPreparation(
          input: bands,
          ensureOwner: () {
            if (!armed) return;
            if (mode == 0 || mode == 2 && work.isReady) {
              work.close();
            } else if (mode == 1) {
              work.advance(maxParts: 1);
            }
          },
        );
        armed = true;
        expect(() => _finish(work), throwsStateError);
        expect(cache.activeLeases, 1);
      }
    },
  );
  test(
    'root constraints reject inward, invented-side and foreign-source movement',
    () {
      final f = MixedEmphasisParentFixture(mixedEmphasisChildren[1]),
          cache = _cache();
      final measured = f.finish(f.open(cache), cache).value;
      addTearDown(measured.lease.release);
      final original =
          (measured.plan.rubyAtoms.single as ForumBodyRubyTreeEmphasisAtomPlan)
              .format
              .placement;
      for (final over in [1.0, double.nan, double.infinity, -16385.0]) {
        expect(
          () => ForumBodyRubyRootEmphasisShift(original: original, over: over),
          throwsArgumentError,
        );
      }
      expect(
        () => ForumBodyRubyRootEmphasisShift(original: original, under: 1),
        throwsArgumentError,
      );
      final foreign = MixedEmphasisParentFixture(mixedEmphasisChildren[1]),
          other = foreign.finish(foreign.open(cache), cache).value;
      addTearDown(other.lease.release);
      final second =
          (other.plan.rubyAtoms.single as ForumBodyRubyTreeEmphasisAtomPlan)
              .format
              .placement;
      expect(
        () => ForumBodyRubyTreeEmphasisPlacementPreparation(
          input: second.input,
          rootShift: ForumBodyRubyRootEmphasisShift(
            original: original,
            over: -1,
          ),
          ensureOwner: () {},
        ),
        throwsA(isA<ForumBodyEmphasisLineException>()),
      );
      expect(cache.activeLeases, 2);
    },
  );
}
