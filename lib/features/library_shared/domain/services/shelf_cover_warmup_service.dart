import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';

/// A metadata-only shelf adapter can opt into this contract to warm covers
/// after the page is already visible.
///
/// The shared controller only knows this small surface. Module-specific cache
/// keys, write-back rules and route target lookup stay inside each adapter.
abstract class ShelfCoverWarmupAdapter {
  Future<List<ShelfCoverWarmupRequest>> buildCoverWarmupRequests({
    required Map<String, List<LibraryWorkItem>> itemsByCategory,
    String? selectedCategoryId,
  });

  Future<ShelfCoverWarmupResult?> warmCover(ShelfCoverWarmupRequest request);
}

class ShelfCoverWarmupRequest {
  const ShelfCoverWarmupRequest({
    required this.moduleKey,
    required this.workId,
    required this.cacheKey,
    required this.sourceUrl,
    required this.ownerType,
    required this.ownerId,
    required this.role,
    required this.useCustomCover,
  });

  /// The shelf item id that should receive the warmed local path.
  final LibraryModuleKey moduleKey;
  final String workId;
  final String cacheKey;
  final String sourceUrl;
  final ImageCacheOwnerType ownerType;
  final String ownerId;
  final ImageCacheRole role;
  final bool useCustomCover;
}

class ShelfCoverWarmupResult {
  const ShelfCoverWarmupResult({
    required this.workId,
    this.coverLocalPath,
    this.customCoverLocalPath,
  });

  final String workId;
  final String? coverLocalPath;
  final String? customCoverLocalPath;

  bool get hasPath {
    final cover = coverLocalPath?.trim();
    final custom = customCoverLocalPath?.trim();
    return (cover != null && cover.isNotEmpty) || (custom != null && custom.isNotEmpty);
  }
}

typedef ShelfCoverWarmupRunner = Future<ShelfCoverWarmupResult?> Function(
  ShelfCoverWarmupRequest request,
);

typedef ShelfCoverWarmupResultHandler = void Function(ShelfCoverWarmupResult result);

class ShelfCoverWarmupService {
  ShelfCoverWarmupService({
    int maxConcurrent = 3,
  }) : _maxConcurrent = maxConcurrent < 1 ? 1 : maxConcurrent;

  final int _maxConcurrent;
  final Set<String> _runningCacheKeys = <String>{};

  Future<void> warmCovers({
    required Iterable<ShelfCoverWarmupRequest> requests,
    required ShelfCoverWarmupRunner warmCover,
    required ShelfCoverWarmupResultHandler onResult,
  }) async {
    final queue = _dedupeAndReserve(requests);
    if (queue.isEmpty) {
      return;
    }

    var nextIndex = 0;
    final workerCount = queue.length < _maxConcurrent ? queue.length : _maxConcurrent;
    final workers = List<Future<void>>.generate(workerCount, (_) async {
      while (nextIndex < queue.length) {
        final request = queue[nextIndex++];
        try {
          final result = await warmCover(request);
          if (result != null && result.hasPath) {
            onResult(result);
          }
        } catch (_) {
          // Cover warming is best-effort. A failed cover must never break the
          // visible shelf metadata path.
        } finally {
          _runningCacheKeys.remove(request.cacheKey);
        }
      }
    });

    await Future.wait(workers);
  }

  List<ShelfCoverWarmupRequest> _dedupeAndReserve(
    Iterable<ShelfCoverWarmupRequest> requests,
  ) {
    final seenInBatch = <String>{};
    final queue = <ShelfCoverWarmupRequest>[];
    for (final request in requests) {
      final cacheKey = request.cacheKey.trim();
      final sourceUrl = request.sourceUrl.trim();
      if (cacheKey.isEmpty || sourceUrl.isEmpty) {
        continue;
      }
      if (!seenInBatch.add(cacheKey)) {
        continue;
      }
      if (!_runningCacheKeys.add(cacheKey)) {
        continue;
      }
      queue.add(request);
    }
    return queue;
  }
}

List<LibraryWorkItem> orderedShelfItemsForCoverWarmup({
  required Map<String, List<LibraryWorkItem>> itemsByCategory,
  String? selectedCategoryId,
}) {
  final ordered = <LibraryWorkItem>[];
  final seenWorkIds = <String>{};

  void append(String categoryId) {
    final items = itemsByCategory[categoryId] ?? const <LibraryWorkItem>[];
    for (final item in items) {
      if (seenWorkIds.add(item.workId)) {
        ordered.add(item);
      }
    }
  }

  final selected = selectedCategoryId?.trim();
  if (selected != null && selected.isNotEmpty) {
    append(selected);
  }
  for (final categoryId in itemsByCategory.keys) {
    if (categoryId.trim() != selected) {
      append(categoryId);
    }
  }
  return ordered;
}
