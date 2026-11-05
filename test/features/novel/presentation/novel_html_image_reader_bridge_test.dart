import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/presentation/services/novel_html_image_reader_bridge.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

void main() {
  test(
    'native exact entries preserve repeated URLs and sparse source ordinals',
    () {
      const first = ForumHtmlReadableImageEntry(
        index: 2,
        url: 'https://x/a.png',
        rawSrc: 'a.png',
        resource: _ImageResource('shared-cache'),
      );
      const second = ForumHtmlReadableImageEntry(
        index: 7,
        url: 'https://x/a.png',
        rawSrc: 'a.png',
        resource: _ImageResource('shared-cache'),
        attachmentId: '123',
      );
      const sequence = ForumHtmlReadableImageSequence(
        sourceId: 'episode',
        entries: [first, second],
      );
      final request = const NovelHtmlImageReaderBridge()
          .buildOpenRequestForEntry(
            threadId: '521519',
            episodeId: 'episode',
            postNumber: 171,
            imageReferer: 'https://bbs.yamibo.com/thread-521519-1-1.html',
            sequence: sequence,
            entry: second,
          )!;
      expect(request.initialIndex, 1);
      expect(request.initialEntry!.indexInPost, 7);
      expect(request.group.entries.map((e) => e.indexInPost), [2, 7]);
      expect(request.group.entries.last.aid, '123');
      expect(request.continuousImages.map((e) => e.index), [2, 7]);
      expect(request.continuousImages.map((e) => e.id).toSet(), hasLength(2));
      expect(
        request.continuousImages.every(
          (e) => e.referer.toString() == request.referer,
        ),
        isTrue,
      );
      expect(
        request.continuousImages.every((e) => e.cacheKey == 'shared-cache'),
        isTrue,
      );
      final foreign = ForumHtmlReadableImageEntry(
        index: 7,
        url: second.url,
        rawSrc: second.rawSrc,
        resource: second.resource,
      );
      for (final (episode, entry) in [
        ('other-episode', second),
        ('episode', foreign),
      ]) {
        expect(
          const NovelHtmlImageReaderBridge().buildOpenRequestForEntry(
            threadId: '521519',
            episodeId: episode,
            postNumber: 171,
            imageReferer: request.referer,
            sequence: sequence,
            entry: entry,
          ),
          isNull,
        );
      }
    },
  );

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
          resource: const _ImageResource('novel/inline/page-1'),
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

final class _ImageResource implements ForumHtmlPreparedImageResource {
  const _ImageResource(this.cacheKey);

  @override
  final String cacheKey;
}
