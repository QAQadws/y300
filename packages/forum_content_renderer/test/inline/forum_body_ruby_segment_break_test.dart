import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_input.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_atom_request.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

final _reader = ForumBodyReaderStyle(
  textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
  fontRevision: 'ahem',
  linkColor: const Color(0xff0000ff),
  paragraphBefore: 0,
  paragraphAfter: 0,
);

ForumBodyInlinePlanInput _input(String html, {double width = 100}) {
  final flow = ForumBodyTextFlowCursor(
    document: const ForumBodyParser().parse(
      html: html,
      sourceId: 'actual-segment-break',
      conversionIdentity: 'none',
    ),
    reader: _reader,
  );
  try {
    while (!flow.isComplete) {
      flow.advance(maxEvents: 1);
      if (flow.current case ForumBodyTextFlowInline(:final content)) {
        return ForumBodyInlinePlanInput(content, width);
      }
    }
    throw StateError('Fixture has no inline');
  } finally {
    flow.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'one discarded break does not shift the next real gap or its original span',
    () {
      final input = _input(
        '<ruby><rb>A</rb><rb>B</rb><rb>C</rb><rt>漢</rt>\n<rt>字</rt> <rt>語</rt><rtc>whole</rtc></ruby>',
      );
      final columns = input.atoms.whereType<ForumBodyRubyColumnAtomRequest>();
      expect(columns, hasLength(3));
      expect(columns.last.value.base.content.projection.text, 'C');
      final gap = input.atoms
          .whereType<ForumBodyRubySoftSpaceAtomRequest>()
          .single;
      expect(gap.value.beforeColumn, 2);
      expect(gap.value.members.single.request.content.projection.text, ' ');
      expect(input.content.projection.display.text, 'A漢B字 C語');
      input.content.resolveAtomicContexts(
        input.atoms.indexOf(gap),
        gap.value.nativeRequests.map((r) => r.content).toList(),
      );
    },
  );
  for (final root in [false, true]) {
    for (final (left, right, space, mode, expected) in [
      ('漢', '字', '\n', 'normal', ''),
      ('漢', 'か', ' \r\n\t ', 'normal', ''),
      ('ば', 'カ', '\n', 'normal', ''),
      ('𠀀', '字', '\n', 'normal', ''),
      ('漢、', 'か', '\n', 'normal', ''),
      ('漢️', '字', '\n', 'normal', ''),
      ('漢', '字', ' ', 'normal', ' '),
      ('x', 'y', '\n', 'normal', ' '),
      ('漢', 'y', '\n', 'normal', ' '),
      ('한', '글', '\n', 'normal', ' '),
      ('漢', '字', '\n', 'pre', ''),
      ('漢', '字', ' \n ', 'pre', '   '),
      ('漢', '字', '\n', 'pre-line', ''),
      ('', '字', '\n', 'normal', ' '),
      ('漢', '', '\n', 'normal', ' '),
      ('漢', '゙', '\n', 'normal', ' '),
    ]) {
      test(
        'actual gap context keeps authored spacing root=$root ($left,$right,$mode,$space)',
        () {
          final annotations = '<rt>$left</rt>$space<rt>$right</rt>';
          final html =
              '<ruby style="white-space:$mode"><rb>A</rb><rb>B</rb>${root ? annotations : '<rtc>$annotations</rtc>'}<rtc>whole</rtc></ruby>';
          if (mode == 'pre' && expected.isNotEmpty) {
            expect(
              () => _input(html),
              throwsA(isA<ForumBodyParagraphInputException>()),
            );
            return;
          }
          final input = _input(html);
          final gaps = input.atoms
              .whereType<ForumBodyRubySoftSpaceAtomRequest>()
              .toList();
          expect(
            gaps
                .map(
                  (g) => g.value.members.single.request.content.projection.text,
                )
                .join(),
            expected,
          );
          expect(gaps.length, expected.isEmpty ? 0 : 1);
          expect(
            input.atoms.whereType<ForumBodyRubyColumnAtomRequest>(),
            hasLength(2),
          );
          if (expected.isEmpty) {
            final fence = input.content.contexts.singleWhere(
              (w) => w.content.projection.text.isEmpty,
            );
            expect(fence.content.isSourceFree, isFalse);
            expect(fence.content.projection.sourceAtUtf16(0).isExact, isFalse);
            expect(
              fence.content.projection
                  .sourceAtUtf16(0, affinity: HtmlProjectionAffinity.upstream)
                  .sourceRune,
              2 + left.runes.length,
            );
            expect(
              fence.content.projection.sourceAtUtf16(0).sourceRune,
              2 +
                  left.runes.length +
                  space.replaceAll('\r\n', '\n').runes.length,
            );
          }
        },
      );
    }
  }

  for (final root in [false, true]) {
    for (final rtl in [false, true]) {
      test(
        'collapsed gap permits original columns to break with source fences and bounded ownership root=$root rtl=$rtl',
        () {
          final annotations = '<rt>漢</rt>\n<rt>字</rt>';
          final html =
              '<p dir="${rtl ? 'rtl' : 'ltr'}"><ruby><rb>A</rb><rb>B</rb>${root ? annotations : '<rtc>$annotations</rtc>'}</ruby></p>';
          final input = _input(html, width: 20);
          expect(input.atoms.length, 2);
          final document = const ForumBodyParser().parse(
            html: html,
            sourceId: 'actual-segment-break',
            conversionIdentity: 'none',
          );
          final cache = ForumBodyParagraphCache(
            maxEntries: 4,
            maxEstimatedBytes: 1 << 20,
          );
          final session = ForumBodyTextPageSession(
            limits: const ForumBodyTextPageSessionLimits(
              maxPages: 100,
              maxFragments: 100,
              maxParagraphs: 100,
              maxTextCodeUnits: 10000,
              maxRuns: 512,
              maxIssuedLeases: 64,
            ),
            document: document,
            reader: _reader,
            cache: cache,
            layoutId: 'actual-cjk-break',
            width: 20,
            height: 30,
          );
          try {
            for (var i = 0; !session.isComplete && i < 10000; i++) {
              final shapes = cache.layoutBuildCount;
              final step = session.advance(maxEvents: 1, maxLines: 1);
              expect(step.formatUnitsPrepared, lessThanOrEqualTo(32));
              expect(cache.layoutBuildCount - shapes, lessThanOrEqualTo(1));
              expect(step.madeProgress, isTrue);
            }
            expect(session.isComplete, isTrue);
            expect(session.snapshot.length, 2);
            var hits = 0;
            for (var page = 0; page < 2; page++) {
              final job = session.openPagePreparation(page);
              final fragments = <ForumBodyPreparedTextFragment>[];
              try {
                for (var i = 0; !job.isReady && i < 10000; i++) {
                  final counts = (
                    cache.layoutBuildCount,
                    cache.pictureBuildCount,
                  );
                  final step = job.advance(maxFragments: 1, maxParts: 1);
                  expect(
                    step.partsPrepared + step.partsInspected,
                    lessThanOrEqualTo(1),
                  );
                  expect(
                    cache.layoutBuildCount -
                        counts.$1 +
                        cache.pictureBuildCount -
                        counts.$2,
                    lessThanOrEqualTo(1),
                  );
                  expect(step.waitingForLayoutBudget, isFalse);
                }
                expect(job.isReady, isTrue);
                fragments.addAll(job.takeFragments());
                final f = fragments.single as ForumBodyPreparedInlineFragment;
                expect(f.nativeLeases.length, 3);
                for (final child
                    in f.nativeLeases.whereType<ForumBodyTextLease>()) {
                  final w = f.view.content.contexts.singleWhere(
                    (w) => identical(w.content, child.content),
                  );
                  final box = f.glyphBoxes(w.startUtf16, w.endUtf16).single;
                  final hit = f.view.sourceAt(
                    Offset(
                      box.direction == TextDirection.rtl
                          ? box.right - .001
                          : box.left + .001,
                      (box.top + box.bottom) / 2,
                    ),
                  );
                  expect(
                    hit.sourceRune,
                    child.content.projection.sourceAtUtf16(0).sourceRune,
                  );
                  // Reordered column text and the omitted LF leave genuine
                  // discontinuities. A native insertion at those joins cannot
                  // turn their source fence into an exact semantic coordinate.
                  expect(hit.isExact, child.content.projection.text == 'A');
                  hits++;
                }
              } finally {
                for (final f in fragments) {
                  f.close();
                }
                job.close();
              }
              expect(session.activeIssuedLeases, 0);
              expect(cache.activeLeases, 0);
            }
            expect(hits, 4);
          } finally {
            session.close();
            cache.close();
          }
          expect(cache.estimatedRetainedBytes, 0);
        },
      );
    }
  }
}
