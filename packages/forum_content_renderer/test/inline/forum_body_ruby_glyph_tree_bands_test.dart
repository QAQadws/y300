import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_tree_input.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_tree_metrics_preparation.dart';

ForumBodyRubyGlyphTreeGeometry _geometry(
  String html,
  ForumBodyParagraphCache cache, {
  TextDirection direction = TextDirection.ltr,
  bool nonlinear = false,
}) {
  final doc = const ForumBodyParser().parse(
    html: html,
    sourceId: 'original-tree-bands',
    conversionIdentity: 'none',
  );
  final flow = ForumBodyTextFlowCursor(
    document: doc,
    reader: ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20),
      fontRevision: 'bands-ahem',
      linkColor: const Color(0xff0000ff),
      textDirection: direction,
    ),
  );
  ForumBodyRubyGroupContent? group;
  try {
    while (!flow.isComplete && group == null) {
      flow.advance(maxEvents: 1);
      if (flow.current case ForumBodyTextFlowInline(:final content)) {
        group = content.parts.whereType<ForumBodyInlineFlowRuby>().first.group;
      }
    }
  } finally {
    flow.close();
  }
  final source = ForumBodyRubyGlyphTreeInputPreparation(
    group: group!,
    maxWidth: 500,
    ensureOwner: () {},
  );
  while (!source.isReady) {
    source.advance(maxParts: 1);
  }
  final input = source.takeInput();
  source.close();
  final measure = ForumBodyRubyGlyphTreeMetricsPreparation(
    input: input,
    cache: cache,
    ensureOwner: () {},
    textScaler: nonlinear ? const _Scaler() : TextScaler.noScaling,
  );
  while (!measure.isReady) {
    final step = measure.advance(maxParts: 1);
    expect(step.waitingForLayoutBudget, isFalse);
    expect(step.picturesBuilt, 0);
  }
  final metrics = measure.takeMetrics();
  measure.close();
  final positions = ForumBodyRubyGlyphTreeGeometryPreparation(
    metrics: metrics,
    ensureOwner: () {},
  );
  while (!positions.isReady) {
    positions.advance(maxParts: 1);
  }
  final result = positions.takeGeometry();
  positions.close();
  return result;
}

final class _Scaler extends TextScaler {
  const _Scaler();
  @override
  double scale(double size) => size < 15 ? size * 1.4 : size * 1.1;
  @override
  double get textScaleFactor => throw StateError('Actual sizes only');
}

ForumBodyRubyGlyphTreeBands _finish(
  ForumBodyRubyGlyphTreeBandsPreparation work,
) {
  try {
    var parts = 0;
    while (!work.isReady) {
      expect(work.advance(maxParts: 1), 1);
      expect(++parts, lessThan(10000));
    }
    final result = work.takeBands();
    expect(work.takeBands, throwsStateError);
    return result;
  } finally {
    work.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ForumBodyParagraphCache cache;
  setUp(
    () => cache = ForumBodyParagraphCache(
      maxEntries: 64,
      maxEstimatedBytes: 1 << 24,
    ),
  );
  tearDown(() => cache.close());
  for (final nestedRT in [false, true]) {
    for (final outer in ForumBodyRubySide.values) {
      for (final inner in ForumBodyRubySide.values) {
        for (final direction in TextDirection.values) {
          for (final nonlinear in [false, true]) {
            test('actual base-branch limits RT=$nestedRT $outer/$inner '
                '$direction nonlinear=$nonlinear', () {
              final child =
                  '<ruby style="ruby-position:${inner.name}"><rb>A</rb><rt>x</rt></ruby>';
              final html = nestedRT
                  ? '<ruby style="ruby-position:${outer.name};line-height:.4"><rb>B</rb><rt>$child</rt></ruby>'
                  : '<ruby style="ruby-position:${outer.name};line-height:.4;text-emphasis:circle"><rb>$child</rb><rt>y</rt></ruby>';
              final geometry = _geometry(
                html,
                cache,
                direction: direction,
                nonlinear: nonlinear,
              );
              final before = (
                cache.layoutBuildCount,
                cache.pictureBuildCount,
                cache.hitCount,
                cache.activeLeases,
              );
              final bands = _finish(
                ForumBodyRubyGlyphTreeBandsPreparation(
                  geometry: geometry,
                  ensureOwner: () {},
                ),
              );
              final root = bands.contexts.first;
              final innerNode = geometry.nodes.singleWhere(
                (p) =>
                    p.id != root.position.id &&
                    geometry.metrics.input.sourceTree.nodes[p.id]
                        is ForumBodyRubyTreeGroup,
              );
              final inside = bands.nodeForId(innerNode.id);
              expect(root.localBands, hasLength(1));
              expect(inside.localBands, hasLength(1));
              final outerBand = root.localBands.single,
                  innerBand = inside.localBands.single;
              expect(outerBand.side, outer);
              expect(innerBand.side, inner);
              expect(outerBand.hasMeasuredAnnotation, isTrue);
              expect(innerBand.isReserved, isTrue);
              for (final context in [root, inside]) {
                final actual =
                    (geometry.metrics.nodes[context.position.id]
                            as ForumBodyRubyTreeContainerMetrics)
                        .group!
                        .annotations
                        .single;
                expect(
                  context.localBands.single.top,
                  context.position.contentOrigin.dy + actual.bandTop,
                );
                expect(
                  context.localBands.single.bottom,
                  context.position.contentOrigin.dy + actual.bandBottom,
                );
              }
              ForumBodyRubyGlyphTreeBandContext source(String text) =>
                  bands.sourceForId(
                    geometry.sources
                        .singleWhere(
                          (p) => p.source.content.projection.text == text,
                        )
                        .source
                        .id,
                  );
              (double?, double?) limits(
                Iterable<ForumBodyRubyGlyphTreeBand> rows,
              ) {
                final over = rows
                    .where((r) => r.side == ForumBodyRubySide.over)
                    .map((r) => r.top)
                    .toList();
                final under = rows
                    .where((r) => r.side == ForumBodyRubySide.under)
                    .map((r) => r.bottom)
                    .toList();
                return (
                  over.isEmpty ? null : over.reduce(math.min),
                  under.isEmpty ? null : under.reduce(math.max),
                );
              }

              void check(
                ForumBodyRubyGlyphTreeBandContext context,
                Iterable<ForumBodyRubyGlyphTreeBand> rows,
              ) {
                expect((
                  context.baseAncestorOverEdge,
                  context.baseAncestorUnderEdge,
                ), limits(rows));
              }

              check(source('A'), [if (!nestedRT) outerBand, innerBand]);
              check(source('x'), [if (!nestedRT) outerBand]);
              check(source(nestedRT ? 'B' : 'y'), nestedRT ? [outerBand] : []);
              expect(bands.geometry, same(geometry));
              expect(
                bands.contexts.map((c) => c.position),
                orderedEquals(geometry.nodes),
              );
              expect((
                cache.layoutBuildCount,
                cache.pictureBuildCount,
                cache.hitCount,
                cache.activeLeases,
              ), before);
              expect(() => root.localBands.clear(), throwsUnsupportedError);
              expect(() => bands.contexts.clear(), throwsUnsupportedError);
            });
          }
        }
      }
    }
  }
  for (final direction in TextDirection.values) {
    test(
      'spanning rows and both kinds of spaces keep their real role $direction',
      () {
        final geometry = _geometry(
          '<ruby><rb>A</rb> <rb>B</rb><rtc><rt rbspan="2">wide</rt></rtc>'
          '<rtc style="ruby-position:under"><rt>a</rt> <rt>b</rt></rtc></ruby>',
          cache,
          direction: direction,
        );
        final bands = _finish(
          ForumBodyRubyGlyphTreeBandsPreparation(
            geometry: geometry,
            ensureOwner: () {},
          ),
        );
        final root = bands.contexts.first;
        expect(root.localBands, hasLength(2));
        expect(
          root.localBands.every((b) => b.hasMeasuredAnnotation && b.isReserved),
          isTrue,
        );
        expect(root.localOverEdge, isNotNull);
        expect(root.localUnderEdge, isNotNull);
        final segment = geometry.metrics.root.segment!;
        expect(
          segment.columns.first.annotations.every((a) => !a.hasAnnotation),
          isTrue,
        );
        var bases = 0, annotationSpaces = 0;
        for (final source in geometry.sources) {
          final context = bands.sourceForId(source.source.id);
          final branch = source.node.edge!.branch;
          if (branch == ForumBodyRubyTreeBranch.base ||
              branch == ForumBodyRubyTreeBranch.gap) {
            expect(context.baseAncestorOverEdge, root.localOverEdge);
            expect(context.baseAncestorUnderEdge, root.localUnderEdge);
            bases++;
          } else {
            expect(context.baseAncestorOverEdge, isNull);
            expect(context.baseAncestorUnderEdge, isNull);
            if (branch == ForumBodyRubyTreeBranch.annotationGap) {
              annotationSpaces++;
            }
          }
        }
        expect(bases, 3);
        expect(annotationSpaces, 1);
      },
    );
  }
  test(
    'empty local RT uses the real shared row without an independent font leaf',
    () {
      final geometry = _geometry(
        '<ruby><rb>A</rb><rb>B</rb><rt></rt><rt>tone</rt></ruby>',
        cache,
      );
      final bands = _finish(
        ForumBodyRubyGlyphTreeBandsPreparation(
          geometry: geometry,
          ensureOwner: () {},
        ),
      );
      final root = bands.contexts.first;
      expect(root.localBands.single.isReserved, isTrue);
      expect(root.localBands.single.hasMeasuredAnnotation, isTrue);
      final empty = geometry.sources.singleWhere(
        (s) => s.source.content.projection.text.isEmpty,
      );
      expect(empty.source.needsNative, isFalse);
      expect(bands.sourceForId(empty.source.id).baseAncestorOverEdge, isNull);
      final a = geometry.sources.firstWhere(
        (s) => s.source.content.projection.text == 'A',
      );
      expect(
        bands.sourceForId(a.source.id).baseAncestorOverEdge,
        root.localOverEdge,
      );
      expect(cache.activeLeases, 0);
    },
  );
  test(
    'unreserved empty RT stays explicit and cannot imply complete font reservation',
    () {
      final geometry = _geometry(
        '<ruby style="text-emphasis:circle"><rb>A</rb><rt> </rt></ruby>',
        cache,
      );
      final bands = _finish(
        ForumBodyRubyGlyphTreeBandsPreparation(
          geometry: geometry,
          ensureOwner: () {},
        ),
      );
      final root = bands.contexts.first;
      expect(root.localBands, hasLength(1));
      expect(root.localBands.single.hasMeasuredAnnotation, isFalse);
      expect(root.localBands.single.isReserved, isFalse);
      expect(root.localOverEdge, isNull);
      final empty = geometry.sources.last;
      expect(empty.source.content.projection.text, isEmpty);
      expect(bands.sourceForId(empty.source.id).position, same(empty.node));
      cache.close();
      expect(bands.geometry.sources.last.source, same(empty.source));
      expect(root.localBands.single.top, root.localBands.single.bottom);
    },
  );
  test(
    'opaque inline sources retain only their actual tree parent context',
    () {
      final geometry = _geometry(
        '<ruby><rb>L<ruby>A<rt>x</rt></ruby>R</rb><rt>y</rt></ruby>',
        cache,
      );
      final bands = _finish(
        ForumBodyRubyGlyphTreeBandsPreparation(
          geometry: geometry,
          ensureOwner: () {},
        ),
      );
      final contexts = geometry.sources
          .where((s) => s.usesInlineParent)
          .toList();
      expect(contexts, isNotEmpty);
      final first = bands.sourceForId(contexts.first.source.id);
      for (final source in contexts) {
        expect(bands.sourceForId(source.source.id), same(first));
        expect(first.position, same(source.node));
      }
      expect(first.baseAncestorOverEdge, bands.contexts.first.localOverEdge);
      expect(first.localBands, isEmpty);
    },
  );
  test('deep bands reuse parent summaries with linear measured-row work', () {
    var html = 'A';
    for (var depth = 0; depth < 18; depth++) {
      final side = depth.isEven ? 'over' : 'under';
      html =
          '<ruby style="ruby-position:$side"><rb>$html</rb><rt>x$depth</rt></ruby>';
    }
    final geometry = _geometry(html, cache);
    final work = ForumBodyRubyGlyphTreeBandsPreparation(
      geometry: geometry,
      ensureOwner: () {},
    );
    var parts = 0;
    while (!work.isReady) {
      expect(work.advance(maxParts: 1), 1);
      parts++;
    }
    final bands = work.takeBands();
    work.close();
    final rows = bands.contexts.expand((c) => c.localBands).toList();
    expect(rows, hasLength(18));
    expect(
      parts,
      lessThanOrEqualTo(3 * geometry.nodes.length + rows.length + 4),
    );
    final base = geometry.sources.singleWhere(
      (s) => s.source.content.projection.text == 'A',
    );
    final context = bands.sourceForId(base.source.id);
    expect(
      context.baseAncestorOverEdge,
      rows
          .where((r) => r.side == ForumBodyRubySide.over)
          .map((r) => r.top)
          .reduce(math.min),
    );
    expect(
      context.baseAncestorUnderEdge,
      rows
          .where((r) => r.side == ForumBodyRubySide.under)
          .map((r) => r.bottom)
          .reduce(math.max),
    );
    expect(cache.activeLeases, 0);
    expect(cache.pictureBuildCount, 0);
  });
  test(
    'each work boundary and publication reject retirement; caught reentry preserves work',
    () {
      final geometry = _geometry(
        '<ruby><rb><ruby>A<rt>x</rt></ruby></rb><rt>y</rt></ruby>',
        cache,
      );
      var parts = 0;
      final count = ForumBodyRubyGlyphTreeBandsPreparation(
        geometry: geometry,
        ensureOwner: () {},
      );
      while (!count.isReady) {
        parts += count.advance(maxParts: 1);
      }
      count.close();
      for (var stop = 0; stop <= parts; stop++) {
        var active = true;
        final work = ForumBodyRubyGlyphTreeBandsPreparation(
          geometry: geometry,
          ensureOwner: () {
            if (!active) throw StateError('retired');
          },
        );
        for (var i = 0; i < stop; i++) {
          work.advance(maxParts: 1);
        }
        active = false;
        expect(work.advance, throwsStateError);
        expect(work.takeBands, throwsStateError);
        work.close();
        work.close();
      }
      ForumBodyRubyGlyphTreeBandsPreparation? reentry;
      reentry = ForumBodyRubyGlyphTreeBandsPreparation(
        geometry: geometry,
        ensureOwner: () {
          if (reentry == null) return;
          expect(reentry.advance, throwsStateError);
          expect(reentry.takeBands, throwsStateError);
        },
      );
      expect(_finish(reentry).contexts, hasLength(geometry.nodes.length));
      ForumBodyRubyGlyphTreeBandsPreparation? publication;
      publication = ForumBodyRubyGlyphTreeBandsPreparation(
        geometry: geometry,
        ensureOwner: () {
          if (publication?.isReady == true) publication!.close();
        },
      );
      expect(() => publication!.advance(maxParts: 10000), throwsStateError);
      expect(publication.takeBands, throwsStateError);
      expect(cache.activeLeases, 0);
      expect(cache.pictureBuildCount, 0);
    },
  );
}
