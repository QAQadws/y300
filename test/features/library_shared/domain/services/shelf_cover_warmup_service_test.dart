import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/shelf_cover_warmup_service.dart';

void main() {
  test('ShelfCoverWarmupService dedupes cache keys and reports successful results', () async {
    final service = ShelfCoverWarmupService(maxConcurrent: 2);
    final warmedKeys = <String>[];
    final results = <ShelfCoverWarmupResult>[];

    await service.warmCovers(
      requests: <ShelfCoverWarmupRequest>[
        _request(cacheKey: 'cover/comic/1', workId: 'w1'),
        _request(cacheKey: 'cover/comic/1', workId: 'w1-duplicate'),
        _request(cacheKey: 'cover/comic/2', workId: 'w2'),
      ],
      warmCover: (request) async {
        warmedKeys.add(request.cacheKey);
        return ShelfCoverWarmupResult(
          workId: request.workId,
          coverLocalPath: '/cache/${request.workId}.jpg',
        );
      },
      onResult: results.add,
    );

    expect(warmedKeys, <String>['cover/comic/1', 'cover/comic/2']);
    expect(results.map((e) => e.workId), <String>['w1', 'w2']);
  });

  test('orderedShelfItemsForCoverWarmup prioritizes selected category and dedupes works', () {
    final ordered = orderedShelfItemsForCoverWarmup(
      selectedCategoryId: 'selected',
      itemsByCategory: <String, List<LibraryWorkItem>>{
        'default': <LibraryWorkItem>[
          _item('a', categoryId: 'default'),
          _item('b', categoryId: 'default'),
        ],
        'selected': <LibraryWorkItem>[
          _item('b', categoryId: 'selected'),
          _item('c', categoryId: 'selected'),
        ],
      },
    );

    expect(ordered.map((e) => e.workId), <String>['b', 'c', 'a']);
  });
}

ShelfCoverWarmupRequest _request({
  required String cacheKey,
  required String workId,
}) {
  return ShelfCoverWarmupRequest(
    moduleKey: LibraryModuleKey.comic,
    workId: workId,
    cacheKey: cacheKey,
    sourceUrl: 'https://img.test/$workId.jpg',
    ownerType: ImageCacheOwnerType.comic,
    ownerId: workId,
    role: ImageCacheRole.cover,
    useCustomCover: false,
  );
}

LibraryWorkItem _item(String workId, {required String categoryId}) {
  return LibraryWorkItem(
    workId: workId,
    categoryId: categoryId,
    title: workId,
    unreadCount: 0,
    totalChapterCount: 1,
    readChapterCount: 0,
    addedAt: DateTime(2026, 1, 1),
  );
}
