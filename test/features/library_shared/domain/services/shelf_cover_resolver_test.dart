import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/shelf_cover_resolver.dart';
import 'package:y300/features/library_shared/domain/services/shelf_cover_warmup_service.dart';

void main() {
  test(
    'ShelfCoverResolver prefers custom local then normal local before cache metadata',
    () async {
      final resolver = ShelfCoverResolver(
        imageCacheService: _FakeImageCacheService(
          localPath: '/cache/from-meta.jpg',
        ),
      );

      final custom = await resolver.resolveFast(
        item: _item(
          customCoverLocalPath: '/local/custom.jpg',
          coverLocalPath: '/local/cover.jpg',
        ),
        request: _request(),
      );
      expect(custom.localPath, '/local/custom.jpg');

      final normal = await resolver.resolveFast(
        item: _item(coverLocalPath: '/local/cover.jpg'),
        request: _request(),
      );
      expect(normal.localPath, '/local/cover.jpg');

      final metadata = await resolver.resolveFast(
        item: _item(),
        request: _request(),
      );
      expect(metadata.localPath, '/cache/from-meta.jpg');
    },
  );

  test(
    'ShelfCoverResolver returns remote-only without downloading when no local exists',
    () async {
      final resolver = ShelfCoverResolver();

      final resolved = await resolver.resolveFast(
        item: _item(coverImageUrl: 'https://img.test/cover.jpg'),
      );

      expect(resolved.status, ShelfResolvedCoverStatus.remoteOnly);
      expect(resolved.remoteUrl, 'https://img.test/cover.jpg');
      expect(resolved.localPath, isNull);
    },
  );

  test(
    'ShelfCoverResolver marks cached cover request as stale when metadata misses',
    () async {
      final resolver = ShelfCoverResolver(
        imageCacheService: _FakeImageCacheService(),
      );

      final resolved = await resolver.resolveFast(
        item: _item(),
        request: _request(),
      );

      expect(resolved.status, ShelfResolvedCoverStatus.stale);
      expect(resolved.cacheKey, 'cover/comic/w1');
      expect(resolved.remoteUrl, 'https://img.test/request.jpg');
    },
  );

  test(
    'ShelfCoverResolver marks item remote as stale when cache metadata misses by key',
    () async {
      final resolver = ShelfCoverResolver(
        imageCacheService: _FakeImageCacheService(),
      );

      final resolved = await resolver.resolveFast(
        item: _item(coverImageUrl: 'https://img.test/item.jpg'),
        request: _request(sourceUrl: ''),
      );

      expect(resolved.status, ShelfResolvedCoverStatus.stale);
      expect(resolved.cacheKey, 'cover/comic/w1');
      expect(resolved.remoteUrl, 'https://img.test/item.jpg');
    },
  );
}

LibraryWorkItem _item({
  String? coverImageUrl,
  String? customCoverImageUrl,
  String? coverLocalPath,
  String? customCoverLocalPath,
}) {
  return LibraryWorkItem(
    workId: 'w1',
    categoryId: 'default',
    title: 'title',
    coverImageUrl: coverImageUrl,
    customCoverImageUrl: customCoverImageUrl,
    coverLocalPath: coverLocalPath,
    customCoverLocalPath: customCoverLocalPath,
    unreadCount: 0,
    totalChapterCount: 1,
    readChapterCount: 0,
    addedAt: DateTime(2026, 1, 1),
  );
}

ShelfCoverWarmupRequest _request({
  String sourceUrl = 'https://img.test/request.jpg',
}) {
  return ShelfCoverWarmupRequest(
    moduleKey: LibraryModuleKey.comic,
    workId: 'w1',
    cacheKey: 'cover/comic/w1',
    sourceUrl: sourceUrl,
    ownerType: ImageCacheOwnerType.comic,
    ownerId: 'w1',
    role: ImageCacheRole.cover,
    useCustomCover: false,
    imageSpec: ForumImageLoadSpec(
      kind: ForumImageKind.cover,
      url: Uri.parse(sourceUrl),
      ownerType: ImageCacheOwnerType.comic,
      ownerId: 'w1',
      cacheKey: 'cover/comic/w1',
    ),
  );
}

class _FakeImageCacheService implements ImageCacheService {
  _FakeImageCacheService({this.localPath});

  final String? localPath;

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    return 0;
  }

  @override
  Future<void> clearUnprotected() async {}

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async => 0;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult.failed;
  }

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult.failed;
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async {
    final path = localPath;
    if (path == null) {
      return null;
    }
    return CachedImageResult(
      success: true,
      cacheKey: cacheKey,
      localPath: path,
      fromCache: true,
    );
  }

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}
}
