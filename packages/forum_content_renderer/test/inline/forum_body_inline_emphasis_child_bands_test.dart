import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_preparation.dart';

const _fixtures = [
  '<ruby>A<rt>x</rt></ruby>',
  '<ruby><rb>A</rb><rb>B</rb><rtc><rt>x</rt></rtc><rtc>word</rtc></ruby>',
  '<ruby style="font-size:44px"><ruby>A<rt>x</rt></ruby><rt>y</rt></ruby>',
  '<ruby style="text-emphasis:circle">A<rt style="text-emphasis:triangle">x</rt></ruby>',
  '<ruby style="ruby-position:under;text-emphasis:circle;text-emphasis-position:under">A<rt style="text-emphasis:triangle;text-emphasis-position:under">x</rt></ruby>',
  '<ruby style="text-emphasis:circle">A<rt></rt></ruby>',
  '<ruby style="font-size:60px;line-height:3"><span style="font-size:12px;line-height:1">A</span><rt style="font-size:7px;line-height:1">x</rt></ruby>',
  '<ruby><rb>A</rb> <rb>B</rb><rtc><rt>x</rt> <rt>y</rt></rtc></ruby>',
  '<ruby style="font-size:12px"><rb>L<ruby>A<rt>x</rt></ruby>R</rb><rt style="text-emphasis:circle">z</rt></ruby>',
  '<ruby style="font-size:12px;text-emphasis:circle"><rb><ruby><rb>A</rb><rt style="font-size:18px"></rt></ruby></rb><rt style="text-emphasis:triangle">x</rt></ruby>',
];

final class _Curve extends TextScaler {
  const _Curve();
  @override
  double scale(double size) => size * (size < 25 ? 1.4 : 1.1);
  @override
  double get textScaleFactor => throw StateError('Use real sizes');
}

typedef _Fixture = ({
  ForumBodyParagraphCache cache,
  ForumBodyInlinePageContent page,
  ForumBodyInlineParagraphLease parent,
  ForumBodyInlineEmphasisFontMetrics fonts,
});
_Fixture _fixture(
  String html, {
  TextDirection direction = TextDirection.ltr,
  TextScaler scaler = TextScaler.noScaling,
  double width = 300,
}) {
  final cache = ForumBodyParagraphCache(
    maxEntries: 512,
    maxEstimatedBytes: 1 << 26,
  );
  addTearDown(cache.close);
  final doc = const ForumBodyParser().parse(
    html: '<p dir="${direction.name}" style="line-height:.4">P $html Q</p>',
    sourceId: 'child-bands',
    conversionIdentity: 'none',
  );
  final flow = ForumBodyTextFlowCursor(
    document: doc,
    reader: ForumBodyReaderStyle(
      textStyle: const TextStyle(
        fontFamily: 'Ahem',
        fontSize: 20,
        color: Color(0xff123456),
      ),
      fontRevision: 'child-bands',
      linkColor: const Color(0xff0000ff),
      textDirection: direction,
    ),
  );
  ForumBodyInlineFlowContent? content;
  try {
    while (!flow.isComplete) {
      flow.advance(maxEvents: 1);
      if (flow.current case ForumBodyTextFlowInline(content: final value)) {
        content = value;
        break;
      }
    }
  } finally {
    flow.close();
  }
  final plan = ForumBodyInlinePlanPreparation.fromFlow(
    input: content!,
    width: width,
    cache: cache,
    textScaler: scaler,
    ensureOwner: () {},
  );
  late ForumBodyInlinePageContent page;
  late ForumBodyInlineParagraphLease parent;
  try {
    for (var n = 0; !plan.isReady; n++) {
      expect(n, lessThan(30000));
      final step = plan.advance(maxParts: 1);
      expect(step.partsPrepared, 1);
      expect(step.waitingForLayoutBudget, isFalse);
    }
    final ready = plan.take();
    page = ready.content;
    parent = ready.lease;
  } finally {
    plan.close();
  }
  addTearDown(parent.release);
  final text = ForumBodyInlineEmphasisTextPreparation(
    content: page.content,
    ensureOwner: () {},
  );
  late ForumBodyInlineEmphasisTextInput input;
  try {
    while (!text.isReady) {
      text.advance(maxParts: 1);
    }
    input = text.takeInput();
  } finally {
    text.close();
  }
  expect(input.glyphInput.glyphs, same(page.content));
  final geometry = ForumBodyInlineEmphasisGeometryPreparation(
    input: input,
    parent: parent,
    ensureOwner: () {},
  );
  late ForumBodyInlineEmphasisTextGeometry g;
  try {
    while (!geometry.isReady) {
      geometry.advance(maxParts: 1);
    }
    g = geometry.takeGeometry();
  } finally {
    geometry.close();
  }
  final fonts = ForumBodyInlineEmphasisFontPreparation(
    geometry: g,
    parentRequest: page.parentRequest,
    parent: parent,
    cache: cache,
    ensureOwner: () {},
    expectedTextScaler: scaler,
    width: width,
  );
  try {
    while (!fonts.isReady) {
      fonts.advance(maxParts: 1);
    }
    return (
      cache: cache,
      page: page,
      parent: parent,
      fonts: fonts.takeMetrics(),
    );
  } finally {
    fonts.close();
  }
}

ForumBodyInlineEmphasisChildBandsPreparation _job(
  _Fixture f, {
  void Function()? guard,
  ForumBodyInlinePageContent? page,
  ForumBodyInlineParagraphLease? parent,
}) => ForumBodyInlineEmphasisChildBandsPreparation(
  fonts: f.fonts,
  page: page ?? f.page,
  parent: parent ?? f.parent,
  ensureOwner: guard ?? () {},
);
({ForumBodyInlineEmphasisChildBands value, int parts}) _finish(
  ForumBodyInlineEmphasisChildBandsPreparation job, {
  int quantum = 1,
}) {
  var parts = 0;
  try {
    for (var n = 0; !job.isReady; n++) {
      expect(n, lessThan(30000));
      final used = job.advance(maxParts: quantum);
      expect(used, inInclusiveRange(1, quantum));
      parts += used;
    }
    expect(job.advance(maxParts: 1), 0);
    return (value: job.takeBands(), parts: parts);
  } finally {
    job.close();
  }
}

List<Object?> _values(ForumBodyInlineEmphasisChildBands value) => [
  for (final b in value.children)
    b == null
        ? null
        : [
            b.atomIndex,
            b.lineIndex,
            b.source,
            b.glyphOrigin,
            b.baseTop,
            b.baseBottom,
            b.overEdge,
            b.underEdge,
            b.overBaseline,
            b.underBaseline,
            b.overAnnotationMarkerBounds,
            b.underAnnotationMarkerBounds,
          ],
];

ForumBodyInlinePageContent _copy(
  ForumBodyInlinePageContent page, {
  List<ForumBodyRubyAtomPlan>? atoms,
  List<PlaceholderDimensions>? dimensions,
  Set<int>? trimmed,
  ForumBodyParagraphLayoutMode? mode,
}) => ForumBodyInlinePageContent.atoms(
  content: page.content,
  dimensions: dimensions ?? page.dimensions,
  rubyAtoms: atoms ?? page.rubyAtoms,
  trimmedAtomIndices: trimmed ?? page.trimmedAtomIndices,
  rootFonts: page.rootFonts,
  containerBackgrounds: page.containerBackgrounds,
  layoutMode: mode ?? page.layoutMode,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final direction in TextDirection.values) {
    for (final scaler in [TextScaler.noScaling, const _Curve()]) {
      for (final width in [70.0, 300.0]) {
        for (final (index, html) in _fixtures.indexed) {
          test('real child bands $index $direction/$scaler/$width', () {
            final f = _fixture(
              html,
              direction: direction,
              scaler: scaler,
              width: width,
            );
            final atoms = f.page.rubyAtoms;
            expect(
              atoms.any(
                (a) => switch (index) {
                  0 => a is ForumBodyRubyColumnPlan,
                  1 => a is ForumBodyRubySegmentPlan,
                  2 => a is ForumBodyRubyTreePlan,
                  3 ||
                  4 ||
                  5 ||
                  8 ||
                  9 => a is ForumBodyRubyTreeEmphasisAtomPlan,
                  7 => a is ForumBodyRubySoftSpacePlan,
                  _ => true,
                },
              ),
              isTrue,
            );
            final before = (
              f.cache.layoutBuildCount,
              f.cache.pictureBuildCount,
              f.cache.hitCount,
              f.cache.activeLeases,
              f.cache.estimatedRetainedBytes,
            );
            final value = _finish(_job(f)).value,
                batched = _finish(_job(f), quantum: 7).value;
            expect(_values(value), _values(batched));
            expect(value.fonts, same(f.fonts));
            expect(value.page, same(f.page));
            expect(value.children, hasLength(f.page.rubyAtoms.length));
            for (final (i, band) in value.children.indexed) {
              if (f.page.trimmedAtomIndices.contains(i)) {
                expect(band, isNull);
                continue;
              }
              final b = band!;
              expect(b.atomIndex, i);
              expect(b.lineIndex, f.fonts.geometry.atomLineIndices[i]);
              expect(b.source, same(f.page.rubyAtoms[i]));
              final baseline = f.parent.layout.lines[b.lineIndex].baseline;
              ForumBodyRubyGroupMetrics? group;
              ForumBodyRubyLevelMetrics? level;
              final source = b.source;
              if (source is ForumBodyRubyColumnPlan) {
                group = source.metrics;
                expect(group, isNotNull);
              } else if (source is ForumBodyRubySegmentPlan) {
                level = source.metrics.level;
              } else if (source is ForumBodyRubySoftSpacePlan) {
                level = source.metrics.level;
              } else if (source is ForumBodyRubyTreePlan) {
                group = source.metrics.root.group;
                level = source.metrics.root.segment?.level;
              } else if (source is ForumBodyRubyTreeEmphasisAtomPlan) {
                final root =
                    source.format.placement.input.input.geometry.metrics.root;
                group = root.group;
                level = root.segment?.level;
                final placement = source.format.placement;
                final rootRow = placement.rows.singleWhere(
                  (r) => r.parent == null,
                );
                Rect? over, under;
                for (final mark in placement.marks) {
                  if (mark.row == rootRow.id) {
                    continue;
                  }
                  var row = placement.rowForId(mark.row);
                  while (row.parent != rootRow.id) {
                    row = placement.rowForId(row.parent!);
                  }
                  if (row.annotationSide == ForumBodyRubySide.over) {
                    over =
                        over?.expandToInclude(mark.fontBounds) ??
                        mark.fontBounds;
                  } else {
                    under =
                        under?.expandToInclude(mark.fontBounds) ??
                        mark.fontBounds;
                  }
                }
                expect(
                  b.overAnnotationMarkerBounds,
                  over?.shift(b.glyphOrigin),
                );
                expect(
                  b.underAnnotationMarkerBounds,
                  under?.shift(b.glyphOrigin),
                );
                expect(rootRow.overAnnotationMarkerBounds, over);
                expect(rootRow.underAnnotationMarkerBounds, under);
                expect(
                  b.overBaseline,
                  rootRow.overBaseline == null
                      ? null
                      : b.glyphOrigin.dy + rootRow.overBaseline!,
                );
                expect(
                  b.underBaseline,
                  rootRow.underBaseline == null
                      ? null
                      : b.glyphOrigin.dy + rootRow.underBaseline!,
                );
                if (index == 3 || index == 8) {
                  expect(b.overAnnotationMarkerBounds, isNotNull);
                } else if (index == 4) {
                  expect(b.underAnnotationMarkerBounds, isNotNull);
                }
              }
              final top = group == null
                  ? -level!.baseAscent
                  : group.baseBandTop - group.baseline;
              final bottom = group == null
                  ? level!.baseDescent
                  : group.baseBandBottom - group.baseline;
              expect(b.baseTop - baseline, closeTo(top, 1e-3));
              expect(b.baseBottom - baseline, closeTo(bottom, 1e-3));
              if (index == 6) {
                expect(
                  b.baseBottom - b.baseTop,
                  lessThan(f.page.dimensions[i].size.height / 2),
                );
                expect(
                  b.baseTop,
                  greaterThan(f.parent.layout.atomBoxes[i].top),
                );
              }
            }
            expect((
              f.cache.layoutBuildCount,
              f.cache.pictureBuildCount,
              f.cache.hitCount,
              f.cache.activeLeases,
              f.cache.estimatedRetainedBytes,
            ), before);
            expect(() => value.children.clear(), throwsUnsupportedError);
            f.parent.release();
            f.cache.clearUnpinned();
            expect(f.cache.activeLeases, 0);
            expect(_values(value), _values(batched));
          });
        }
      }
    }
  }
  for (final direction in TextDirection.values) {
    for (final scaler in [TextScaler.noScaling, const _Curve()]) {
      test(
        'trimmed real soft gaps contribute no child bands $direction/$scaler',
        () {
          final f = _fixture(
            _fixtures[7],
            direction: direction,
            scaler: scaler,
            width: 35,
          );
          expect(f.page.trimmedAtomIndices, isNotEmpty);
          final value = _finish(_job(f)).value;
          for (final index in f.page.trimmedAtomIndices) {
            expect(f.page.rubyAtoms[index], isA<ForumBodyRubySoftSpacePlan>());
            expect(value.children[index], isNull);
          }
          expect(f.cache.activeLeases, 1);
        },
      );
    }
  }
  test('a zero-text child cannot invent a source-bound atomic range', () {
    expect(
      () => _fixture(
        '<ruby style="text-emphasis:circle"><rb></rb><rt></rt></ruby>',
      ),
      throwsA(
        isA<ForumBodyParagraphInputException>().having(
          (e) => e.failure,
          'failure',
          ForumBodyParagraphInputFailure.structure,
        ),
      ),
    );
  });
  test(
    'real indivisible overflow remains a layout failure before band capture',
    () {
      expect(
        () => _fixture('<ruby>A<rt>long annotation</rt></ruby>', width: 70),
        throwsA(
          isA<ForumBodyRubyGroupException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyRubyGroupFailure.overflow,
          ),
        ),
      );
    },
  );
  test(
    'column metrics are required for bands and qualify actual dimensions',
    () {
      final f = _fixture(_fixtures[0]);
      final actual = f.page.rubyAtoms.single as ForumBodyRubyColumnPlan;
      expect(actual.metrics, isNotNull);
      final legacy = _copy(
        f.page,
        atoms: [
          ForumBodyRubyAtomPlan.column(
            request: actual.request,
            level: actual.level,
          ),
        ],
      );
      expect(
        () => _finish(_job(f, page: legacy)),
        throwsA(
          isA<ForumBodyEmphasisGeometryException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyEmphasisGeometryFailure.source,
          ),
        ),
      );
      final dimension = f.page.dimensions.single;
      expect(
        () => _copy(
          f.page,
          dimensions: [
            PlaceholderDimensions(
              size: Size(dimension.size.width, dimension.size.height + 1),
              alignment: dimension.alignment,
              baseline: dimension.baseline,
              baselineOffset: dimension.baselineOffset,
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => _job(
          f,
          page: _copy(
            f.page,
            mode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
          ),
        ),
        throwsA(isA<ForumBodyEmphasisGeometryException>()),
      );
      expect(f.cache.activeLeases, 1);
    },
  );
  test('a stale soft trim mask cannot describe the current native parent', () {
    final f = _fixture(_fixtures[7]);
    final soft = f.page.rubyAtoms.indexWhere(
      (a) => a is ForumBodyRubySoftSpacePlan,
    );
    expect(soft, greaterThanOrEqualTo(0));
    expect(f.page.trimmedAtomIndices, isEmpty);
    final stale = _copy(f.page, trimmed: {soft});
    expect(
      () => _finish(_job(f, page: stale)),
      throwsA(
        isA<ForumBodyEmphasisGeometryException>().having(
          (e) => e.failure,
          'failure',
          ForumBodyEmphasisGeometryFailure.source,
        ),
      ),
    );
    expect(f.cache.activeLeases, 1);
  });
  test(
    'column measurement must fit the actual annotation sides and row target',
    () {
      final f = _fixture(_fixtures[0]);
      final original = f.page.rubyAtoms.single as ForumBodyRubyColumnPlan;
      final target =
          original.level ?? ForumBodyRubyLevelMetrics.single(original.metrics!);
      for (final html in [
        '<ruby style="ruby-position:under">A<rt>x</rt></ruby>',
        '<ruby style="font-size:50px">A<rt>x</rt></ruby>',
      ]) {
        final other =
            _fixture(html).page.rubyAtoms.single as ForumBodyRubyColumnPlan;
        expect(
          () => ForumBodyRubyAtomPlan.column(
            request: original.request,
            level: target,
            metrics: other.metrics,
          ),
          throwsArgumentError,
        );
      }
      expect(f.cache.activeLeases, 1);
    },
  );
  test('equal values from another source or physical parent cannot bind', () {
    final a = _fixture(_fixtures[3]), b = _fixture(_fixtures[3]);
    expect(
      () => _job(a, page: b.page),
      throwsA(isA<ForumBodyEmphasisGeometryException>()),
    );
    expect(
      () => _job(a, parent: b.parent),
      throwsA(isA<ForumBodyEmphasisGeometryException>()),
    );
    expect(a.cache.activeLeases, 1);
    expect(b.cache.activeLeases, 1);
  });
  test('every bounded work and ready handoff guards its borrowed owner', () {
    final f = _fixture(_fixtures[3]);
    final parts = _finish(_job(f)).parts;
    for (var boundary = 0; boundary <= parts; boundary++) {
      var active = true;
      final job = _job(
        f,
        guard: () {
          if (!active) {
            throw StateError('Retired');
          }
        },
      );
      for (var n = 0; n < boundary; n++) {
        job.advance(maxParts: 1);
      }
      active = false;
      expect(
        job.isReady ? job.takeBands : () => job.advance(maxParts: 1),
        throwsStateError,
      );
      expect(job.isReady, isFalse);
      job.close();
      expect(f.cache.activeLeases, 1);
    }
  });
  test('released current parent blocks active and ready snapshots', () {
    final f = _fixture(_fixtures[3]);
    for (final ready in [false, true]) {
      final parent = f.page.parentRequest.acquire(
        f.cache,
        width: 300,
        textScaler: TextScaler.noScaling,
        cachedOnly: false,
      )!;
      final job = _job(f, parent: parent);
      if (ready) {
        while (!job.isReady) {
          job.advance(maxParts: 1);
        }
      }
      parent.release();
      expect(
        ready ? job.takeBands : () => job.advance(maxParts: 1),
        throwsStateError,
      );
      expect(job.isReady, isFalse);
      job.close();
      expect(f.cache.activeLeases, 1);
    }
  });
  test('owner callback cannot reenter or revive close/ready work', () {
    final f = _fixture(_fixtures[3]);
    for (final mode in [0, 1, 2]) {
      var armed = false;
      late ForumBodyInlineEmphasisChildBandsPreparation job;
      job = _job(
        f,
        guard: () {
          if (!armed) {
            return;
          }
          if (mode == 0 || mode == 2 && job.isReady) {
            job.close();
          } else if (mode == 1) {
            job.advance(maxParts: 1);
          }
        },
      );
      armed = true;
      expect(() => _finish(job), throwsStateError);
      expect(f.cache.activeLeases, 1);
    }
  });
}
