import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/forum_image_cache_requests.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';

void main() {
  const resolver = DefaultForumImageRequestResolver();

  group('DefaultForumImageRequestResolver.resolveCacheRequest', () {
    test('maps thread inline images through ForumImageCacheRequests', () {
      final spec = ForumImageLoadSpec(
        kind: ForumImageKind.threadInline,
        url: Uri.parse('https://bbs.yamibo.com/data/attachment/page.jpg'),
        ownerId: '573279',
        imageIndex: 2,
      );

      final request = resolver.resolveCacheRequest(spec);
      final expected = ForumImageCacheRequests.threadInline(
        tid: '573279',
        url: 'https://bbs.yamibo.com/data/attachment/page.jpg',
        imageIndex: 2,
      );

      expect(request?.role, ImageCacheRole.threadInline);
      expect(request?.ownerType, ImageCacheOwnerType.thread);
      expect(request?.ownerId, '573279');
      expect(request?.imageIndex, 2);
      expect(request?.effectiveRetentionClass, ImageRetentionClass.ephemeral);
      expect(request?.cacheKey, expected.cacheKey);
    });

    test('falls back empty thread owner id to unknown', () {
      final request = resolver.resolveCacheRequest(
        ForumImageLoadSpec(
          kind: ForumImageKind.threadInline,
          url: Uri.parse('https://bbs.yamibo.com/a.jpg'),
          ownerId: ' ',
        ),
      );

      expect(request?.ownerId, 'unknown');
    });

    test('maps thread attachments to attachment role', () {
      final request = resolver.resolveCacheRequest(
        ForumImageLoadSpec(
          kind: ForumImageKind.threadAttachment,
          url: Uri.parse('https://bbs.yamibo.com/attachment.php?aid=1'),
          ownerId: '573279',
          imageIndex: 1,
        ),
      );

      expect(request?.role, ImageCacheRole.threadAttachment);
      expect(request?.ownerType, ImageCacheOwnerType.thread);
      expect(request?.ownerId, '573279');
      expect(request?.imageIndex, 1);
      expect(request?.effectiveRetentionClass, ImageRetentionClass.ephemeral);
    });

    test('maps smileys to sticky remote smiley cache keys', () {
      final request = resolver.resolveCacheRequest(
        ForumImageLoadSpec(
          kind: ForumImageKind.remoteSmiley,
          url: Uri.parse(
            'https://bbs.yamibo.com/static/image/smiley/gexing/008.gif',
          ),
        ),
      );

      expect(request?.role, ImageCacheRole.remoteSmiley);
      expect(request?.ownerType, ImageCacheOwnerType.sticker);
      expect(request?.ownerId, 'yamibo-smiley-v4');
      expect(request?.effectiveRetentionClass, ImageRetentionClass.sticky);
      expect(
        request?.cacheKey,
        ImageCacheKeys.remoteSmiley(
          'https://bbs.yamibo.com/static/image/smiley/gexing/008.gif',
        ),
      );
    });

    test('maps avatars with caller-provided owner type', () {
      final request = resolver.resolveCacheRequest(
        ForumImageLoadSpec(
          kind: ForumImageKind.avatar,
          url: Uri.parse('https://bbs.yamibo.com/avatar.php?uid=42'),
          ownerId: '42',
          ownerType: ImageCacheOwnerType.thread,
        ),
      );

      expect(request?.role, ImageCacheRole.avatar);
      expect(request?.ownerType, ImageCacheOwnerType.thread);
      expect(request?.ownerId, '42');
      expect(request?.effectiveRetentionClass, ImageRetentionClass.ephemeral);
    });

    test('maps forum head images to sticky forum cache', () {
      final request = resolver.resolveCacheRequest(
        ForumImageLoadSpec(
          kind: ForumImageKind.forumHeadImage,
          url: Uri.parse('https://bbs.yamibo.com/banner.jpg'),
          ownerId: 'home',
        ),
      );

      expect(request?.role, ImageCacheRole.forumHeadImage);
      expect(request?.ownerType, ImageCacheOwnerType.forum);
      expect(request?.ownerId, 'home');
      expect(request?.effectiveRetentionClass, ImageRetentionClass.sticky);
    });

    test('maps forum icons to sticky forum display cache', () {
      final request = resolver.resolveCacheRequest(
        ForumImageLoadSpec(
          kind: ForumImageKind.forumIcon,
          url: Uri.parse('https://bbs.yamibo.com/icon.png'),
          ownerId: 'fid-20',
        ),
      );

      expect(request?.role, ImageCacheRole.forumIcon);
      expect(request?.ownerType, ImageCacheOwnerType.forumDisplay);
      expect(request?.ownerId, 'fid-20');
      expect(request?.effectiveRetentionClass, ImageRetentionClass.sticky);
      expect(
        request?.cacheKey,
        ImageCacheKeys.forumIcon('https://bbs.yamibo.com/icon.png'),
      );
    });

    test('maps blog inline images to blog role', () {
      final request = resolver.resolveCacheRequest(
        ForumImageLoadSpec(
          kind: ForumImageKind.blogInline,
          url: Uri.parse('https://bbs.yamibo.com/blog-image.jpg'),
          ownerId: 'blog-1',
          imageIndex: 3,
        ),
      );

      expect(request?.role, ImageCacheRole.blogInline);
      expect(request?.ownerType, ImageCacheOwnerType.blog);
      expect(request?.ownerId, 'blog-1');
      expect(request?.imageIndex, 3);
    });

    test('maps cover-like specs only when cache key is explicit', () {
      final missing = resolver.resolveCacheRequest(
        ForumImageLoadSpec(
          kind: ForumImageKind.cover,
          url: Uri.parse('https://bbs.yamibo.com/cover.jpg'),
          ownerId: 'comic-1',
        ),
      );
      final request = resolver.resolveCacheRequest(
        ForumImageLoadSpec(
          kind: ForumImageKind.cover,
          url: Uri.parse('https://bbs.yamibo.com/cover.jpg'),
          ownerId: 'comic-1',
          ownerType: ImageCacheOwnerType.comic,
          cacheKey: ImageCacheKeys.comicCover('comic-1'),
        ),
      );

      expect(missing, isNull);
      expect(request?.role, ImageCacheRole.cover);
      expect(request?.ownerType, ImageCacheOwnerType.comic);
      expect(request?.ownerId, 'comic-1');
      expect(request?.protected, isFalse);
      expect(request?.effectiveRetentionClass, ImageRetentionClass.protected);
    });

    test('maps custom covers as protected cache requests', () {
      final request = resolver.resolveCacheRequest(
        ForumImageLoadSpec(
          kind: ForumImageKind.customCover,
          url: Uri.parse('file:///tmp/cover.jpg'),
          ownerId: 'comic-1',
          ownerType: ImageCacheOwnerType.comic,
          cacheKey: ImageCacheKeys.customCover(
            ownerType: ImageCacheOwnerType.comic.dbValue,
            ownerId: 'comic-1',
          ),
        ),
      );

      expect(request?.role, ImageCacheRole.customCover);
      expect(request?.protected, isTrue);
      expect(request?.effectiveRetentionClass, ImageRetentionClass.protected);
    });

    test('maps comic reader page specs when identity fields are complete', () {
      final request = resolver.resolveCacheRequest(
        ForumImageLoadSpec(
          kind: ForumImageKind.comicReaderPage,
          url: Uri.parse('https://bbs.yamibo.com/page-1.jpg'),
          ownerId: 'comic-1',
          episodeId: 'ep-1',
          imageIndex: 0,
        ),
      );

      expect(request?.role, ImageCacheRole.comicPage);
      expect(request?.ownerType, ImageCacheOwnerType.comic);
      expect(request?.ownerId, 'comic-1');
      expect(request?.episodeId, 'ep-1');
      expect(request?.imageIndex, 0);
      expect(
        request?.effectiveRetentionClass,
        ImageRetentionClass.recentReader,
      );
      expect(
        request?.cacheKey,
        ImageCacheKeys.comicPage(
          comicId: 'comic-1',
          episodeId: 'ep-1',
          imageIndex: 0,
        ),
      );
    });

    test('does not cache external inline images by default', () {
      final request = resolver.resolveCacheRequest(
        ForumImageLoadSpec(
          kind: ForumImageKind.externalInline,
          url: Uri.parse('https://example.com/image.jpg'),
        ),
      );

      expect(request, isNull);
    });
  });

  group('DefaultForumImageRequestResolver.resolveRenderPolicy', () {
    test('covers every image kind', () {
      for (final kind in ForumImageKind.values) {
        final policy = resolver.resolveRenderPolicy(
          ForumImageLoadSpec(
            kind: kind,
            url: Uri.parse('https://bbs.yamibo.com/image.jpg'),
          ),
        );

        expect(policy.layoutMode, isA<ForumImageLayoutMode>());
        expect(policy.precacheMode, isA<ForumImagePrecacheMode>());
        expect(policy.downscaleMode, isA<ForumImageDownscaleMode>());
        expect(policy.retentionHint, isA<ImageRetentionClass>());
      }
    });

    test('uses known aspect ratio policy when html dimensions exist', () {
      final policy = resolver.resolveRenderPolicy(
        ForumImageLoadSpec(
          kind: ForumImageKind.threadInline,
          url: Uri.parse('https://bbs.yamibo.com/page.jpg'),
          htmlWidth: 640,
          htmlHeight: 480,
        ),
      );

      expect(policy.layoutMode, ForumImageLayoutMode.blockWithKnownAspectRatio);
      expect(policy.allowReaderOpen, isTrue);
    });

    test('uses inline intrinsic policy for smileys', () {
      final policy = resolver.resolveRenderPolicy(
        ForumImageLoadSpec(
          kind: ForumImageKind.remoteSmiley,
          url: Uri.parse('https://bbs.yamibo.com/static/image/smiley/a.gif'),
        ),
      );

      expect(policy.layoutMode, ForumImageLayoutMode.inlineIntrinsic);
      expect(policy.precacheMode, ForumImagePrecacheMode.none);
      expect(policy.allowReaderOpen, isFalse);
      expect(policy.retentionHint, ImageRetentionClass.sticky);
    });

    test('uses reader session policy for comic reader pages', () {
      final policy = resolver.resolveRenderPolicy(
        ForumImageLoadSpec(
          kind: ForumImageKind.comicReaderPage,
          url: Uri.parse('https://bbs.yamibo.com/page.jpg'),
        ),
      );

      expect(policy.layoutMode, ForumImageLayoutMode.readerPage);
      expect(
        policy.precacheMode,
        ForumImagePrecacheMode.readerSessionAggressive,
      );
      expect(policy.downscaleMode, ForumImageDownscaleMode.readerViewport);
      expect(policy.retentionHint, ImageRetentionClass.recentReader);
    });
  });
}
