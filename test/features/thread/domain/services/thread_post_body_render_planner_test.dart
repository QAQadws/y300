import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/rich_text/document/rich_document.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_settings.dart';
import 'package:y300/features/thread/domain/models/thread_post_resource_layout_hints.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_display_transformer.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_render_planner.dart';
import 'package:y300/features/thread/domain/services/thread_post_resource_layout_hint_resolver.dart';

void main() {
  group('ThreadPostBodyRenderPlanner', () {
    test('splits text bodies around the configured text length', () {
      const planner = ThreadPostBodyRenderPlanner(maxSegmentTextLength: 6);
      const document = RichDocument(
        blocks: <RichBlock>[
          RichTextBlock(runs: <RichRun>[RichRun(text: 'abcdef')]),
          RichTextBlock(runs: <RichRun>[RichRun(text: 'ghijkl')]),
          RichTextBlock(runs: <RichRun>[RichRun(text: 'mnop')]),
        ],
      );

      final plan = planner.planDocument(document);

      expect(plan.usesListSegments, isTrue);
      expect(plan.segments, hasLength(3));
      expect(
        plan.segments.map((segment) {
          return segment.blocks
              .whereType<RichTextBlock>()
              .map((block) => block.plainText)
              .join();
        }),
        <String>['abcdef', 'ghijkl', 'mnop'],
      );
      expect(
        plan.segments
            .expand((segment) => segment.blocks)
            .whereType<RichTextBlock>()
            .map((block) => block.plainText)
            .join(),
        'abcdefghijklmnop',
      );
    });

    test('keeps image blocks as standalone segments', () {
      const planner = ThreadPostBodyRenderPlanner(maxSegmentTextLength: 900);
      const firstImage = RichImageBlock(
        url: 'https://bbs.yamibo.com/a.jpg',
        rawUrl: 'a.jpg',
        index: 0,
      );
      const secondImage = RichImageBlock(
        url: 'https://bbs.yamibo.com/b.jpg',
        rawUrl: 'b.jpg',
        index: 1,
      );
      const document = RichDocument(
        blocks: <RichBlock>[
          RichTextBlock(runs: <RichRun>[RichRun(text: '前文')]),
          firstImage,
          RichTextBlock(runs: <RichRun>[RichRun(text: '后文')]),
          secondImage,
        ],
      );

      final plan = planner.planDocument(document);

      expect(plan.usesListSegments, isTrue);
      expect(plan.images, <RichImageBlock>[firstImage, secondImage]);
      expect(plan.segments, hasLength(4));
      expect(plan.segments[1].blocks, <RichBlock>[firstImage]);
      expect(plan.segments[3].blocks, <RichBlock>[secondImage]);
      expect(
        plan.resourceLayoutHints.blockImage(firstImage)?.source,
        ThreadPostResourceLayoutHintSource.contentDefault,
      );
    });

    test('adds resource layout hints to render plans', () {
      const planner = ThreadPostBodyRenderPlanner();
      const image = RichImageBlock(
        url: 'https://bbs.yamibo.com/a.jpg',
        rawUrl: 'a.jpg',
        index: 0,
        originalWidth: 1200,
        originalHeight: 800,
      );
      const inlineImage = RichInlineImage(
        url: 'https://bbs.yamibo.com/static/image/smiley/comcom/2.gif',
        rawUrl: 'static/image/smiley/comcom/2.gif',
        originalWidth: 28,
        originalHeight: 20,
      );
      const document = RichDocument(
        blocks: <RichBlock>[
          image,
          RichTextBlock(
            runs: <RichRun>[RichRun(text: '', inlineImage: inlineImage)],
          ),
        ],
      );

      final plan = planner.planDocument(document);

      expect(plan.resourceLayoutHints.blockImage(image)?.aspectRatio, 1.5);
      expect(plan.resourceLayoutHints.inlineImage(inlineImage)?.width, 28);
      expect(plan.resourceLayoutHints.inlineImage(inlineImage)?.height, 20);
    });

    test('records render settings and resource hint signatures', () {
      const planner = ThreadPostBodyRenderPlanner(
        resourceLayoutHintResolver: ThreadPostResourceLayoutHintResolver(
          defaultBlockImageAspectRatio: 1.0,
          lockForCurrentBuild: true,
        ),
      );
      const document = RichDocument(
        blocks: <RichBlock>[
          RichImageBlock(
            url: 'https://bbs.yamibo.com/a.jpg',
            rawUrl: 'a.jpg',
            index: 0,
          ),
        ],
      );
      final settings = ThreadPostBodyRenderSettings.defaults.copyWith(
        fontSize: 20,
      );

      final plan = planner.planDocument(document, renderSettings: settings);

      expect(plan.renderSettingsSignature, settings.signature);
      expect(
        plan.resourceHintResolverSignature,
        planner.resourceHintResolverSignature,
      );
      expect(plan.resourceHintSignature, plan.resourceLayoutHints.signature);
    });

    test('keeps source document separate from display document', () {
      const planner = ThreadPostBodyRenderPlanner(
        displayTransformer: ThreadPostBodyDisplayTransformer(
          textTransformer: _replaceOriginalText,
          signature: 'replace-original-text',
        ),
      );
      const document = RichDocument(
        blocks: <RichBlock>[
          RichTextBlock(
            runs: <RichRun>[
              RichRun(text: '原文'),
              RichRun(
                text: '',
                inlineImage: RichInlineImage(
                  url: 'https://bbs.yamibo.com/static/image/smiley/a.gif',
                  rawUrl: 'static/image/smiley/a.gif',
                  altText: '[笑]',
                ),
              ),
            ],
          ),
        ],
      );

      final plan = planner.planDocument(document);
      final sourceBlock = plan.document.blocks.single as RichTextBlock;
      final displayBlock = plan.displayDocument.blocks.single as RichTextBlock;
      final segmentBlock = plan.segments.single.blocks.single as RichTextBlock;

      expect(sourceBlock.plainText, '原文');
      expect(displayBlock.plainText, '显示文');
      expect(segmentBlock.plainText, '显示文');
      expect(identical(sourceBlock.runs.last, displayBlock.runs.last), isTrue);
      expect(plan.displayTransformerSignature, 'replace-original-text');
    });

    test('keeps quote blocks intact', () {
      const planner = ThreadPostBodyRenderPlanner(maxSegmentTextLength: 4);
      const quote = RichQuoteBlock(
        blocks: <RichBlock>[
          RichTextBlock(runs: <RichRun>[RichRun(text: 'quoted text')]),
        ],
      );
      const document = RichDocument(
        blocks: <RichBlock>[
          RichTextBlock(runs: <RichRun>[RichRun(text: 'lead')]),
          quote,
          RichTextBlock(runs: <RichRun>[RichRun(text: 'tail')]),
        ],
      );

      final plan = planner.planDocument(document);

      expect(plan.usesListSegments, isTrue);
      expect(plan.segments, hasLength(3));
      expect(plan.segments[1].blocks, <RichBlock>[quote]);
    });

    test('short body still creates one segment', () {
      const planner = ThreadPostBodyRenderPlanner();
      const document = RichDocument(
        blocks: <RichBlock>[
          RichTextBlock(runs: <RichRun>[RichRun(text: '短正文')]),
        ],
      );

      final plan = planner.planDocument(document);

      expect(plan.usesListSegments, isFalse);
      expect(plan.segments, hasLength(1));
      expect(plan.segments.single.blocks, document.blocks);
    });

    test('defaults to roughly 600 text characters per segment', () {
      const planner = ThreadPostBodyRenderPlanner();
      final document = RichDocument(
        blocks: <RichBlock>[
          RichTextBlock(
            runs: <RichRun>[RichRun(text: List.filled(600, 'a').join())],
          ),
          const RichTextBlock(runs: <RichRun>[RichRun(text: 'b')]),
        ],
      );

      final plan = planner.planDocument(document);

      expect(plan.usesListSegments, isTrue);
      expect(plan.segments, hasLength(2));
      expect(
        plan.segments.first.blocks.single,
        isA<RichTextBlock>().having(
          (block) => block.plainText.length,
          'length',
          600,
        ),
      );
    });
  });
}

String _replaceOriginalText(String text) {
  return text.replaceAll('原文', '显示文');
}
