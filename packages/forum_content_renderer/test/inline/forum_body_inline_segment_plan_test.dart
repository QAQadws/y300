import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_input.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_preparation.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_atom_request.dart';

ForumBodyInlinePlanInput _input(String html, {double width = 300}) {
  final document = const ForumBodyParser().parse(
    html: html,
    sourceId: 'formal-span-plan',
    conversionIdentity: 'none',
  );
  final flow = ForumBodyTextFlowCursor(
    document: document,
    reader: ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
      fontRevision: 'ahem',
      linkColor: const Color(0xff0000ff),
    ),
  );
  try {
    while (!flow.isComplete) {
      flow.advance(maxEvents: 1);
      if (flow.current case ForumBodyTextFlowInline(:final content)) {
        return ForumBodyInlinePlanInput(content, width);
      }
    }
    throw StateError('No actual inline input');
  } finally {
    flow.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  test('the retained span is one original source-bound atom', () {
    final input = _input(
      '<ruby><rb>A</rb><rb>B</rb><rtc>word</rtc><rtc><rt>x</rt></rtc></ruby>',
    );
    expect(input.content.projection.display.text, 'ABword');
    expect(input.content.projection.atoms.length, 1);
    expect(() => input.groups, throwsStateError);
    final request =
        (input.atoms.single as ForumBodyRubySegmentAtomRequest).value;
    expect(request.bases.map((b) => b.content.projection.text), ['A', 'B']);
    expect(
      request.spans.map((s) => (s.startColumn, s.endColumn, s.annotationIndex)),
      [(0, 2, 0)],
    );
    expect(request.nativeHandleCount, 3);
    final original = request.nativeRequests.map((r) => r.content).toList();
    final bound = input.content.resolveAtomicContexts(0, original);
    expect(bound.map((c) => c.content), orderedEquals(original));
    final band = (request.bases.first as ForumBodyTextBandChildRequest).band;
    expect(band.contexts, orderedEquals(original));
    input.replaceBand(band, 123);
    final rebound =
        (input.atoms.single as ForumBodyRubySegmentAtomRequest).value;
    expect(
      rebound.nativeRequests.every(
        (r) => (r as ForumBodyTextBandChildRequest).gutter == 123,
      ),
      isTrue,
    );
    expect(
      rebound.nativeRequests.map((r) => r.content),
      orderedEquals(original),
    );
    input.replaceBand(band, null);
    expect(
      (input.atoms.single as ForumBodyRubySegmentAtomRequest)
          .value
          .nativeRequests
          .every((r) => r is ForumBodyParagraphTextRequest),
      isTrue,
    );
  });

  for (final q in [1, 7, 32]) {
    for (final narrow in [false, true]) {
      test(
        'actual same-root spanning group and following base use physical row union q=$q narrow=$narrow',
        () {
          final input = _input(
            '<ruby><rb style="font-size:30px">A</rb><rb>B</rb><rtc style="font-size:10px">xx</rtc><rb style="font-size:10px">C</rb><rt style="font-size:10px">y</rt></ruby>',
            width: narrow ? 50 : 100,
          );
          expect(input.atoms.map((r) => r.runtimeType), [
            ForumBodyRubySegmentAtomRequest,
            ForumBodyRubyColumnAtomRequest,
          ]);
          expect(input.rubyLevelIds, [0, 0]);
          final cache = ForumBodyParagraphCache(
            maxEntries: 4,
            maxEstimatedBytes: 1 << 24,
          );
          addTearDown(cache.close);
          final prep = ForumBodyInlinePlanPreparation(
            input: input,
            cache: cache,
            textScaler: TextScaler.noScaling,
            ensureOwner: () {},
          );
          addTearDown(prep.close);
          for (var i = 0; !prep.isReady && i < 10000; i++) {
            final builds = cache.layoutBuildCount;
            final step = prep.advance(maxParts: q);
            expect(step.partsPrepared, inInclusiveRange(1, q));
            expect(cache.layoutBuildCount - builds, lessThanOrEqualTo(1));
            expect(cache.pictureBuildCount, 0);
          }
          expect(prep.isReady, isTrue);
          final result = prep.take();
          try {
            final segment =
                result.content.rubyAtoms.first as ForumBodyRubySegmentPlan;
            final column =
                result.content.rubyAtoms.last as ForumBodyRubyColumnPlan;
            if (narrow) {
              expect(column.level, isNull);
            } else {
              expect(column.level, isNotNull);
              expect(
                segment.metrics.level.baseAscent,
                column.level!.baseAscent,
              );
              expect(
                result.content.dimensions
                    .map((d) => d.baselineOffset)
                    .toSet()
                    .length,
                1,
              );
            }
            expect(result.lease.layout.lines.length, narrow ? 2 : 1);
            expect(cache.activeLeases, 1);
          } finally {
            result.lease.release();
          }
          expect(cache.activeLeases, 0);
        },
      );
    }
  }

  for (final rejectRetry in [false, true]) {
    test(
      'span isolation failure yields, then retries actual requests only, repeated=$rejectRetry',
      () {
        final input = _input(
          '<ruby style="line-height:.25"><rb>A</rb><rb>B</rb><rtc style="line-height:.25">xy</rtc></ruby>',
        );
        final band =
            ((input.atoms.single as ForumBodyRubySegmentAtomRequest)
                        .value
                        .bases
                        .first
                    as ForumBodyTextBandChildRequest)
                .band;
        input.replaceBand(band, 1);
        final cache = ForumBodyParagraphCache(
          maxEntries: 4,
          maxEstimatedBytes: 1 << 24,
        );
        addTearDown(cache.close);
        final prep = ForumBodyInlinePlanPreparation(
          input: input,
          cache: cache,
          textScaler: TextScaler.noScaling,
          ensureOwner: () {},
        );
        addTearDown(prep.close);
        expect(prep.advance(maxParts: 1).partsPrepared, 1);
        expect(cache.activeLeases, 0);
        cache.clearUnpinned();
        final rejected = prep.advance();
        expect(rejected.partsPrepared, 1);
        expect(cache.activeLeases, 0);
        final retried =
            (input.atoms.single as ForumBodyRubySegmentAtomRequest).value;
        expect(
          retried.nativeRequests.every(
            (r) => (r as ForumBodyTextBandChildRequest).gutter! > 1,
          ),
          isTrue,
        );
        if (rejectRetry) {
          input.replaceBand(band, 1);
          expect(prep.advance().partsPrepared, 1);
          expect(
            (input.atoms.single as ForumBodyRubySegmentAtomRequest)
                .value
                .nativeRequests
                .every((r) => r is ForumBodyParagraphTextRequest),
            isTrue,
          );
        }
        for (var i = 0; !prep.isReady && i < 1000; i++) {
          final builds = cache.layoutBuildCount;
          prep.advance(maxParts: 7);
          expect(cache.layoutBuildCount - builds, lessThanOrEqualTo(1));
        }
        expect(prep.isReady, isTrue);
        final result = prep.take();
        result.lease.release();
        expect(cache.activeLeases, 0);
      },
    );
  }

  test('internal physical gap keeps its original source and base edge', () {
    final input = _input('<ruby><rb>A</rb> <rb>B</rb><rtc>wide</rtc></ruby>');
    expect(input.content.projection.display.text, 'A Bwide');
    final request =
        (input.atoms.single as ForumBodyRubySegmentAtomRequest).value;
    expect(request.gaps.single.beforeColumn, 1);
    expect(request.gaps.single.request.content.projection.text, ' ');
    expect(request.bases.length, 2);
    expect(request.nativeRequests.map((r) => r.content.projection.text), [
      'A',
      ' ',
      'B',
      'wide',
    ]);
    input.content.resolveAtomicContexts(
      0,
      request.nativeRequests.map((r) => r.content).toList(),
    );
  });

  test('a gap in an omitted level does not enter the spanning request', () {
    final input = _input(
      '<ruby><rb>A</rb> <rb>B</rb><rtc>whole</rtc><rtc><rt>x</rt> <rt>y</rt></rtc></ruby>',
    );
    final request =
        (input.atoms.single as ForumBodyRubySegmentAtomRequest).value;
    expect(request.annotationGaps, isEmpty);
    expect(request.nativeRequests.map((r) => r.content.projection.text), [
      'A',
      ' ',
      'B',
      'whole',
    ]);
    expect(request.bases.length, 2);
    expect(request.spans, hasLength(1));
    input.content.resolveAtomicContexts(
      0,
      request.nativeRequests.map((r) => r.content).toList(),
    );
  });

  for (final outer in ['', '<rtc> </rtc>']) {
    test(
      'a gap does not fuse otherwise breakable columns even with an empty outer box: $outer',
      () {
        final input = _input(
          '<ruby><rb>A</rb><rb>B</rb><rtc><rt>x</rt> <rt>y</rt></rtc>$outer</ruby>',
        );
        expect(input.atoms.map((a) => a.runtimeType), [
          ForumBodyRubyColumnAtomRequest,
          ForumBodyRubySoftSpaceAtomRequest,
          ForumBodyRubyColumnAtomRequest,
        ]);
        expect(input.content.projection.display.text, 'Ax By');
        expect(input.rubyLevelIds, [0, 0, 0]);
        final gap = (input.atoms[1] as ForumBodyRubySoftSpaceAtomRequest).value;
        expect(gap.beforeColumn, 1);
        expect(gap.members.single.annotationIndex, 0);
        expect(gap.members.single.request.content.isSourceFree, isFalse);
        expect(gap.sides, [ForumBodyRubySide.over]);
      },
    );
  }

  test(
    'a direct RT gap does not silently disappear or fuse breakable columns',
    () {
      final input = _input(
        '<ruby><rb>A</rb><rb>B</rb><rt>x</rt> <rt>y</rt></ruby>',
      );
      final gap = (input.atoms[1] as ForumBodyRubySoftSpaceAtomRequest).value;
      expect(gap.members.single.request.content.projection.text, ' ');
      final band =
          (gap.members.single.request as ForumBodyTextBandChildRequest).band;
      expect(band.contexts.map((c) => c.projection.text), [
        'A',
        'B',
        'x',
        ' ',
        'y',
      ]);
      final original = gap.members.single.request.content;
      input.replaceBand(band, 123);
      final rebound =
          (input.atoms[1] as ForumBodyRubySoftSpaceAtomRequest).value;
      expect(
        (rebound.members.single.request as ForumBodyTextBandChildRequest)
            .gutter,
        123,
      );
      expect(rebound.members.single.request.content, same(original));
      input.replaceBand(band, null);
      expect(
        (input.atoms[1] as ForumBodyRubySoftSpaceAtomRequest)
            .value
            .members
            .single
            .request,
        isA<ForumBodyParagraphTextRequest>(),
      );
    },
  );

  test(
    'base and annotation gaps retain source ordering through band retries',
    () {
      final input = _input(
        '<ruby><rb>A</rb> <rb>B</rb><rtc><rt>x</rt> <rt>y</rt></rtc><rtc style="ruby-position:under"><rt>u</rt> <rt>v</rt></rtc></ruby>',
      );
      final request =
          (input.atoms[1] as ForumBodyRubySoftSpaceAtomRequest).value;
      expect(request.members.map((m) => m.annotationIndex), [null, 0]);
      expect(request.sides, [ForumBodyRubySide.over]);
      expect(request.maxWidth, 16384);
      final contexts = request.nativeRequests.map((r) => r.content).toList();
      expect(
        input.content.resolveAtomicContexts(1, contexts).map((w) => w.content),
        orderedEquals(contexts),
      );
      final band =
          (request.nativeRequests.first as ForumBodyTextBandChildRequest).band;
      expect(band.contexts.map((c) => c.projection.text), [
        'A',
        ' ',
        'B',
        'x',
        ' ',
        'y',
      ]);
      input.replaceBand(band, null);
      final mapped =
          (input.atoms[1] as ForumBodyRubySoftSpaceAtomRequest).value;
      expect(
        mapped.nativeRequests.every((r) => r is ForumBodyParagraphTextRequest),
        isTrue,
      );
      expect(
        mapped.nativeRequests.map((r) => r.content),
        orderedEquals(contexts),
      );
    },
  );

  for (final repeat in [false, true]) {
    test(
      'actual gap band failure yields and rebinds only original sources repeat=$repeat',
      () {
        final input = _input(
          '<ruby style="line-height:.25"><rb>A</rb><rb>B</rb><rtc style="line-height:.25"><rt>x</rt> <rt>y</rt></rtc></ruby>',
        );
        final original =
            (input.atoms[1] as ForumBodyRubySoftSpaceAtomRequest).value;
        final band =
            (original.nativeRequests.single as ForumBodyTextBandChildRequest)
                .band;
        void rejectGap() {
          input.atoms[1] = input.atoms[1].mapRequests(
            (r) => ForumBodyTextRequest.bandChild(
              band: band,
              childIndex: (r as ForumBodyTextBandChildRequest).childIndex,
              gutter: 1,
            ),
          );
        }

        rejectGap();
        final cache = ForumBodyParagraphCache(
          maxEntries: 4,
          maxEstimatedBytes: 1 << 24,
        );
        addTearDown(cache.close);
        final prep = ForumBodyInlinePlanPreparation(
          input: input,
          cache: cache,
          textScaler: TextScaler.noScaling,
          ensureOwner: () {},
        );
        addTearDown(prep.close);
        var failed = false;
        for (var i = 0; !failed && i < 1000; i++) {
          final builds = cache.layoutBuildCount;
          final step = prep.advance(maxParts: 1);
          expect(cache.layoutBuildCount - builds, lessThanOrEqualTo(1));
          expect(step.partsPrepared, lessThanOrEqualTo(1));
          final current =
              (input.atoms[1] as ForumBodyRubySoftSpaceAtomRequest).value;
          failed =
              (current.nativeRequests.single as ForumBodyTextBandChildRequest)
                  .gutter! >
              1;
        }
        expect(failed, isTrue);
        expect(cache.activeLeases, 0);
        if (repeat) {
          rejectGap();
          expect(prep.advance(maxParts: 1).partsPrepared, 1);
          expect(
            (input.atoms[1] as ForumBodyRubySoftSpaceAtomRequest)
                .value
                .nativeRequests
                .single,
            isA<ForumBodyParagraphTextRequest>(),
          );
        }
        for (var i = 0; !prep.isReady && i < 1000; i++) {
          final builds = cache.layoutBuildCount;
          prep.advance(maxParts: 7);
          expect(cache.layoutBuildCount - builds, lessThanOrEqualTo(1));
        }
        expect(prep.isReady, isTrue);
        final result = prep.take();
        result.lease.release();
        expect(
          (input.atoms[1] as ForumBodyRubySoftSpaceAtomRequest)
              .value
              .nativeRequests
              .single
              .content,
          same(original.nativeRequests.single.content),
        );
        expect(cache.activeLeases, 0);
      },
    );
  }

  test('an empty LF edge does not renumber a later real original gap', () {
    final input = _input(
      '<ruby><rb>A</rb><rb>B</rb><rb>C</rb><rt>漢</rt>\n<rt>字</rt> <rt>語</rt></ruby>',
    );
    expect(input.atoms.map((a) => a.runtimeType), [
      ForumBodyRubyColumnAtomRequest,
      ForumBodyRubyColumnAtomRequest,
      ForumBodyRubySoftSpaceAtomRequest,
      ForumBodyRubyColumnAtomRequest,
    ]);
    final gap = (input.atoms[2] as ForumBodyRubySoftSpaceAtomRequest).value;
    expect(gap.beforeColumn, 2);
    expect(gap.nativeRequests.single.content.projection.text, ' ');
    final fence = input.content.contexts.singleWhere(
      (w) => !w.content.isSourceFree && w.content.projection.text.isEmpty,
    );
    expect(fence.startUtf16, fence.endUtf16);
  });

  for (final mode in ['pre', 'pre-wrap']) {
    test('preserved $mode annotation gaps are not silently made trimmable', () {
      expect(
        () => _input(
          '<ruby><rb>A</rb><rb>B</rb><rtc style="white-space:$mode"><rt>x</rt> <rt>y</rt></rtc></ruby>',
        ),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
    });
  }

  test('an omitted span leaves implicit base spaces and actual columns', () {
    final input = _input('X<ruby> A <rt>xx</rt><rtc>word</rtc></ruby>Z');
    expect(input.content.projection.display.text, 'X Axx Z');
    expect(input.groups.map((column) => column.base.content.projection.text), [
      'A',
    ]);
    final contexts = [
      for (final (index, column) in input.groups.indexed)
        ...input.content.resolveAtomicContexts(
          index,
          column.nativeRequests.map((r) => r.content).toList(),
        ),
    ];
    expect(contexts.map((c) => c.content.projection.text), ['A', 'xx']);
    for (final window in contexts) {
      if (window.content.isSourceFree) {
        expect(window.startUtf16, window.endUtf16);
        continue;
      }
      final from = window.content.projection.text.length > 1 ? 1 : 0;
      expect(
        input.content.projection.display
            .sourceAtUtf16(window.startUtf16 + from)
            .sourceRune,
        window.content.projection.sourceAtUtf16(from).sourceRune,
      );
    }
  });

  test('structural outer gap omission does not absorb a component source', () {
    final input = _input(
      '<ruby> \n<rb>A</rb><rb>B</rb> \n<rtc>wide</rtc></ruby>',
    );
    expect(input.content.projection.display.text, 'ABwide');
    final request =
        (input.atoms.single as ForumBodyRubySegmentAtomRequest).value;
    final contexts = input.content.resolveAtomicContexts(
      0,
      request.nativeRequests.map((r) => r.content).toList(),
    );
    expect(contexts.map((c) => c.content.projection.text), ['A', 'B', 'wide']);
  });
}
