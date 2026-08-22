import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_settings.dart';
import 'package:y300/features/thread/domain/models/thread_post_render_cache_key.dart';
import 'package:y300/features/thread/domain/models/thread_post_segmentation_config.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_preparer.dart';
import 'forum_html_test_theme.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_html_first_image_diagnostics_service.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_html_image_reader_bridge.dart';

void main() {
  group('ThreadHtmlFirstImageDiagnosticsService', () {
    const preparer = DefaultForumHtmlRenderPreparer();
    const service = ThreadHtmlFirstImageDiagnosticsService();

    test('reports prepare counters and legacy sequence diff', () {
      final prepared = preparer.prepare(
        html:
            '<img id="aimg_1" src="data/attachment/forum/page-1.jpg">'
            '<img src="https://example.com/repeat.jpg">'
            '<img src="https://example.com/repeat.jpg">'
            '<img src="static/image/smiley/comcom/2.gif">'
            '<img src="data:image/png;base64,abc">',
        preferences: ForumHtmlReaderPreferences.defaults(),
        theme: forumHtmlTestTheme,
        sourceId: 'p1',
        threadId: '100',
        imageCacheOwnerId: '100',
      );
      final legacyPlan = _planWithImages(<ThreadPostImageBlock>[
        RichImageBlock(
          url: 'https://bbs.yamibo.com/data/attachment/forum/page-1.jpg',
          rawUrl: 'data/attachment/forum/page-1.jpg',
          index: 0,
          aid: '1',
        ),
        const RichImageBlock(
          url: 'https://bbs.yamibo.com/data/attachment/forum/legacy-only.jpg',
          rawUrl: 'data/attachment/forum/legacy-only.jpg',
          index: 1,
        ),
      ]);

      final report = service.buildReport(
        post: _post,
        legacyPlan: legacyPlan,
        preparedDocument: prepared,
      );

      expect(report.totalImageCount, 5);
      expect(report.readableImageCount, 3);
      expect(report.skippedStickerCount, 1);
      expect(report.skippedNonNetworkCount, 1);
      expect(report.duplicatedReadableUrlCount, 1);
      expect(report.attachmentTaggedCount, 1);
      expect(report.sequenceDiff.matchedAttachmentIds, <String>['1']);
      expect(report.sequenceDiff.matchedUrls, hasLength(1));
      expect(report.sequenceDiff.missingFromHtmlFirst, hasLength(1));
      expect(report.sequenceDiff.extraInHtmlFirst, hasLength(1));
    });

    test('summarizes image tap fallback reasons', () {
      final prepared = preparer.prepare(
        html: '<img src="data/attachment/forum/page-1.jpg">',
        preferences: ForumHtmlReaderPreferences.defaults(),
        theme: forumHtmlTestTheme,
        sourceId: 'p1',
        threadId: '100',
        imageCacheOwnerId: '100',
      );

      final report = service.buildReport(
        post: _post,
        legacyPlan: _planWithImages(const <ThreadPostImageBlock>[]),
        preparedDocument: prepared,
        lastImageRequest: const ForumHtmlImageRequest(
          url: 'https://bbs.yamibo.com/static/image/smiley/comcom/2.gif',
          isSticker: true,
        ),
        lastBridgeResult: const ThreadHtmlImageReaderBridgeResult.fallback(
          ThreadHtmlImageReaderBridgeFailureReason.sticker,
        ),
      );

      expect(
        report.lastFailureReason,
        ThreadHtmlImageReaderBridgeFailureReason.sticker,
      );
      expect(report.failureBreakdownText, contains('表情已忽略'));
    });
  });
}

ThreadPostBodyRenderPlan _planWithImages(List<ThreadPostImageBlock> images) {
  return ThreadPostBodyRenderPlan(
    document: RichDocument(blocks: images),
    displayDocument: RichDocument(blocks: images),
    images: images,
    segments: const <ThreadPostBodySegment>[],
    usesListSegments: false,
    renderKey: const ThreadPostRenderCacheKey(
      renderSettings: ThreadPostBodyRenderSettings.defaults,
      displayTransformerSignature: 'default',
      resourceHintResolverSignature: 'default',
      segmentation: ThreadPostSegmentationConfig.standard,
    ),
  );
}

final _post = ThreadPost(
  pid: 'p1',
  author: 'alice',
  authorId: '1',
  message: '<p>正文</p>',
  number: 1,
  isFirst: true,
  dateline: 'today',
);
