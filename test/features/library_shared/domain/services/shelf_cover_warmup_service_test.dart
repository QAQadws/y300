import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
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

  test('ShelfCoverWarmupService dedupes same cache key even when source url differs', () async {
    final service = ShelfCoverWarmupService(maxConcurrent: 1);
    final warmedUrls = <String>[];

    await service.warmCovers(
      requests: <ShelfCoverWarmupRequest>[
        _request(cacheKey: 'cover/comic/1', workId: 'w1', sourceUrl: 'https://img.test/a.jpg'),
        _request(cacheKey: 'cover/comic/1', workId: 'w1', sourceUrl: 'https://img.test/b.jpg'),
      ],
      warmCover: (request) async {
        warmedUrls.add(request.sourceUrl);
        return ShelfCoverWarmupResult(
          workId: request.workId,
          coverLocalPath: '/cache/${request.workId}.jpg',
        );
      },
      onResult: (_) {},
    );

    expect(warmedUrls, <String>['https://img.test/a.jpg']);
  });

  test('ShelfCoverWarmupService runs high priority requests first', () async {
    final service = ShelfCoverWarmupService(maxConcurrent: 1);
    final warmed = <String>[];

    await service.warmCovers(
      requests: <ShelfCoverWarmupRequest>[
        _request(
          cacheKey: 'cover/comic/background',
          workId: 'background',
          priority: ShelfCoverWarmupPriority.background,
        ),
        _request(
          cacheKey: 'cover/comic/current',
          workId: 'current',
          priority: ShelfCoverWarmupPriority.currentViewport,
        ),
        _request(
          cacheKey: 'cover/comic/adjacent',
          workId: 'adjacent',
          priority: ShelfCoverWarmupPriority.adjacentCategory,
        ),
      ],
      warmCover: (request) async {
        warmed.add(request.workId);
        return ShelfCoverWarmupResult(
          workId: request.workId,
          coverLocalPath: '/cache/${request.workId}.jpg',
        );
      },
      onResult: (_) {},
    );

    expect(warmed, <String>['current', 'adjacent', 'background']);
  });

  test('ShelfCoverWarmupService skips failed request during cooldown', () async {
    var now = DateTime(2026, 1, 1, 12);
    final service = ShelfCoverWarmupService(
      maxConcurrent: 1,
      failureCooldown: const Duration(minutes: 5),
      now: () => now,
    );
    var calls = 0;
    final request = _request(cacheKey: 'cover/comic/fail', workId: 'fail');

    Future<ShelfCoverWarmupResult?> fail(ShelfCoverWarmupRequest request) async {
      calls += 1;
      return null;
    }

    await service.warmCovers(
      requests: [request],
      warmCover: fail,
      onResult: (_) {},
    );
    await service.warmCovers(
      requests: [request],
      warmCover: fail,
      onResult: (_) {},
    );

    expect(calls, 1);

    now = now.add(const Duration(minutes: 6));
    await service.warmCovers(
      requests: [request],
      warmCover: fail,
      onResult: (_) {},
    );

    expect(calls, 2);
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

  test('prioritizeShelfCoverWarmupRequests marks viewport and adjacent category ranges', () {
    final categories = <LibraryCategory>[
      _category('left'),
      _category('selected'),
      _category('right'),
    ];
    final itemsByCategory = <String, List<LibraryWorkItem>>{
      'left': <LibraryWorkItem>[_item('l1', categoryId: 'left')],
      'selected': <LibraryWorkItem>[
        _item('s0', categoryId: 'selected'),
        _item('s1', categoryId: 'selected'),
        _item('s2', categoryId: 'selected'),
      ],
      'right': <LibraryWorkItem>[_item('r1', categoryId: 'right')],
    };

    final prioritized = prioritizeShelfCoverWarmupRequests(
      requests: <ShelfCoverWarmupRequest>[
        _request(cacheKey: 'cover/comic/l1', workId: 'l1'),
        _request(cacheKey: 'cover/comic/s0', workId: 's0'),
        _request(cacheKey: 'cover/comic/s1', workId: 's1'),
        _request(cacheKey: 'cover/comic/s2', workId: 's2'),
        _request(cacheKey: 'cover/comic/r1', workId: 'r1'),
      ],
      itemsByCategory: itemsByCategory,
      categories: categories,
      selectedCategoryId: 'selected',
      visibleRangesByCategory: const <String, ShelfCoverVisibleRange>{
        'selected': ShelfCoverVisibleRange(firstIndex: 1, lastIndex: 1),
      },
      displayMode: LibraryDisplayMode.list,
      gridColumnCount: 3,
    );

    expect(_priorityOf(prioritized, 's1'), ShelfCoverWarmupPriority.currentViewport);
    expect(_priorityOf(prioritized, 's2'), ShelfCoverWarmupPriority.nearViewport);
    expect(_priorityOf(prioritized, 'l1'), ShelfCoverWarmupPriority.adjacentCategory);
    expect(_priorityOf(prioritized, 'r1'), ShelfCoverWarmupPriority.adjacentCategory);
  });
}

ShelfCoverWarmupRequest _request({
  required String cacheKey,
  required String workId,
  String? sourceUrl,
  ShelfCoverWarmupPriority priority = ShelfCoverWarmupPriority.background,
}) {
  return ShelfCoverWarmupRequest(
    moduleKey: LibraryModuleKey.comic,
    workId: workId,
    cacheKey: cacheKey,
    sourceUrl: sourceUrl ?? 'https://img.test/$workId.jpg',
    ownerType: ImageCacheOwnerType.comic,
    ownerId: workId,
    role: ImageCacheRole.cover,
    useCustomCover: false,
    priority: priority,
  );
}

LibraryCategory _category(String categoryId) {
  return LibraryCategory(
    categoryId: categoryId,
    name: categoryId,
    sortOrder: 0,
    createdAt: DateTime(2026, 1, 1),
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

ShelfCoverWarmupPriority _priorityOf(
  List<ShelfCoverWarmupRequest> requests,
  String workId,
) {
  return requests.singleWhere((request) => request.workId == workId).priority;
}
