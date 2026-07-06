import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_settings.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';
import 'package:y300/features/thread/domain/models/thread_post_render_cache_key.dart';
import 'package:y300/features/thread/domain/models/thread_post_resource_layout_hints.dart';
import 'package:y300/features/thread/domain/models/thread_post_segmentation_config.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_preparer.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_html_image_reader_bridge.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';

void main() {
  group('DefaultForumHtmlRenderPreparer', () {
    const preparer = DefaultForumHtmlRenderPreparer();

    test('collects readable images in DOM order and annotates indices', () {
      final prepared = preparer.prepare(
        html:
            '<p>正文</p>'
            '<img id="aimg_123" src="data/attachment/forum/page-1.jpg" '
            'width="640" height="480" alt="一">'
            '<img src="data/attachment/forum/page-2.jpg" alt="二">',
        preferences: ForumHtmlReaderPreferences.defaults(),
        sourceId: 'p1',
        threadId: '100',
        imageCacheOwnerId: '100',
      );

      final images = html_parser
          .parseFragment(prepared.preparedHtml)
          .querySelectorAll('img');

      expect(prepared.sequence.entries, hasLength(2));
      expect(prepared.sequence.entries.first.index, 0);
      expect(prepared.sequence.entries.first.attachmentId, '123');
      expect(prepared.sequence.entries.first.htmlWidth, 640);
      expect(prepared.sequence.entries.first.htmlHeight, 480);
      expect(prepared.sequence.entries.last.index, 1);
      expect(
        images.map(
          (image) => image.attributes[forumHtmlReadableImageIndexAttribute],
        ),
        <String?>['0', '1'],
      );
    });

    test('skips stickers, non-network images, and invalid image sources', () {
      final prepared = preparer.prepare(
        html:
            '<img src="static/image/smiley/comcom/2.gif">'
            '<img src="data:image/png;base64,abc">'
            '<img src="">'
            '<img src="data/attachment/forum/page-1.jpg">',
        preferences: ForumHtmlReaderPreferences.defaults(),
        sourceId: 'p1',
        threadId: '100',
        imageCacheOwnerId: '100',
      );

      expect(prepared.sequence.entries, hasLength(1));
      expect(prepared.skippedStickerCount, 1);
      expect(prepared.skippedNonNetworkCount, 2);
    });

    test('keeps repeated real image references as separate reader entries', () {
      final prepared = preparer.prepare(
        html:
            '<img src="https://example.com/images/page-1.jpg">'
            '<img src="https://example.com/images/page-1.jpg">',
        preferences: ForumHtmlReaderPreferences.defaults(),
        sourceId: 'p1',
        threadId: '100',
        imageCacheOwnerId: '100',
      );

      expect(prepared.sequence.entries, hasLength(2));
      expect(
        prepared.sequence.entries[0].url,
        prepared.sequence.entries[1].url,
      );
      expect(prepared.sequence.entries[0].index, 0);
      expect(prepared.sequence.entries[1].index, 1);
    });

    test('keeps collapse content images on the same global sequence', () {
      final prepared = preparer.prepare(
        html:
            '<img src="data/attachment/forum/page-1.jpg">'
            '<div class="showcollapse_box">'
            '<div class="showcollapse_title">目录</div>'
            '<div class="showcollapse_content">'
            '<img src="data/attachment/forum/page-2.jpg">'
            '</div>'
            '</div>',
        preferences: ForumHtmlReaderPreferences.defaults(),
        sourceId: 'p1',
        threadId: '100',
        imageCacheOwnerId: '100',
      );

      final images = html_parser
          .parseFragment(prepared.preparedHtml)
          .querySelectorAll('img');

      expect(prepared.sequence.entries.map((entry) => entry.index), <int>[
        0,
        1,
      ]);
      expect(
        images.map(
          (image) => image.attributes[forumHtmlReadableImageIndexAttribute],
        ),
        <String?>['0', '1'],
      );
    });
  });

  group('ThreadHtmlImageReaderBridge', () {
    const bridge = ThreadHtmlImageReaderBridge();

    test('opens the readable image selected by index', () {
      final prepared = _prepared(
        '<img src="data/attachment/forum/page-1.jpg">'
        '<img src="data/attachment/forum/page-2.jpg">',
      );

      final result = bridge.buildOpenRequest(
        post: _post,
        threadId: '100',
        imageReferer: 'https://bbs.yamibo.com/thread-100-1-1.html',
        legacyPlan: _emptyPlan,
        sequence: prepared.sequence,
        imageRequest: ForumHtmlImageRequest(
          url: prepared.sequence.entries[1].url,
          readableIndex: 1,
        ),
      );

      expect(result.canOpen, isTrue);
      expect(result.request!.initialIndex, 1);
      expect(result.request!.image.url, endsWith('/page-2.jpg'));
      expect(result.request!.readerRequest!.initialIndex, 1);
      expect(result.request!.readerRequest!.continuousImages, hasLength(2));
    });

    test('falls back to attachment and URL matching when index is absent', () {
      final prepared = _prepared(
        '<img id="aimg_99" src="data/attachment/forum/page-1.jpg">'
        '<img src="data/attachment/forum/page-2.jpg">',
      );

      final result = bridge.buildOpenRequest(
        post: _post,
        threadId: '100',
        imageReferer: 'https://bbs.yamibo.com/thread-100-1-1.html',
        legacyPlan: _planWithLegacyImage(
          aid: '99',
          url: prepared.sequence.entries.first.url,
        ),
        sequence: prepared.sequence,
        imageRequest: ForumHtmlImageRequest(
          url: 'https://bbs.yamibo.com/data/attachment/forum/page-1.jpg',
          attachmentId: '99',
        ),
      );

      expect(result.canOpen, isTrue);
      expect(result.request!.initialIndex, 0);
    });

    test('returns fallback for stickers or unmatched images', () {
      final prepared = _prepared(
        '<img src="data/attachment/forum/page-1.jpg">',
      );

      final sticker = bridge.buildOpenRequest(
        post: _post,
        threadId: '100',
        imageReferer: 'https://bbs.yamibo.com/thread-100-1-1.html',
        legacyPlan: _emptyPlan,
        sequence: prepared.sequence,
        imageRequest: const ForumHtmlImageRequest(
          url: 'https://bbs.yamibo.com/static/image/smiley/comcom/2.gif',
          isSticker: true,
        ),
      );
      final unmatched = bridge.buildOpenRequest(
        post: _post,
        threadId: '100',
        imageReferer: 'https://bbs.yamibo.com/thread-100-1-1.html',
        legacyPlan: _emptyPlan,
        sequence: prepared.sequence,
        imageRequest: const ForumHtmlImageRequest(
          url: 'https://bbs.yamibo.com/data/attachment/forum/missing.jpg',
        ),
      );

      expect(
        sticker.failureReason,
        ThreadHtmlImageReaderBridgeFailureReason.sticker,
      );
      expect(
        unmatched.failureReason,
        ThreadHtmlImageReaderBridgeFailureReason.unmatchedImage,
      );
    });
  });
}

ForumHtmlPreparedRenderDocument _prepared(String html) {
  return const DefaultForumHtmlRenderPreparer().prepare(
    html: html,
    preferences: ForumHtmlReaderPreferences.defaults(),
    sourceId: 'p1',
    threadId: '100',
    imageCacheOwnerId: '100',
  );
}

ThreadPostBodyRenderPlan get _emptyPlan => ThreadPostBodyRenderPlan(
  document: const RichDocument(blocks: <RichBlock>[]),
  displayDocument: const RichDocument(blocks: <RichBlock>[]),
  images: const <ThreadPostImageBlock>[],
  segments: const <ThreadPostBodySegment>[],
  usesListSegments: false,
  renderKey: _renderKey,
);

ThreadPostBodyRenderPlan _planWithLegacyImage({
  required String aid,
  required String url,
}) {
  final image = RichImageBlock(url: url, rawUrl: url, index: 0, aid: aid);
  return ThreadPostBodyRenderPlan(
    document: RichDocument(blocks: <RichBlock>[image]),
    displayDocument: RichDocument(blocks: <RichBlock>[image]),
    images: <ThreadPostImageBlock>[image],
    segments: const <ThreadPostBodySegment>[],
    usesListSegments: false,
    renderKey: _renderKey,
    resourceLayoutHints: ThreadPostResourceLayoutHints(
      blockImages: <String, ThreadPostBlockImageLayoutHint>{
        ThreadPostResourceLayoutHints.blockImageKey(
          image,
        ): const ThreadPostBlockImageLayoutHint(
          aspectRatio: 1.2,
          source: ThreadPostResourceLayoutHintSource.htmlAttribute,
          lockForCurrentBuild: false,
        ),
      },
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

const _renderKey = ThreadPostRenderCacheKey(
  renderSettings: ThreadPostBodyRenderSettings.defaults,
  displayTransformerSignature: 'default',
  resourceHintResolverSignature: 'default',
  segmentation: ThreadPostSegmentationConfig.standard,
);
