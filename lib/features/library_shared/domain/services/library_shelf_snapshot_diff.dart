import 'package:y300/features/library_shared/domain/models/library_models.dart';

class LibraryShelfSnapshotDiff {
  const LibraryShelfSnapshotDiff({
    required this.addedWorkIds,
    required this.removedWorkIds,
    required this.changedWorkIds,
    required this.orderChangedCategoryIds,
  });

  final Set<String> addedWorkIds;
  final Set<String> removedWorkIds;
  final Set<String> changedWorkIds;
  final Set<String> orderChangedCategoryIds;

  bool get hasChanges {
    return addedWorkIds.isNotEmpty ||
        removedWorkIds.isNotEmpty ||
        changedWorkIds.isNotEmpty ||
        orderChangedCategoryIds.isNotEmpty;
  }
}

/// Computes the minimum shelf-level changes needed to decide whether a reload
/// is just a stale-while-revalidate refresh or a meaningful metadata update.
class LibraryShelfSnapshotDiffer {
  const LibraryShelfSnapshotDiffer();

  LibraryShelfSnapshotDiff diff({
    required LibraryShelfSnapshot previous,
    required LibraryShelfSnapshot next,
  }) {
    final previousItems = _itemsByWorkId(previous.itemsByCategory);
    final nextItems = _itemsByWorkId(next.itemsByCategory);
    final previousIds = previousItems.keys.toSet();
    final nextIds = nextItems.keys.toSet();

    final added = nextIds.difference(previousIds);
    final removed = previousIds.difference(nextIds);
    final changed = <String>{};
    for (final workId in previousIds.intersection(nextIds)) {
      if (!_sameMetadata(previousItems[workId]!, nextItems[workId]!)) {
        changed.add(workId);
      }
    }

    final orderChanged = <String>{};
    final categoryIds = <String>{
      ...previous.itemsByCategory.keys,
      ...next.itemsByCategory.keys,
    };
    for (final categoryId in categoryIds) {
      final previousOrder =
          previous.itemsByCategory[categoryId]
              ?.map((item) => item.workId)
              .toList() ??
          const <String>[];
      final nextOrder =
          next.itemsByCategory[categoryId]
              ?.map((item) => item.workId)
              .toList() ??
          const <String>[];
      if (!_sameStringList(previousOrder, nextOrder)) {
        orderChanged.add(categoryId);
      }
    }

    return LibraryShelfSnapshotDiff(
      addedWorkIds: added,
      removedWorkIds: removed,
      changedWorkIds: changed,
      orderChangedCategoryIds: orderChanged,
    );
  }

  Map<String, LibraryWorkItem> _itemsByWorkId(
    Map<String, List<LibraryWorkItem>> itemsByCategory,
  ) {
    final result = <String, LibraryWorkItem>{};
    for (final items in itemsByCategory.values) {
      for (final item in items) {
        result[item.workId] = item;
      }
    }
    return result;
  }

  bool _sameMetadata(LibraryWorkItem a, LibraryWorkItem b) {
    return a.categoryId == b.categoryId &&
        a.title == b.title &&
        a.secondaryName == b.secondaryName &&
        a.coverImageUrl == b.coverImageUrl &&
        a.customCoverImageUrl == b.customCoverImageUrl &&
        a.coverLocalPath == b.coverLocalPath &&
        a.customCoverLocalPath == b.customCoverLocalPath &&
        a.customCoverFocusX == b.customCoverFocusX &&
        a.customCoverFocusY == b.customCoverFocusY &&
        a.unreadCount == b.unreadCount &&
        a.totalChapterCount == b.totalChapterCount &&
        a.readChapterCount == b.readChapterCount &&
        a.addedAt == b.addedAt &&
        a.lastReadAt == b.lastReadAt &&
        a.workUpdatedAt == b.workUpdatedAt &&
        a.lastCheckedAt == b.lastCheckedAt &&
        a.lastFetchedAt == b.lastFetchedAt &&
        a.hasTags == b.hasTags &&
        a.hasBookmarks == b.hasBookmarks &&
        a.isDownloaded == b.isDownloaded;
  }

  bool _sameStringList(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
