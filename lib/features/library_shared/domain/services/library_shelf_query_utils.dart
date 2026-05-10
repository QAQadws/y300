import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';

/// 书架 snapshot 查询后的共享内存筛选/排序工具。
///
/// 仓储层负责批量取足够字段；这里集中维护 UI 口径，避免漫画、小说、收藏
/// 三套实现各自复制一份 keyword/filter/sort 规则。
class LibraryShelfQueryUtils {
  const LibraryShelfQueryUtils._();

  static Map<String, List<LibraryWorkItem>> filterAndSortByCategory({
    required Map<String, List<LibraryWorkItem>> source,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) {
    return <String, List<LibraryWorkItem>>{
      for (final entry in source.entries)
        entry.key: filterAndSort(
          source: entry.value,
          filters: filters,
          sortOption: sortOption,
          keyword: keyword,
        ),
    };
  }

  static List<LibraryWorkItem> filterAndSort({
    required List<LibraryWorkItem> source,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) {
    final normalizedKeyword = keyword.trim().toLowerCase();
    final filtered = source.where((item) {
      return matchesKeyword(item, normalizedKeyword) && matchesFilters(item, filters);
    }).toList(growable: false);
    return sortItems(filtered, sortOption);
  }

  static bool matchesKeyword(LibraryWorkItem item, String normalizedKeyword) {
    if (normalizedKeyword.isEmpty) {
      return true;
    }
    final title = item.title.toLowerCase();
    final secondary = (item.secondaryName ?? '').toLowerCase();
    return title.contains(normalizedKeyword) || secondary.contains(normalizedKeyword);
  }

  static bool matchesFilters(LibraryWorkItem item, LibraryFilterSet filters) {
    return _matchesTriState(filters.downloaded, item.isDownloaded) &&
        _matchesTriState(filters.unread, item.unreadCount > 0) &&
        _matchesTriState(filters.read, item.readChapterCount > 0) &&
        _matchesTriState(filters.hasTags, item.hasTags);
  }

  static List<LibraryWorkItem> sortItems(
    List<LibraryWorkItem> source,
    LibraryShelfSortOption sortOption,
  ) {
    final items = List<LibraryWorkItem>.from(source);
    items.sort((a, b) {
      int cmp;
      switch (sortOption.field) {
        case LibraryShelfSortField.name:
          cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          break;
        case LibraryShelfSortField.chapterCount:
          cmp = a.totalChapterCount.compareTo(b.totalChapterCount);
          break;
        case LibraryShelfSortField.unreadCount:
          cmp = a.unreadCount.compareTo(b.unreadCount);
          break;
        case LibraryShelfSortField.workUpdatedAt:
          cmp = _dateOrEpoch(a.workUpdatedAt).compareTo(_dateOrEpoch(b.workUpdatedAt));
          break;
        case LibraryShelfSortField.fetchedAt:
          cmp = _dateOrEpoch(a.lastFetchedAt).compareTo(_dateOrEpoch(b.lastFetchedAt));
          break;
        case LibraryShelfSortField.lastCheckedAt:
          cmp = _dateOrEpoch(a.lastCheckedAt).compareTo(_dateOrEpoch(b.lastCheckedAt));
          break;
        case LibraryShelfSortField.lastReadAt:
          cmp = _dateOrEpoch(a.lastReadAt).compareTo(_dateOrEpoch(b.lastReadAt));
          break;
        case LibraryShelfSortField.favoriteAddedAt:
          cmp = a.addedAt.compareTo(b.addedAt);
          break;
      }
      return sortOption.direction == LibrarySortDirection.desc ? -cmp : cmp;
    });
    return List<LibraryWorkItem>.unmodifiable(items);
  }

  static Map<String, int> countByCategory(
    Map<String, List<LibraryWorkItem>> itemsByCategory,
  ) {
    return <String, int>{
      for (final entry in itemsByCategory.entries) entry.key: entry.value.length,
    };
  }

  static bool _matchesTriState(TriStateFilterValue value, bool actual) {
    switch (value) {
      case TriStateFilterValue.ignore:
        return true;
      case TriStateFilterValue.include:
        return actual;
      case TriStateFilterValue.exclude:
        return !actual;
    }
  }

  static DateTime _dateOrEpoch(DateTime? value) {
    return value ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
}
