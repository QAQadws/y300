import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_cover_image_adapter.dart';

void main() {
  const adapter = LibraryCoverImageAdapter();

  test('comic cover builds cover spec with comic owner cache key', () {
    final request = adapter.buildCoverSpec(
      moduleKey: LibraryModuleKey.comic,
      item: _item(
        workId: 'comic-1',
        coverImageUrl: 'https://img.test/comic.jpg',
      ),
    );

    expect(request, isNotNull);
    expect(request!.workId, 'comic-1');
    expect(request.useCustomCover, isFalse);
    expect(request.imageSpec.kind, ForumImageKind.cover);
    expect(request.imageSpec.ownerType, ImageCacheOwnerType.comic);
    expect(request.imageSpec.ownerId, 'comic-1');
    expect(request.imageSpec.cacheKey, ImageCacheKeys.comicCover('comic-1'));
    expect(request.imageSpec.protected, isFalse);
  });

  test('novel cover builds cover spec with novel owner cache key', () {
    final request = adapter.buildCoverSpec(
      moduleKey: LibraryModuleKey.novel,
      item: _item(
        workId: 'novel-1',
        coverImageUrl: 'https://img.test/novel.jpg',
      ),
    );

    expect(request, isNotNull);
    expect(request!.imageSpec.kind, ForumImageKind.cover);
    expect(request.imageSpec.ownerType, ImageCacheOwnerType.novel);
    expect(request.imageSpec.cacheKey, ImageCacheKeys.novelCover('novel-1'));
  });

  test('custom cover builds protected customCover spec', () {
    final request = adapter.buildCoverSpec(
      moduleKey: LibraryModuleKey.comic,
      item: _item(
        workId: 'comic-2',
        coverImageUrl: 'https://img.test/ordinary.jpg',
        customCoverImageUrl: 'https://img.test/custom.jpg',
      ),
    );

    expect(request, isNotNull);
    expect(request!.useCustomCover, isTrue);
    expect(request.imageSpec.kind, ForumImageKind.customCover);
    expect(request.imageSpec.protected, isTrue);
    expect(
      request.imageSpec.cacheKey,
      ImageCacheKeys.customCover(
        ownerType: ImageCacheOwnerType.comic.dbValue,
        ownerId: 'comic-2',
      ),
    );
  });

  test('existing local cover skips prefetch spec', () {
    final request = adapter.buildCoverSpec(
      moduleKey: LibraryModuleKey.comic,
      item: _item(
        workId: 'comic-3',
        coverImageUrl: 'https://img.test/ordinary.jpg',
        coverLocalPath: '/cache/ordinary.jpg',
      ),
    );

    expect(request, isNull);
  });

  test(
    'favorite cover uses resolved module owner instead of favorite shell',
    () {
      final request = adapter.buildCoverSpec(
        moduleKey: LibraryModuleKey.favorite,
        item: _item(
          workId: 'favorite:100',
          coverImageUrl: 'https://img.test/fav.jpg',
        ),
        ownerType: ImageCacheOwnerType.novel,
        ownerId: 'novel-100',
      );

      expect(request, isNotNull);
      expect(request!.imageSpec.kind, ForumImageKind.favoriteCover);
      expect(request.imageSpec.ownerType, ImageCacheOwnerType.novel);
      expect(request.imageSpec.ownerId, 'novel-100');
      expect(
        request.imageSpec.cacheKey,
        ImageCacheKeys.novelCover('novel-100'),
      );
    },
  );

  test('favorite cover without resolved route target is skipped', () {
    final request = adapter.buildCoverSpec(
      moduleKey: LibraryModuleKey.favorite,
      item: _item(
        workId: 'favorite:101',
        coverImageUrl: 'https://img.test/fav.jpg',
      ),
    );

    expect(request, isNull);
  });

  test('detail header cover can be represented as the same cover spec', () {
    final request = adapter.buildDetailCoverSpec(
      moduleKey: LibraryModuleKey.comic,
      header: LibraryDetailHeader(
        workId: 'comic-detail',
        title: 'Detail',
        coverImageUrl: 'https://img.test/detail.jpg',
        inShelf: true,
      ),
    );

    expect(request, isNotNull);
    expect(request!.workId, 'comic-detail');
    expect(request.imageSpec.kind, ForumImageKind.cover);
    expect(
      request.imageSpec.cacheKey,
      ImageCacheKeys.comicCover('comic-detail'),
    );
  });
}

LibraryWorkItem _item({
  required String workId,
  String? coverImageUrl,
  String? customCoverImageUrl,
  String? coverLocalPath,
  String? customCoverLocalPath,
}) {
  return LibraryWorkItem(
    workId: workId,
    categoryId: 'default',
    title: workId,
    coverImageUrl: coverImageUrl,
    customCoverImageUrl: customCoverImageUrl,
    coverLocalPath: coverLocalPath,
    customCoverLocalPath: customCoverLocalPath,
    unreadCount: 0,
    totalChapterCount: 1,
    readChapterCount: 0,
    addedAt: DateTime.utc(2026, 1, 1),
  );
}
