import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/novel/presentation/services/novel_html_image_reader_bridge.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';

void main() {
  test('novel image reader requests leave display spacing to the engine', () {
    final imageUri = Uri.parse(
      'https://bbs.yamibo.com/data/attachment/forum/novel-page.jpg',
    );
    final sequence = ForumHtmlReadableImageSequence(
      sourceId: 'novel-episode-1',
      entries: <ForumHtmlReadableImageEntry>[
        ForumHtmlReadableImageEntry(
          index: 0,
          url: imageUri.toString(),
          rawSrc: 'data/attachment/forum/novel-page.jpg',
          cacheKey: 'novel/inline/page-1',
          spec: ForumImageLoadSpec(
            kind: ForumImageKind.threadInline,
            url: imageUri,
            ownerId: '100',
            imageIndex: 0,
            cacheKey: 'novel/inline/page-1',
          ),
        ),
      ],
    );

    final request = const NovelHtmlImageReaderBridge().buildOpenRequest(
      threadId: '100',
      episodeId: 'novel-episode-1',
      postNumber: 2,
      imageReferer: 'https://bbs.yamibo.com/thread-100-1-1.html',
      sequence: sequence,
      imageRequest: ForumHtmlImageRequest(
        url: imageUri.toString(),
        readableIndex: 0,
      ),
    );

    expect(request, isNotNull);
    expect(request!.continuousImages, hasLength(1));
    expect(request.continuousImages.single.spacingAfter, 0);
  });
}
