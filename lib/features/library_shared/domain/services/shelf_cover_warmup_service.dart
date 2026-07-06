import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';

enum ShelfCoverWarmupPriority {
  currentViewport,
  nearViewport,
  adjacentCategory,
  background,
}

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

  Future<ShelfCoverWarmupResult?> applyWarmedCover({
    required ShelfCoverWarmupRequest request,
    required String localPath,
  }) {
    return warmCover(request);
  }
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
    required this.imageSpec,
    this.priority = ShelfCoverWarmupPriority.background,
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
  final ForumImageLoadSpec imageSpec;
  final ShelfCoverWarmupPriority priority;

  String get dedupeKey {
    final specKey = imageSpec.cacheKey?.trim();
    if (specKey != null && specKey.isNotEmpty) {
      return specKey;
    }
    return cacheKey;
  }

  ShelfCoverWarmupRequest copyWith({ShelfCoverWarmupPriority? priority}) {
    return ShelfCoverWarmupRequest(
      moduleKey: moduleKey,
      workId: workId,
      cacheKey: cacheKey,
      sourceUrl: sourceUrl,
      ownerType: ownerType,
      ownerId: ownerId,
      role: role,
      useCustomCover: useCustomCover,
      imageSpec: imageSpec,
      priority: priority ?? this.priority,
    );
  }
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
    return (cover != null && cover.isNotEmpty) ||
        (custom != null && custom.isNotEmpty);
  }
}

class ShelfCoverVisibleRange {
  const ShelfCoverVisibleRange({
    required this.firstIndex,
    required this.lastIndex,
  });

  final int firstIndex;
  final int lastIndex;

  bool contains(int index) {
    return index >= firstIndex && index <= lastIndex;
  }

  bool isNearAfter(int index, int prefetchCount) {
    return index > lastIndex && index <= lastIndex + prefetchCount;
  }

  ShelfCoverVisibleRange normalized(int itemCount) {
    if (itemCount <= 0) {
      return const ShelfCoverVisibleRange(firstIndex: 0, lastIndex: -1);
    }
    final first = firstIndex.clamp(0, itemCount - 1).toInt();
    final last = lastIndex.clamp(first, itemCount - 1).toInt();
    return ShelfCoverVisibleRange(firstIndex: first, lastIndex: last);
  }

  @override
  bool operator ==(Object other) {
    return other is ShelfCoverVisibleRange &&
        other.firstIndex == firstIndex &&
        other.lastIndex == lastIndex;
  }

  @override
  int get hashCode => Object.hash(firstIndex, lastIndex);
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

List<ShelfCoverWarmupRequest> prioritizeShelfCoverWarmupRequests({
  required Iterable<ShelfCoverWarmupRequest> requests,
  required Map<String, List<LibraryWorkItem>> itemsByCategory,
  required List<LibraryCategory> categories,
  required String selectedCategoryId,
  required Map<String, ShelfCoverVisibleRange> visibleRangesByCategory,
  required LibraryDisplayMode displayMode,
  required int gridColumnCount,
}) {
  final priorityByWorkId = _coverPriorityByWorkId(
    itemsByCategory: itemsByCategory,
    categories: categories,
    selectedCategoryId: selectedCategoryId,
    visibleRangesByCategory: visibleRangesByCategory,
    displayMode: displayMode,
    gridColumnCount: gridColumnCount,
  );
  return requests
      .map(
        (request) => request.copyWith(
          priority:
              priorityByWorkId[request.workId] ??
              ShelfCoverWarmupPriority.background,
        ),
      )
      .toList(growable: false);
}

Map<String, ShelfCoverWarmupPriority> _coverPriorityByWorkId({
  required Map<String, List<LibraryWorkItem>> itemsByCategory,
  required List<LibraryCategory> categories,
  required String selectedCategoryId,
  required Map<String, ShelfCoverVisibleRange> visibleRangesByCategory,
  required LibraryDisplayMode displayMode,
  required int gridColumnCount,
}) {
  final priorityByWorkId = <String, ShelfCoverWarmupPriority>{};
  final selectedIndex = categories.indexWhere(
    (category) => category.categoryId == selectedCategoryId,
  );
  final selectedItems =
      itemsByCategory[selectedCategoryId] ?? const <LibraryWorkItem>[];
  final firstScreenCount = _estimatedFirstScreenCount(
    displayMode: displayMode,
    gridColumnCount: gridColumnCount,
  );
  final prefetchCount = firstScreenCount * 2;

  void promote(String workId, ShelfCoverWarmupPriority priority) {
    final current = priorityByWorkId[workId];
    if (current == null || priority.index < current.index) {
      priorityByWorkId[workId] = priority;
    }
  }

  final visibleRange = visibleRangesByCategory[selectedCategoryId]?.normalized(
    selectedItems.length,
  );
  for (var index = 0; index < selectedItems.length; index++) {
    final item = selectedItems[index];
    if (visibleRange != null &&
        visibleRange.lastIndex >= visibleRange.firstIndex) {
      if (visibleRange.contains(index)) {
        promote(item.workId, ShelfCoverWarmupPriority.currentViewport);
      } else if (visibleRange.isNearAfter(index, prefetchCount)) {
        promote(item.workId, ShelfCoverWarmupPriority.nearViewport);
      } else {
        promote(item.workId, ShelfCoverWarmupPriority.background);
      }
      continue;
    }
    if (index < firstScreenCount) {
      promote(item.workId, ShelfCoverWarmupPriority.currentViewport);
    } else if (index < firstScreenCount + prefetchCount) {
      promote(item.workId, ShelfCoverWarmupPriority.nearViewport);
    } else {
      promote(item.workId, ShelfCoverWarmupPriority.background);
    }
  }

  if (selectedIndex >= 0) {
    for (final adjacentIndex in <int>[selectedIndex - 1, selectedIndex + 1]) {
      if (adjacentIndex < 0 || adjacentIndex >= categories.length) {
        continue;
      }
      final categoryId = categories[adjacentIndex].categoryId;
      final adjacentItems =
          itemsByCategory[categoryId] ?? const <LibraryWorkItem>[];
      for (
        var index = 0;
        index < adjacentItems.length && index < firstScreenCount;
        index++
      ) {
        promote(
          adjacentItems[index].workId,
          ShelfCoverWarmupPriority.adjacentCategory,
        );
      }
    }
  }

  return priorityByWorkId;
}

int _estimatedFirstScreenCount({
  required LibraryDisplayMode displayMode,
  required int gridColumnCount,
}) {
  switch (displayMode) {
    case LibraryDisplayMode.grid:
      final columns = gridColumnCount < 1 ? 1 : gridColumnCount;
      return columns * 4;
    case LibraryDisplayMode.list:
      return 8;
  }
}
