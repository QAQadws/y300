import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/thread/domain/models/thread_image_layout_hint.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_preparer.dart';
import 'forum_html_test_theme.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_html_image_reader_bridge.dart';

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
        theme: forumHtmlTestTheme,
        sourceId: 'p1',
        threadId: '100',
        imageCacheOwnerId: '100',
      );

      final images = html_parser
          .parseFragment(prepared.preparedHtml)
          .querySelectorAll('img');

      expect(prepared.sequence.entries, hasLength(2));
      expect(prepared.totalImageCount, 2);
      expect(prepared.readableImageCount, 2);
      expect(prepared.attachmentTaggedCount, 1);
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
        theme: forumHtmlTestTheme,
        sourceId: 'p1',
        threadId: '100',
        imageCacheOwnerId: '100',
      );

      expect(prepared.sequence.entries, hasLength(1));
      expect(prepared.totalImageCount, 4);
      expect(prepared.skippedStickerCount, 1);
      expect(prepared.skippedNonNetworkCount, 2);
    });

    test('keeps repeated real image references as separate reader entries', () {
      final prepared = preparer.prepare(
        html:
            '<img src="https://example.com/images/page-1.jpg">'
            '<img src="https://example.com/images/page-1.jpg">',
        preferences: ForumHtmlReaderPreferences.defaults(),
        theme: forumHtmlTestTheme,
        sourceId: 'p1',
        threadId: '100',
        imageCacheOwnerId: '100',
      );

      expect(prepared.sequence.entries, hasLength(2));
      expect(prepared.duplicatedReadableUrlCount, 1);
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
        theme: forumHtmlTestTheme,
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
        sequence: prepared.sequence,
        imageRequest: ForumHtmlImageRequest(
          url: prepared.sequence.entries[1].url,
          readableIndex: 1,
        ),
      );

      expect(result.canOpen, isTrue);
      expect(result.request!.initialIndex, 1);
      expect(result.request!.initialEntry!.url, endsWith('/page-2.jpg'));
      expect(result.request!.continuousImages, hasLength(2));
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
        sequence: prepared.sequence,
        imageRequest: const ForumHtmlImageRequest(
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

    test('keeps repeated URLs distinct by readable index', () {
      final prepared = _prepared(
        '<img src="https://example.test/page.jpg">'
        '<img src="https://example.test/page.jpg">',
      );
      final result = bridge.buildOpenRequest(
        post: _post,
        threadId: '100',
        imageReferer: _referer,
        sequence: prepared.sequence,
        imageRequest: const ForumHtmlImageRequest(
          url: 'https://example.test/page.jpg',
          readableIndex: 1,
        ),
      );

      final request = result.request!;
      expect(request.initialIndex, 1);
      expect(request.initialEntry!.indexInPost, 1);
      expect(request.group.urls, <String>[
        'https://example.test/page.jpg',
        'https://example.test/page.jpg',
      ]);
      expect(
        request.continuousImages[0].id,
        isNot(request.continuousImages[1].id),
      );
    });

    test(
      'attachment identity precedes URL fallback without a readable index',
      () {
        final prepared = _prepared(
          '<img src="data/attachment/forum/page-1.jpg">'
          '<img id="aimg_99" src="data/attachment/forum/page-2.jpg">',
        );
        final result = bridge.buildOpenRequest(
          post: _post,
          threadId: '100',
          imageReferer: _referer,
          sequence: prepared.sequence,
          imageRequest: ForumHtmlImageRequest(
            url: prepared.sequence.entries.first.url,
            attachmentId: ' 99 ',
          ),
        );

        expect(result.request!.initialIndex, 1);
        expect(result.request!.initialEntry!.aid, '99');
      },
    );

    test('matches a relative URL after trimming and removing its fragment', () {
      final prepared = _prepared(
        '<img src="data/attachment/forum/page-1.jpg">',
      );
      final result = bridge.buildOpenRequest(
        post: _post,
        threadId: '100',
        imageReferer: _referer,
        sequence: prepared.sequence,
        imageRequest: const ForumHtmlImageRequest(
          url: ' data/attachment/forum/page-1.jpg#tap ',
          attachmentId: 'unknown',
        ),
      );

      expect(result.request!.initialIndex, 0);
    });

    test('matches the original source when the readable URL differs', () {
      final source = _prepared(
        '<img src="data/attachment/forum/page-1.jpg">',
      ).sequence.entries.single;
      final sequence = ForumHtmlReadableImageSequence(
        sourceId: 'p1',
        entries: <ForumHtmlReadableImageEntry>[
          _entryWith(source, url: 'https://cdn.example.test/page-1.jpg'),
        ],
      );
      final result = bridge.buildOpenRequest(
        post: _post,
        threadId: '100',
        imageReferer: _referer,
        sequence: sequence,
        imageRequest: const ForumHtmlImageRequest(
          url: 'data/attachment/forum/page-1.jpg#tap',
        ),
      );

      expect(
        result.request!.initialEntry!.url,
        'https://cdn.example.test/page-1.jpg',
      );
    });

    test(
      'lazy file sources preserve cache identity, referer, and dimensions',
      () {
        final prepared = _prepared(
          '<img id="aimg_42" src="static/image/common/none.gif" '
          'file="data/attachment/forum/page-1.jpg" width="640" height="480">',
        );
        final source = prepared.sequence.entries.single;
        final result = bridge.buildOpenRequest(
          post: _post,
          threadId: '100',
          imageReferer: _referer,
          sequence: prepared.sequence,
          imageRequest: const ForumHtmlImageRequest(
            url: 'https://bbs.yamibo.com/data/attachment/forum/page-1.jpg',
            readableIndex: 0,
            cacheKey: 'untrusted-tap-cache-key',
          ),
        );

        final request = result.request!;
        final image = request.initialEntry!;
        final continuousImage = request.continuousImages.single;
        expect(request.tid, '100');
        expect(request.pid, 'p1');
        expect(request.postNumber, 1);
        expect(request.referer, _referer);
        expect(request.group.tid, request.tid);
        expect(request.group.pid, request.pid);
        expect(request.group.postNumber, request.postNumber);
        expect(
          image.url,
          'https://bbs.yamibo.com/data/attachment/forum/page-1.jpg',
        );
        expect(image.rawUrl, 'data/attachment/forum/page-1.jpg');
        expect(image.aid, '42');
        expect(image.cacheKey, source.cacheKey);
        expect(image.layoutHint!.aspectRatio, closeTo(640 / 480, 0.0001));
        expect(
          image.layoutHint!.source,
          ThreadPostResourceLayoutHintSource.htmlAttribute,
        );
        expect(continuousImage.cacheKey, source.cacheKey);
        expect(continuousImage.url, image.url);
        expect(continuousImage.referer, Uri.parse(_referer));
        expect(continuousImage.ownerId, 'thread:100:post:p1');
        expect(continuousImage.id, 'thread:100:post:p1:0:${source.cacheKey}');
        expect(
          continuousImage.sourceKind,
          ContinuousImageSourceKind.threadImageReader,
        );
        expect(
          continuousImage.knownDimensionSource,
          ContinuousImageDimensionSource.html,
        );
        expect(
          continuousImage.knownWidth! / continuousImage.knownHeight!,
          closeTo(640 / 480, 0.001),
        );
      },
    );

    for (final index in <int>[-1, 1]) {
      test(
        'invalid readable index $index cannot fallback to a matching image',
        () {
          final prepared = _prepared(
            '<img id="aimg_99" src="data/attachment/forum/page-1.jpg">',
          );
          final result = bridge.buildOpenRequest(
            post: _post,
            threadId: '100',
            imageReferer: _referer,
            sequence: prepared.sequence,
            imageRequest: ForumHtmlImageRequest(
              url: prepared.sequence.entries.single.url,
              readableIndex: index,
              attachmentId: '99',
            ),
          );

          expect(result.request, isNull);
          expect(
            result.failureReason,
            ThreadHtmlImageReaderBridgeFailureReason.unmatchedImage,
          );
        },
      );
    }

    test(
      'rejects a malformed sequence whose image index is outside its group',
      () {
        final source = _prepared(
          '<img src="data/attachment/forum/page-1.jpg">',
        ).sequence.entries.single;
        final result = bridge.buildOpenRequest(
          post: _post,
          threadId: '100',
          imageReferer: _referer,
          sequence: ForumHtmlReadableImageSequence(
            sourceId: 'p1',
            entries: <ForumHtmlReadableImageEntry>[
              _entryWith(source, index: 2),
            ],
          ),
          imageRequest: ForumHtmlImageRequest(
            url: source.url,
            readableIndex: 0,
          ),
        );

        expect(result.request, isNull);
        expect(
          result.failureReason,
          ThreadHtmlImageReaderBridgeFailureReason.invalidInitialIndex,
        );
      },
    );

    test('returns empty-sequence fallback when no image can be read', () {
      final result = bridge.buildOpenRequest(
        post: _post,
        threadId: '100',
        imageReferer: _referer,
        sequence: const ForumHtmlReadableImageSequence(
          sourceId: 'p1',
          entries: <ForumHtmlReadableImageEntry>[],
        ),
        imageRequest: const ForumHtmlImageRequest(
          url: 'https://example.test/page.jpg',
        ),
      );

      expect(result.request, isNull);
      expect(
        result.failureReason,
        ThreadHtmlImageReaderBridgeFailureReason.emptySequence,
      );
    });
  });
}

ForumHtmlPreparedRenderDocument _prepared(String html) {
  return const DefaultForumHtmlRenderPreparer().prepare(
    html: html,
    preferences: ForumHtmlReaderPreferences.defaults(),
    theme: forumHtmlTestTheme,
    sourceId: 'p1',
    threadId: '100',
    imageCacheOwnerId: '100',
  );
}

ForumHtmlReadableImageEntry _entryWith(
  ForumHtmlReadableImageEntry source, {
  int? index,
  String? url,
}) {
  return ForumHtmlReadableImageEntry(
    index: index ?? source.index,
    url: url ?? source.url,
    rawSrc: source.rawSrc,
    cacheKey: source.cacheKey,
    spec: source.spec,
    attachmentId: source.attachmentId,
    htmlWidth: source.htmlWidth,
    htmlHeight: source.htmlHeight,
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

const _referer = 'https://bbs.yamibo.com/thread-100-1-1.html';
