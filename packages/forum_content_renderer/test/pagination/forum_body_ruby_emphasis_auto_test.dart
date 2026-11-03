import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_preparation.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_source_preparation.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_input.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_atom_request.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_tree_input.dart';

import '../inline/test_support/ruby_tree_emphasis_scene_fixture.dart';

const _limits = ForumBodyTextPageSessionLimits(
  maxPages: 100,
  maxFragments: 1000,
  maxParagraphs: 100,
  maxTextCodeUnits: 200000,
  maxRuns: 20000,
  maxIssuedLeases: 128,
);
const _aligned =
    '<ruby style="text-emphasis:circle">A<rt style="font-size:5px">x</rt>'
    'B<rt style="font-size:30px">yy</rt></ruby>';

final class _Curve extends TextScaler {
  const _Curve();
  @override
  double scale(double size) => size * (size < 20 ? 1.4 : 1.1);
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}

ForumBodyReaderStyle _reader(TextDirection direction) => ForumBodyReaderStyle(
  textStyle: const TextStyle(
    fontFamily: 'Ahem',
    fontSize: 20,
    color: Color(0xff123456),
  ),
  fontRevision: 'auto-ruby-ahem',
  linkColor: const Color(0xff0000ff),
  textDirection: direction,
);

ForumBodyInlineFlowContent _flow(
  ForumBodyDocument doc,
  TextDirection direction,
) {
  final flow = ForumBodyTextFlowCursor(
    document: doc,
    reader: _reader(direction),
  );
  try {
    while (!flow.isComplete) {
      flow.advance(maxEvents: 1);
      if (flow.current case ForumBodyTextFlowInline(:final content)) {
        return content;
      }
    }
    throw StateError('Missing actual inline context');
  } finally {
    flow.close();
  }
}

ForumBodyDocument _doc(String html) => const ForumBodyParser().parse(
  html: '<p style="margin:0">$html</p>',
  sourceId: 'auto-ruby',
  conversionIdentity: 'none',
);

ForumBodyParagraphCache _cache() =>
    ForumBodyParagraphCache(maxEntries: 512, maxEstimatedBytes: 1 << 26);

ForumBodyInlinePlanInput _source(
  ForumBodyInlineFlowContent flow, {
  double width = 300,
}) {
  final work = ForumBodyInlineSourcePreparation(
    input: flow,
    width: width,
    ensureOwner: () {},
  );
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(30000));
      expect(work.advance(maxParts: 1), 1);
    }
    return work.takeInput();
  } finally {
    work.close();
  }
}

({ForumBodyInlinePageContent content, ForumBodyInlineParagraphLease lease})
_plan(
  ForumBodyInlineFlowContent flow,
  ForumBodyParagraphCache cache, {
  double width = 300,
  TextScaler scaler = TextScaler.noScaling,
  int quantum = 1,
}) {
  final work = ForumBodyInlinePlanPreparation.fromFlow(
    input: flow,
    width: width,
    cache: cache,
    textScaler: scaler,
    ensureOwner: () {},
  );
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(30000));
      final before = (cache.layoutBuildCount, cache.pictureBuildCount);
      final step = work.advance(maxParts: quantum);
      expect(step.partsPrepared, lessThanOrEqualTo(quantum));
      expect(step.waitingForLayoutBudget, isFalse);
      expect(work.cacheMiss, isFalse);
      expect(
        cache.layoutBuildCount -
            before.$1 +
            cache.pictureBuildCount -
            before.$2,
        lessThanOrEqualTo(1),
      );
    }
    return work.take();
  } finally {
    work.close();
  }
}

void _finish(
  ForumBodyTextPageSession session,
  ForumBodyParagraphCache cache, {
  int quantum = 1,
}) {
  for (var n = 0; !session.isComplete; n++) {
    expect(n, lessThan(50000));
    final pictures = cache.pictureBuildCount;
    final step = session.advance(
      maxEvents: 2,
      maxLines: 1,
      maxFormatParts: quantum,
    );
    expect(step.formatUnitsPrepared, lessThanOrEqualTo(quantum));
    expect(step.layoutsBuilt, lessThanOrEqualTo(1));
    expect(step.waitingForLayoutBudget, isFalse);
    expect(step.madeProgress, isTrue);
    expect(cache.pictureBuildCount, pictures);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final direction in TextDirection.values) {
    for (final scaler in [TextScaler.noScaling, const _Curve()]) {
      for (final (index, html) in [
        rubyTreeEmphasisSceneNested,
        rubyTreeEmphasisSceneMixed,
        rubyTreeEmphasisSceneSegment,
        _aligned,
        '<ruby style="text-emphasis:circle">.<rt>x</rt></ruby>',
      ].indexed) {
        test(
          'source -> actual InlinePlan -> Session/page fixture=$index $direction $scaler',
          () {
            final doc = _doc(html), cache = _cache();
            addTearDown(cache.close);
            final flow = _flow(doc, direction), source = _source(flow);
            expect(source.hasEmphasisTrees, isTrue);
            for (final request
                in source.atoms
                    .whereType<ForumBodyRubyTreeEmphasisAtomRequest>()) {
              for (final item in request.value.sources.where(
                (s) => !s.content.isSourceFree,
              )) {
                expect(
                  source.content.contexts.any(
                    (w) => identical(w.content, item.content),
                  ),
                  isTrue,
                );
              }
              expect(
                request.nativeRequests.every(
                  (r) => !r.content.style.textEmphasis.isEnabled,
                ),
                isTrue,
              );
            }
            final planned = _plan(
              flow,
              cache,
              scaler: scaler,
              quantum: index + 1,
            );
            try {
              expect(
                planned.content.rubyAtoms.every(
                  (a) => a is ForumBodyRubyTreeEmphasisAtomPlan,
                ),
                isTrue,
              );
              for (final (i, atom) in planned.content.rubyAtoms.indexed) {
                final a = atom as ForumBodyRubyTreeEmphasisAtomPlan,
                    d = planned.content.dimensions[i];
                expect(d.size.width, closeTo(a.format.frame.size.width, 1e-4));
                expect(
                  d.size.height,
                  closeTo(a.format.frame.size.height, 1e-4),
                );
                expect(planned.lease.layout.dimensions[i].size, d.size);
              }
            } finally {
              planned.lease.release();
            }
            final session = ForumBodyTextPageSession(
              document: doc,
              reader: _reader(direction),
              cache: cache,
              limits: _limits,
              layoutId: 'auto-complete',
              width: 300,
              height: 240,
              textScaler: scaler,
              maxNativeEntriesPerPage: 64,
            );
            addTearDown(session.close);
            _finish(session, cache);
            expect(session.snapshot.isComplete, isTrue);
            expect(cache.activeLeases, 0);
            cache.clearUnpinned();
            for (var page = 0; page < session.snapshot.length; page++) {
              final job = session.openPagePreparation(page);
              try {
                for (var n = 0; !job.isReady; n++) {
                  expect(n, lessThan(30000));
                  final step = job.advance(maxFragments: 1, maxParts: 1);
                  expect(
                    step.layoutsBuilt + step.picturesBuilt,
                    lessThanOrEqualTo(1),
                  );
                  expect(step.waitingForLayoutBudget, isFalse);
                }
                final result = job.takeFragments();
                job.close();
                try {
                  validateForumBodyPreparedTextPageBinding(
                    snapshot: session.snapshot,
                    pageIndex: page,
                    layoutId: 'auto-complete',
                    fragments: result,
                  );
                  final recorder = ui.PictureRecorder();
                  try {
                    for (final fragment
                        in result
                            .whereType<ForumBodyPreparedInlineFragment>()) {
                      fragment.view.paint(Canvas(recorder), Offset.zero);
                      for (final b in fragment.glyphBoxes(
                        fragment.view.coverageStartUtf16,
                        fragment.view.coverageEndUtf16,
                      )) {
                        expect(b.toRect().isFinite, isTrue);
                      }
                    }
                  } finally {
                    recorder.endRecording().dispose();
                  }
                } finally {
                  for (final f in result) {
                    f.close();
                  }
                }
              } finally {
                job.close();
              }
              expect(cache.activeLeases, 0);
            }
          },
        );
      }
    }
  }
  test(
    'physical wrapping uses complete frames and same-root alignment only within the actual row',
    () {
      final flow = _flow(_doc(_aligned), TextDirection.ltr), cache = _cache();
      addTearDown(cache.close);
      final source = _source(flow);
      expect(source.atoms, hasLength(2));
      expect(source.rubyLevelIds.toSet(), hasLength(1));
      for (final width in [100.0, 65.0]) {
        final ready = _plan(flow, cache, width: width);
        try {
          final atoms = ready.content.rubyAtoms
              .cast<ForumBodyRubyTreeEmphasisAtomPlan>();
          final first =
                  atoms.first.format.placement.input.input.geometry.metrics,
              last = atoms.last.format.placement.input.input.geometry.metrics;
          if (width == 100) {
            expect(ready.lease.layout.lines, hasLength(1));
            expect(
              first.root.group!.annotations.single.bandBaseline -
                  first.root.group!.baseline,
              last.root.group!.annotations.single.bandBaseline -
                  last.root.group!.baseline,
            );
          } else {
            expect(ready.lease.layout.lines, hasLength(2));
            expect(
              first.root.group!.annotations.single.bandBaseline -
                  first.root.group!.baseline,
              isNot(
                last.root.group!.annotations.single.bandBaseline -
                    last.root.group!.baseline,
              ),
            );
          }
        } finally {
          ready.lease.release();
        }
      }
    },
  );
  for (final html in [
    '<ruby>A<rt style="text-emphasis:sesame">x</rt></ruby>',
    '<ruby><rb><span style="text-emphasis:circle">A</span></rb><rt>x</rt></ruby>',
    '<ruby><ruby>A<rt style="text-emphasis:circle">x</rt></ruby><rt>y</rt></ruby>',
  ]) {
    test(
      'actual root/rank/run emphasis is discovered without a root flag $html',
      () {
        final source = _source(_flow(_doc(html), TextDirection.ltr));
        expect(source.hasEmphasisTrees, isTrue);
        expect(
          source.atoms.single,
          isA<ForumBodyRubyTreeEmphasisAtomRequest>(),
        );
      },
    );
  }
  test(
    'flat ordinary roots keep split columns and long inspection obeys the source budget',
    () {
      final body = List.generate(
        120,
        (i) => '<span style="color:${i.isEven ? 'red' : 'blue'}">A</span>',
      ).join();
      final flow = _flow(
        _doc('<ruby><rb>$body</rb><rt>x</rt><rb>B</rb><rt>y</rt></ruby>'),
        TextDirection.ltr,
      );
      final work = ForumBodyInlineSourcePreparation(
        input: flow,
        width: 300,
        ensureOwner: () {},
      );
      var calls = 0;
      try {
        while (!work.isReady) {
          expect(work.advance(maxParts: 1), 1);
          calls++;
          expect(calls, lessThan(30000));
        }
        final input = work.takeInput();
        expect(calls, greaterThan(120));
        expect(input.hasEmphasisTrees, isFalse);
        expect(
          input.atoms.every((a) => a is ForumBodyRubyColumnAtomRequest),
          isTrue,
        );
      } finally {
        work.close();
      }
    },
  );
  test(
    'derived glyph band associations use actual original windows and retain all full/half samples',
    () {
      final input = _source(
        _flow(
          _doc(
            '<ruby style="text-emphasis:circle;font-size:26px">'
            'A<rt style="font-size:17px"></rt>B<rt>x</rt></ruby>',
          ),
          TextDirection.ltr,
        ),
      );
      final requests = input.atoms.cast<ForumBodyRubyTreeEmphasisAtomRequest>();
      expect(
        requests
            .expand((a) => a.nativeRequests)
            .whereType<ForumBodyTextBandChildRequest>(),
        isNotEmpty,
      );
      expect(input.nativeFontSizes.toSet(), containsAll([26.0, 13.0, 17.0]));
      for (final atom in requests) {
        for (final source in atom.value.sources.where((s) => s.needsNative)) {
          expect(
            atom.nativeRequests.any((r) => identical(r.content, source.glyphs)),
            isTrue,
          );
        }
      }
    },
  );
  test(
    'projection of a prepared source tree keeps the exact graph and current windows',
    () {
      final flow = _flow(_doc(rubyTreeEmphasisSceneNested), TextDirection.ltr),
          group = flow.parts.whereType<ForumBodyInlineFlowRuby>().single.group;
      final tree = ForumBodyRubyTreeInputPreparation(
        group: group,
        maxWidth: 300,
      );
      while (!tree.isReady) {
        tree.advance(maxParts: 1);
      }
      final actual = tree.takeInput();
      tree.close();
      final projection = ForumBodyRubyGlyphTreeInputPreparation.fromTree(
        sourceTree: actual,
        ensureOwner: () {},
      );
      try {
        while (!projection.isReady) {
          expect(projection.advance(maxParts: 1), 1);
        }
        final input = projection.takeInput();
        expect(input.sourceTree, same(actual));
        for (final source in input.sources) {
          expect(
            source.content,
            same(actual.sources.singleWhere((s) => s.id == source.id).content),
          );
        }
      } finally {
        projection.close();
      }
    },
  );
  test(
    'active mixed opaque parents and parent-line emphasis remain explicitly gated',
    () {
      final cache = _cache();
      addTearDown(cache.close);
      for (final html in [
        '<ruby style="text-emphasis:circle"><rb>L<ruby>A<rt>x</rt></ruby>R</rb><rt>y</rt></ruby>',
      ]) {
        expect(
          () => _plan(_flow(_doc(html), TextDirection.ltr), cache),
          throwsA(isA<ForumBodyParagraphInputException>()),
        );
        expect(cache.activeLeases, 0);
      }
      expect(
        () => _plan(
          _flow(
            _doc(
              '<span style="text-emphasis:circle">A'
              '<ruby>B<rt>b</rt></ruby>C</span>',
            ),
            TextDirection.ltr,
          ),
          cache,
        ),
        throwsA(
          isA<ForumBodyParagraphLayoutException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphLayoutFailure.emphasis,
          ),
        ),
      );
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'a later glyph band retry invalidates earlier complete formats before publication',
    () {
      final html =
          '<ruby style="text-emphasis:circle"><rb><ruby>AB<rt>xy</rt></ruby></rb><rt>zz</rt></ruby>'
          '<ruby dir="rtl" style="line-height:.25;text-emphasis:circle"><rb style="line-height:.25">'
          '<ruby style="line-height:.25">CD<rt style="line-height:.25">uv</rt></ruby></rb>'
          '<rt style="line-height:.25">ww</rt></ruby>';
      final source = _source(_flow(_doc(html), TextDirection.ltr), width: 300),
          cache = _cache();
      addTearDown(cache.close);
      final band =
          (source.atoms.last.nativeRequests.first
                  as ForumBodyTextBandChildRequest)
              .band;
      source.replaceBand(band, 1);
      final before = source.atoms
          .cast<ForumBodyRubyTreeEmphasisAtomRequest>()
          .map((a) => a.value)
          .toList();
      final work = ForumBodyInlinePlanPreparation(
        input: source,
        cache: cache,
        textScaler: TextScaler.noScaling,
        ensureOwner: () {},
      );
      try {
        for (var n = 0; !work.isReady; n++) {
          expect(n, lessThan(30000));
          final builds = cache.layoutBuildCount;
          final step = work.advance(maxParts: 1);
          expect(step.partsPrepared, lessThanOrEqualTo(1));
          expect(cache.layoutBuildCount - builds, lessThanOrEqualTo(1));
          expect(step.waitingForLayoutBudget, isFalse);
        }
        final ready = work.take();
        try {
          final after = source.atoms
              .cast<ForumBodyRubyTreeEmphasisAtomRequest>()
              .map((a) => a.value)
              .toList();
          expect(after.first, isNot(same(before.first)));
          expect(
            (source.atoms.last.nativeRequests.first
                    as ForumBodyTextBandChildRequest)
                .gutter,
            greaterThan(1),
          );
          for (final (i, atom) in ready.content.rubyAtoms.indexed) {
            final current = atom as ForumBodyRubyTreeEmphasisAtomPlan;
            expect(current.request, same(after[i]));
            expect(
              current.format.placement.input.input.geometry.metrics.input,
              same(after[i]),
            );
            for (final item in current.request.sources) {
              expect(
                item.content,
                same(before[i].sourceForId(item.id).content),
              );
            }
          }
        } finally {
          ready.lease.release();
        }
      } finally {
        work.close();
      }
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'every automatic plan work boundary and final publication cancels owned native resources',
    () {
      final flow = _flow(
            _doc('<ruby style="text-emphasis:circle">A<rt>x</rt></ruby>'),
            TextDirection.ltr,
          ),
          cache = _cache();
      addTearDown(cache.close);
      ForumBodyInlinePlanPreparation open() =>
          ForumBodyInlinePlanPreparation.fromFlow(
            input: flow,
            width: 100,
            cache: cache,
            textScaler: TextScaler.noScaling,
            ensureOwner: () {},
          );
      final first = open();
      var count = 0;
      while (!first.isReady) {
        first.advance(maxParts: 1);
        count++;
        expect(count, lessThan(30000));
      }
      first.close();
      for (var cut = 0; cut <= count; cut++) {
        final work = open();
        for (var n = 0; n < cut && !work.isReady; n++) {
          work.advance(maxParts: 1);
        }
        work.close();
        expect(cache.activeLeases, 0, reason: 'boundary=$cut');
        expect(work.nativeLeases, isEmpty);
      }
    },
  );

  test(
    'retirement during source inspection/projection and ready transfer cannot publish late input',
    () {
      final flow = _flow(_doc(rubyTreeEmphasisSceneNested), TextDirection.ltr);
      var checks = 0;
      final counted = ForumBodyInlineSourcePreparation(
        input: flow,
        width: 300,
        ensureOwner: () {
          checks++;
        },
      );
      while (!counted.isReady) {
        counted.advance(maxParts: 1);
      }
      counted.close();
      for (final stop in {1, 5, checks ~/ 2, checks - 1, checks}) {
        var calls = 0;
        late ForumBodyInlineSourcePreparation work;
        work = ForumBodyInlineSourcePreparation(
          input: flow,
          width: 300,
          ensureOwner: () {
            if (++calls == stop) work.close();
          },
        );
        try {
          expect(() {
            while (!work.isReady) {
              work.advance(maxParts: 1);
            }
          }, throwsStateError);
          expect(() => work.takeInput(), throwsStateError);
        } finally {
          work.close();
        }
      }
    },
  );

  test(
    'automatic planning retains no visible leases while the numeric session completes',
    () {
      final doc = _doc(
            '$rubyTreeEmphasisSceneNested<br>$rubyTreeEmphasisSceneMixed',
          ),
          cache = _cache();
      addTearDown(cache.close);
      final session = ForumBodyTextPageSession(
        document: doc,
        reader: _reader(TextDirection.ltr),
        cache: cache,
        limits: _limits,
        layoutId: 'automatic-pages',
        width: 300,
        height: 80,
        maxNativeEntriesPerPage: 64,
      );
      addTearDown(session.close);
      _finish(session, cache);
      // The real block flow omits each context's trailing empty physical BR
      // row. These two readable contexts total 103px, so an 80px viewport must
      // paginate them without treating that omitted row as body content.
      expect(session.snapshot.length, greaterThan(1));
      expect(
        session.snapshot
            .expand((p) => p.fragments)
            .map((f) => f.paragraphIndex)
            .toSet(),
        hasLength(2),
      );
      expect(cache.activeLeases, 0);
      final job = session.openPagePreparation(0);
      while (!job.isReady) {
        job.advance(maxFragments: 1, maxParts: 1);
      }
      final fragments = job.takeFragments();
      job.close();
      expect(fragments.single.isActive, isTrue);
      session.close();
      expect(fragments.single.isActive, isFalse);
      expect(cache.activeLeases, 0);
      for (final fragment in fragments) {
        fragment.close();
      }
    },
  );
  test(
    'actual marker overhang determines wrapping before same-root row alignment',
    () {
      final html = _aligned.replaceFirst(
        'text-emphasis:circle',
        "text-emphasis:'👩‍👩‍👧‍👦'",
      );
      final flow = _flow(_doc(html), TextDirection.ltr), cache = _cache();
      addTearDown(cache.close);
      final ready = _plan(flow, cache, width: 90);
      try {
        final first =
            ready.content.rubyAtoms.first as ForumBodyRubyTreeEmphasisAtomPlan;
        final last =
            ready.content.rubyAtoms.last as ForumBodyRubyTreeEmphasisAtomPlan;
        final firstGlyph = first.format.placement.input.input.geometry.metrics;
        final lastGlyph = last.format.placement.input.input.geometry.metrics;
        expect(
          first.format.frame.size.width,
          greaterThan(firstGlyph.box.bounds.width),
        );
        expect(ready.lease.layout.lines, hasLength(2));
        expect(
          firstGlyph.root.group!.annotations.single.bandBaseline -
              firstGlyph.root.group!.baseline,
          isNot(
            lastGlyph.root.group!.annotations.single.bandBaseline -
                lastGlyph.root.group!.baseline,
          ),
        );
      } finally {
        ready.lease.release();
      }
    },
  );
}
