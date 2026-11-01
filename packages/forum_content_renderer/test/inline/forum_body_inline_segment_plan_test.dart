import 'package:flutter/painting.dart';
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
  test(
    'raw span is one original source-bound atom, alongside its actual column RTs',
    () {
      final input = _input(
        '<ruby><rb>A</rb><rb>B</rb><rtc><rt>x</rt></rtc><rtc>word</rtc></ruby>',
      );
      expect(input.content.projection.display.text, 'ABxword');
      expect(input.content.projection.atoms.length, 1);
      expect(() => input.groups, throwsStateError);
      final request =
          (input.atoms.single as ForumBodyRubySegmentAtomRequest).value;
      expect(request.bases.map((b) => b.content.projection.text), ['A', 'B']);
      expect(
        request.spans.map(
          (s) => (s.startColumn, s.endColumn, s.annotationIndex),
        ),
        [(0, 1, 0), (0, 2, 1)],
      );
      expect(request.nativeHandleCount, 4);
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
    },
  );

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

  test(
    'annotation gap keeps actual neighbouring span index inside a true spanning closure',
    () {
      final input = _input(
        '<ruby><rb>A</rb> <rb>B</rb><rtc><rt>x</rt> <rt>y</rt></rtc><rtc>whole</rtc></ruby>',
      );
      final request =
          (input.atoms.single as ForumBodyRubySegmentAtomRequest).value;
      expect(request.annotationGaps.single.beforeSpanIndex, 1);
      expect(request.nativeRequests.map((r) => r.content.projection.text), [
        'A',
        ' ',
        'B',
        'x',
        ' ',
        'y',
        'whole',
      ]);
      expect(request.bases.length, 2);
      expect(request.spans.length, 3);
      input.content.resolveAtomicContexts(
        0,
        request.nativeRequests.map((r) => r.content).toList(),
      );
      final band = (request.bases.first as ForumBodyTextBandChildRequest).band;
      input.replaceBand(band, 123);
      final mapped =
          (input.atoms.single as ForumBodyRubySegmentAtomRequest).value;
      expect(
        (mapped.annotationGaps.single.request as ForumBodyTextBandChildRequest)
            .gutter,
        123,
      );
      expect(
        mapped.annotationGaps.single.request.content,
        same(request.annotationGaps.single.request.content),
      );
      expect(mapped.annotationGaps.single.beforeSpanIndex, 1);
    },
  );

  for (final outer in ['', '<rtc> </rtc>']) {
    test(
      'a gap does not fuse otherwise breakable columns even with an empty outer box: $outer',
      () {
        expect(
          () => _input(
            '<ruby><rb>A</rb><rb>B</rb><rtc><rt>x</rt> <rt>y</rt></rtc>$outer</ruby>',
          ),
          throwsA(isA<ForumBodyParagraphInputException>()),
        );
      },
    );
  }

  test(
    'a direct RT gap does not silently disappear or fuse breakable columns',
    () {
      expect(
        () => _input('<ruby><rb>A</rb><rb>B</rb><rt>x</rt> <rt>y</rt></ruby>'),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
    },
  );

  test(
    'implicit spanning base keeps real outer spaces and anonymous excess base',
    () {
      final input = _input(
        'X<ruby> A <rt>xx</rt><rt>yy</rt><rtc>word</rtc></ruby>Z',
      );
      expect(input.content.projection.display.text, 'X Axxyyword Z');
      final request =
          (input.atoms.single as ForumBodyRubySegmentAtomRequest).value;
      expect(request.bases.map((b) => b.content.projection.text), ['A', '']);
      expect(request.bases.last.content.isSourceFree, isTrue);
      expect(request.spans.map((s) => (s.startColumn, s.endColumn)), [
        (0, 1),
        (1, 2),
        (0, 2),
      ]);
      final contexts = input.content.resolveAtomicContexts(
        0,
        request.nativeRequests.map((r) => r.content).toList(),
      );
      expect(contexts.map((c) => c.content.projection.text), [
        'A',
        '',
        'xx',
        'yy',
        'word',
      ]);
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
    },
  );

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
