import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_input.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_preparation.dart';

ForumBodyInlinePlanInput _input() {
  final document = const ForumBodyParser().parse(
    html:
        '<ruby style="line-height:.25">AB<rt style="line-height:.25">xy</rt></ruby>',
    sourceId: 'native-plan-isolation',
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
        return ForumBodyInlinePlanInput(content, 100);
      }
    }
    throw StateError('No mixed context');
  } finally {
    flow.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final rejectRetry in [false, true]) {
    test(
      'native isolation yields before retry, repeated rejection=$rejectRetry',
      () {
        final input = _input();
        final band =
            (input.groups.single.base as ForumBodyTextBandChildRequest).band;
        input.replaceBand(band, 1);
        final cache = ForumBodyParagraphCache(
          maxEntries: 4,
          maxEstimatedBytes: 1 << 22,
        );
        addTearDown(cache.close);
        final prepare = ForumBodyInlinePlanPreparation(
          input: input,
          cache: cache,
          textScaler: TextScaler.noScaling,
          ensureOwner: () {},
        );
        addTearDown(prepare.close);
        // Root font capture is an independent native quantum and retains no
        // lease. Its numeric result must survive eviction before band retry.
        expect(prepare.advance(maxParts: 1).partsPrepared, 1);
        expect(cache.activeLeases, 0);
        cache.clearUnpinned();
        final rejected = prepare.advance();
        expect(rejected.partsPrepared, 1);
        expect(rejected.isReady, isFalse);
        expect(rejected.waitingForLayoutBudget, isFalse);
        // A retry must not shape again in the same unit or leave failed glyphs.
        expect(cache.entryCount, 0);
        expect(cache.activeLeases, 0);
        final request =
            input.groups.single.base as ForumBodyTextBandChildRequest;
        expect(request.gutter, greaterThan(1));
        expect(
          (input.groups.single.annotation as ForumBodyTextBandChildRequest)
              .gutter,
          request.gutter,
        );
        if (rejectRetry) {
          // Reproduce a second native isolation rejection under the same band
          // identity; the bounded retry policy must retire it to native children.
          input.replaceBand(band, 1);
          final again = prepare.advance();
          expect(again.partsPrepared, 1);
          expect(cache.entryCount, 0);
          expect(cache.activeLeases, 0);
          expect(
            input.groups.single.base,
            isA<ForumBodyParagraphTextRequest>(),
          );
          expect(
            input.groups.single.annotation,
            isA<ForumBodyParagraphTextRequest>(),
          );
        }
        for (var i = 0; !prepare.isReady && i < 20; i++) {
          final builds = cache.layoutBuildCount;
          final step = prepare.advance();
          expect(cache.layoutBuildCount - builds, lessThanOrEqualTo(1));
          expect(step.partsPrepared, greaterThan(0));
          expect(cache.pictureBuildCount, 0);
        }
        expect(prepare.isReady, isTrue);
        final result = prepare.take();
        try {
          expect(result.content.dimensions.single.size, const Size(40, 30));
          expect(
            result.content.rubyGroups.single.base.content,
            same(input.groups.single.base.content),
          );
          expect(result.lease.layout.atomBoxes, hasLength(1));
          expect(cache.activeLeases, 1);
        } finally {
          result.lease.release();
        }
        expect(cache.activeLeases, 0);
        cache.clearUnpinned();
        expect(cache.estimatedRetainedBytes, 0);
      },
    );
  }
}
