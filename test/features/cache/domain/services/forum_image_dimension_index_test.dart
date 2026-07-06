import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/forum_image_cache_requests.dart';
import 'package:y300/features/cache/domain/models/forum_image_dimensions.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_dimension_index.dart';
import 'package:y300/features/cache/domain/services/forum_image_layout_hint_resolver.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';

void main() {
  group('ForumImageDimensions', () {
    test('reads valid html dimensions and aspect ratio', () {
      final dimensions = ForumImageDimensions.fromHtmlSpec(
        ForumImageLoadSpec(
          kind: ForumImageKind.threadInline,
          url: Uri.parse('https://bbs.yamibo.com/page.jpg'),
          htmlWidth: 640,
          htmlHeight: 480,
        ),
      );

      expect(dimensions?.width, 640);
      expect(dimensions?.height, 480);
      expect(dimensions?.source, ForumImageDimensionSource.htmlAttribute);
      expect(dimensions?.aspectRatio, 640 / 480);
    });

    test('rejects invalid dimensions', () {
      final dimensions = ForumImageDimensions.fromHtmlSpec(
        ForumImageLoadSpec(
          kind: ForumImageKind.threadInline,
          url: Uri.parse('https://bbs.yamibo.com/page.jpg'),
          htmlWidth: 0,
          htmlHeight: 480,
        ),
      );

      expect(dimensions, isNull);
    });
  });

  group('CacheRecordForumImageDimensionIndex', () {
    test(
      'reads cache metadata dimensions through spec request resolution',
      () async {
        final cacheService = _RecordingImageCacheService();
        final request = ForumImageCacheRequests.threadInline(
          tid: '573279',
          url: 'https://bbs.yamibo.com/data/attachment/forum/page.jpg',
          imageIndex: 2,
        );
        cacheService.cachedResults[request.cacheKey] = CachedImageResult(
          success: true,
          cacheKey: request.cacheKey,
          width: 320,
          height: 200,
          fromCache: true,
        );
        final index = CacheRecordForumImageDimensionIndex(
          imageCacheService: cacheService,
          imageRequestResolver: const DefaultForumImageRequestResolver(),
        );

        final dimensions = await index.getBySpec(
          ForumImageLoadSpec(
            kind: ForumImageKind.threadInline,
            url: Uri.parse(
              'https://bbs.yamibo.com/data/attachment/forum/page.jpg',
            ),
            ownerId: '573279',
            imageIndex: 2,
          ),
        );

        expect(dimensions?.width, 320);
        expect(dimensions?.height, 200);
        expect(dimensions?.source, ForumImageDimensionSource.cacheMetadata);
        expect(cacheService.getCachedKeys, <String>[request.cacheKey]);
      },
    );

    test('returns null when cache metadata is missing or invalid', () async {
      final cacheService = _RecordingImageCacheService();
      final request = ForumImageCacheRequests.remoteSmiley(
        url: 'https://bbs.yamibo.com/static/image/smiley/gexing/008.gif',
        ownerId: 'yamibo-smiley-v4',
      );
      cacheService.cachedResults[request.cacheKey] = CachedImageResult(
        success: true,
        cacheKey: request.cacheKey,
        width: 0,
        height: 32,
        fromCache: true,
      );
      final index = CacheRecordForumImageDimensionIndex(
        imageCacheService: cacheService,
        imageRequestResolver: const DefaultForumImageRequestResolver(),
      );

      final invalid = await index.getBySpec(
        ForumImageLoadSpec(
          kind: ForumImageKind.remoteSmiley,
          url: Uri.parse(
            'https://bbs.yamibo.com/static/image/smiley/gexing/008.gif',
          ),
        ),
      );
      final missing = await index.getBySpec(
        ForumImageLoadSpec(
          kind: ForumImageKind.threadInline,
          url: Uri.parse('https://bbs.yamibo.com/missing.jpg'),
          ownerId: '573279',
        ),
      );

      expect(invalid, isNull);
      expect(missing, isNull);
    });

    test('returns null for specs without cache requests', () async {
      final cacheService = _RecordingImageCacheService();
      final index = CacheRecordForumImageDimensionIndex(
        imageCacheService: cacheService,
        imageRequestResolver: const DefaultForumImageRequestResolver(),
      );

      final dimensions = await index.getBySpec(
        ForumImageLoadSpec(
          kind: ForumImageKind.externalInline,
          url: Uri.parse('https://example.com/image.jpg'),
        ),
      );

      expect(dimensions, isNull);
      expect(cacheService.getCachedKeys, isEmpty);
    });

    test('recording decoded dimensions failure does not escape', () async {
      final index = CacheRecordForumImageDimensionIndex(
        imageCacheService: _ThrowingDimensionImageCacheService(),
        imageRequestResolver: const DefaultForumImageRequestResolver(),
      );

      await expectLater(
        index.recordDecodedDimensions(
          spec: ForumImageLoadSpec(
            kind: ForumImageKind.remoteSmiley,
            url: Uri.parse(
              'https://bbs.yamibo.com/static/image/smiley/gexing/008.gif',
            ),
          ),
          size: const Size(24, 24),
        ),
        completes,
      );
    });
  });

  group('ForumImageLayoutHintResolver', () {
    const resolver = ForumImageLayoutHintResolver();

    test('thread images prefer html dimensions over cache metadata', () {
      final hint = resolver.resolve(
        spec: ForumImageLoadSpec(
          kind: ForumImageKind.threadInline,
          url: Uri.parse('https://bbs.yamibo.com/page.jpg'),
          htmlWidth: 640,
          htmlHeight: 480,
        ),
        cacheDimensions: const ForumImageDimensions(
          width: 320,
          height: 200,
          source: ForumImageDimensionSource.cacheMetadata,
        ),
      );

      expect(hint.layoutMode, ForumImageLayoutMode.blockWithKnownAspectRatio);
      expect(hint.dimensionSource, ForumImageDimensionSource.htmlAttribute);
      expect(hint.aspectRatio, 640 / 480);
      expect(hint.displaySize, isNull);
    });

    test('thread images use cache metadata before fallback ratio', () {
      final hint = resolver.resolve(
        spec: ForumImageLoadSpec(
          kind: ForumImageKind.threadInline,
          url: Uri.parse('https://bbs.yamibo.com/page.jpg'),
        ),
        cacheDimensions: const ForumImageDimensions(
          width: 320,
          height: 200,
          source: ForumImageDimensionSource.cacheMetadata,
        ),
      );

      expect(hint.layoutMode, ForumImageLayoutMode.blockWithKnownAspectRatio);
      expect(hint.dimensionSource, ForumImageDimensionSource.cacheMetadata);
      expect(hint.aspectRatio, 1.6);
    });

    test('thread images fall back to the stable unknown ratio', () {
      final hint = resolver.resolve(
        spec: ForumImageLoadSpec(
          kind: ForumImageKind.threadInline,
          url: Uri.parse('https://bbs.yamibo.com/page.jpg'),
        ),
      );

      expect(
        hint.layoutMode,
        ForumImageLayoutMode.blockWithFallbackAspectRatio,
      );
      expect(hint.dimensionSource, isNull);
      expect(hint.aspectRatio, 0.7);
    });

    test('smileys prefer html then cache dimensions before intrinsic', () {
      final htmlHint = resolver.resolve(
        spec: ForumImageLoadSpec(
          kind: ForumImageKind.remoteSmiley,
          url: Uri.parse('https://bbs.yamibo.com/static/image/smiley/a.gif'),
          htmlWidth: 36,
          htmlHeight: 28,
        ),
        cacheDimensions: const ForumImageDimensions(
          width: 40,
          height: 32,
          source: ForumImageDimensionSource.cacheMetadata,
        ),
      );
      final cacheHint = resolver.resolve(
        spec: ForumImageLoadSpec(
          kind: ForumImageKind.remoteSmiley,
          url: Uri.parse('https://bbs.yamibo.com/static/image/smiley/a.gif'),
        ),
        cacheDimensions: const ForumImageDimensions(
          width: 40,
          height: 32,
          source: ForumImageDimensionSource.cacheMetadata,
        ),
      );
      final intrinsicHint = resolver.resolve(
        spec: ForumImageLoadSpec(
          kind: ForumImageKind.remoteSmiley,
          url: Uri.parse('https://bbs.yamibo.com/static/image/smiley/a.gif'),
        ),
      );

      expect(htmlHint.displaySize, const Size(36, 28));
      expect(htmlHint.dimensionSource, ForumImageDimensionSource.htmlAttribute);
      expect(cacheHint.displaySize, const Size(40, 32));
      expect(
        cacheHint.dimensionSource,
        ForumImageDimensionSource.cacheMetadata,
      );
      expect(intrinsicHint.displaySize, isNull);
      expect(intrinsicHint.layoutMode, ForumImageLayoutMode.inlineIntrinsic);
    });

    test('fixed-surface image kinds do not use body fallback layout', () {
      final expectations = <ForumImageKind, ForumImageLayoutMode>{
        ForumImageKind.avatar: ForumImageLayoutMode.fixedAvatar,
        ForumImageKind.cover: ForumImageLayoutMode.fixedCover,
        ForumImageKind.customCover: ForumImageLayoutMode.fixedCover,
        ForumImageKind.favoriteCover: ForumImageLayoutMode.fixedCover,
        ForumImageKind.forumHeadImage: ForumImageLayoutMode.fixedBanner,
        ForumImageKind.forumIcon: ForumImageLayoutMode.fixedIcon,
        ForumImageKind.comicReaderPage: ForumImageLayoutMode.readerPage,
      };

      for (final entry in expectations.entries) {
        final hint = resolver.resolve(
          spec: ForumImageLoadSpec(
            kind: entry.key,
            url: Uri.parse('https://bbs.yamibo.com/image.jpg'),
          ),
        );

        expect(hint.layoutMode, entry.value);
        expect(hint.dimensionSource, ForumImageDimensionSource.fixedContainer);
        expect(hint.aspectRatio, isNull);
      }
    });
  });
}

class _RecordingImageCacheService implements ImageCacheService {
  final cachedResults = <String, CachedImageResult>{};
  final getCachedKeys = <String>[];

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult(success: true, cacheKey: request.cacheKey);
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async {
    getCachedKeys.add(cacheKey);
    return cachedResults[cacheKey];
  }

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult.failed;
  }

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async {
    return 0;
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    return 0;
  }

  @override
  Future<void> clearUnprotected() async {}
}

class _ThrowingDimensionImageCacheService extends _RecordingImageCacheService
    implements ImageCacheDimensionRecorder {
  @override
  Future<void> recordResolvedDimensions({
    required String cacheKey,
    required Size size,
  }) async {
    throw StateError('boom');
  }
}
