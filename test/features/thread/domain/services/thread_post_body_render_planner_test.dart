import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_render_planner.dart';

void main() {
  group('ThreadPostBodyRenderPlanner', () {
    test('splits text bodies around the configured text length', () {
      const planner = ThreadPostBodyRenderPlanner(maxSegmentTextLength: 6);
      const document = ThreadPostBodyDocument(
        blocks: <ThreadPostBodyBlock>[
          ThreadPostTextBlock(
            runs: <ThreadPostTextRun>[ThreadPostTextRun(text: 'abcdef')],
          ),
          ThreadPostTextBlock(
            runs: <ThreadPostTextRun>[ThreadPostTextRun(text: 'ghijkl')],
          ),
          ThreadPostTextBlock(
            runs: <ThreadPostTextRun>[ThreadPostTextRun(text: 'mnop')],
          ),
        ],
      );

      final plan = planner.planDocument(document);

      expect(plan.usesListSegments, isTrue);
      expect(plan.segments, hasLength(3));
      expect(
        plan.segments.map((segment) {
          return segment.blocks
              .whereType<ThreadPostTextBlock>()
              .map((block) => block.plainText)
              .join();
        }),
        <String>['abcdef', 'ghijkl', 'mnop'],
      );
      expect(
        plan.segments
            .expand((segment) => segment.blocks)
            .whereType<ThreadPostTextBlock>()
            .map((block) => block.plainText)
            .join(),
        'abcdefghijklmnop',
      );
    });

    test('keeps image blocks as standalone segments', () {
      const planner = ThreadPostBodyRenderPlanner(maxSegmentTextLength: 900);
      const firstImage = ThreadPostImageBlock(
        url: 'https://bbs.yamibo.com/a.jpg',
        rawUrl: 'a.jpg',
        index: 0,
      );
      const secondImage = ThreadPostImageBlock(
        url: 'https://bbs.yamibo.com/b.jpg',
        rawUrl: 'b.jpg',
        index: 1,
      );
      const document = ThreadPostBodyDocument(
        blocks: <ThreadPostBodyBlock>[
          ThreadPostTextBlock(
            runs: <ThreadPostTextRun>[ThreadPostTextRun(text: '前文')],
          ),
          firstImage,
          ThreadPostTextBlock(
            runs: <ThreadPostTextRun>[ThreadPostTextRun(text: '后文')],
          ),
          secondImage,
        ],
      );

      final plan = planner.planDocument(document);

      expect(plan.usesListSegments, isTrue);
      expect(plan.images, <ThreadPostImageBlock>[firstImage, secondImage]);
      expect(plan.segments, hasLength(4));
      expect(plan.segments[1].blocks, <ThreadPostBodyBlock>[firstImage]);
      expect(plan.segments[3].blocks, <ThreadPostBodyBlock>[secondImage]);
    });

    test('keeps quote blocks intact', () {
      const planner = ThreadPostBodyRenderPlanner(maxSegmentTextLength: 4);
      const quote = ThreadPostQuoteBlock(
        blocks: <ThreadPostBodyBlock>[
          ThreadPostTextBlock(
            runs: <ThreadPostTextRun>[ThreadPostTextRun(text: 'quoted text')],
          ),
        ],
      );
      const document = ThreadPostBodyDocument(
        blocks: <ThreadPostBodyBlock>[
          ThreadPostTextBlock(
            runs: <ThreadPostTextRun>[ThreadPostTextRun(text: 'lead')],
          ),
          quote,
          ThreadPostTextBlock(
            runs: <ThreadPostTextRun>[ThreadPostTextRun(text: 'tail')],
          ),
        ],
      );

      final plan = planner.planDocument(document);

      expect(plan.usesListSegments, isTrue);
      expect(plan.segments, hasLength(3));
      expect(plan.segments[1].blocks, <ThreadPostBodyBlock>[quote]);
    });

    test('short body still creates one segment', () {
      const planner = ThreadPostBodyRenderPlanner();
      const document = ThreadPostBodyDocument(
        blocks: <ThreadPostBodyBlock>[
          ThreadPostTextBlock(
            runs: <ThreadPostTextRun>[ThreadPostTextRun(text: '短正文')],
          ),
        ],
      );

      final plan = planner.planDocument(document);

      expect(plan.usesListSegments, isFalse);
      expect(plan.segments, hasLength(1));
      expect(plan.segments.single.blocks, document.blocks);
    });

    test('defaults to roughly 600 text characters per segment', () {
      const planner = ThreadPostBodyRenderPlanner();
      final document = ThreadPostBodyDocument(
        blocks: <ThreadPostBodyBlock>[
          ThreadPostTextBlock(
            runs: <ThreadPostTextRun>[
              ThreadPostTextRun(text: List.filled(600, 'a').join()),
            ],
          ),
          const ThreadPostTextBlock(
            runs: <ThreadPostTextRun>[ThreadPostTextRun(text: 'b')],
          ),
        ],
      );

      final plan = planner.planDocument(document);

      expect(plan.usesListSegments, isTrue);
      expect(plan.segments, hasLength(2));
      expect(
        plan.segments.first.blocks.single,
        isA<ThreadPostTextBlock>().having(
          (block) => block.plainText.length,
          'length',
          600,
        ),
      );
    });
  });
}
