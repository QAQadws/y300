import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/profile/presentation/blog/blog_image_reader_capability.dart';
import 'package:y300/features/profile/presentation/blog/blog_image_reader_request.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/presentation/engine/engine.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';

const _url = 'https://example.test/picture.png';

void main() {
  test(
    'reader preserves duplicate positions and reuses blog cache ownership',
    () {
      final request = _build(
        const ForumHtmlImageRequest(url: _url, readableIndex: 1),
      )!;
      expect(request.initialIndex, 1);
      expect(request.items, hasLength(2));
      expect(request.items.map((item) => item.id).toSet(), hasLength(2));
      expect(request.requests.map((item) => item.cacheKey).toSet(), {
        ImageCacheKeys.blogInline(_url),
      });
      expect(() => request.items.clear(), throwsUnsupportedError);
      expect(
        request.items.first.sourceKind,
        ContinuousImageSourceKind.genericImageReader,
      );
      final capability = BlogImageReaderCapability(
        request: request,
        imageReferer: 'https://example.test/',
        title: 'fixture',
        displayLabel: 'display',
        exportLabel: 'export',
      );
      for (final item in request.items) {
        expect(item.ownerId, 'session-1');
        expect(item.knownDimensions!.width, 120);
        expect(item.knownDimensions!.height, 80);
        final cached = capability.cacheRequestFor(item);
        expect(cached.ownerType, ImageCacheOwnerType.blog);
        expect(cached.ownerId, 'blog-11');
        expect(cached.role, ImageCacheRole.blogInline);
        final spec = capability.imageLoadSpecFor(item)!;
        expect(spec.kind, ForumImageKind.blogInline);
        expect(spec.cacheKey, cached.cacheKey);
        expect(
          capability.exportMetadataFor(item)!.baseName,
          startsWith('Y300-blog-blog-11-'),
        );
      }
      expect(capability.readerKind, ReaderKind.generic);
    },
  );

  for (final image in [
    const ForumHtmlImageRequest(url: _url, isSticker: true),
    const ForumHtmlImageRequest(url: _url, readableIndex: -1),
    const ForumHtmlImageRequest(url: _url, readableIndex: 3),
    const ForumHtmlImageRequest(
      url: 'https://example.test/other.png',
      readableIndex: 1,
    ),
    const ForumHtmlImageRequest(
      url: _url,
      cacheKey: 'thread/inline/wrong-policy',
    ),
    const ForumHtmlImageRequest(url: 'javascript:alert(1)'),
    const ForumHtmlImageRequest(url: 'file:///tmp/file.png'),
    const ForumHtmlImageRequest(
      url: 'https://user:password@example.test/picture.png',
    ),
  ]) {
    test(
      'unmatched or non-readable image is rejected: ${image.url} ${image.readableIndex} ${image.isSticker}',
      () {
        expect(_build(image), isNull);
      },
    );
  }

  test(
    'URL fallback accepts the actual visible cache key without guessing another source',
    () {
      final request = _build(
        ForumHtmlImageRequest(
          url: '$_url#fragment',
          cacheKey: ImageCacheKeys.blogInline(_url),
        ),
      )!;
      expect(request.initialIndex, 0);
      expect(request.items.first.url, _url);
    },
  );
}

BlogImageReaderRequest? _build(ForumHtmlImageRequest image) =>
    BlogImageReaderRequest.fromImage(
      sequence: ForumHtmlReadableImageSequence(
        sourceId: 'fixture-article',
        entries: [
          for (var i = 0; i < 2; i++)
            ForumHtmlReadableImageEntry(
              index: i,
              url: _url,
              rawSrc: _url,
              cacheKey: ImageCacheKeys.threadInline(_url),
              spec: ForumImageLoadSpec(
                kind: ForumImageKind.threadInline,
                url: Uri.parse(_url),
              ),
              htmlWidth: 120,
              htmlHeight: 80,
            ),
        ],
      ),
      image: image,
      cacheOwnerId: 'blog-11',
      sessionOwnerId: 'session-1',
      referer: 'https://example.test/',
      resolver: const DefaultForumImageRequestResolver(),
    );
