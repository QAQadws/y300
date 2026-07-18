import 'package:flutter/foundation.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';

/// Fixed-size device preferences for one public shelf module.
@immutable
final class LibraryShelfViewPreferences {
  const LibraryShelfViewPreferences({
    required this.moduleKey,
    required this.displayMode,
    required this.gridColumnCount,
    required this.sortOption,
    required this.filters,
    this.lastCategoryId,
  });

  factory LibraryShelfViewPreferences.defaults({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode displayMode,
    required LibraryShelfSortOption sortOption,
  }) {
    return LibraryShelfViewPreferences(
      moduleKey: moduleKey,
      displayMode: displayMode,
      gridColumnCount: 3,
      sortOption: sortOption,
      filters: LibraryFilterSet.defaults,
    );
  }

  final LibraryModuleKey moduleKey;
  final LibraryDisplayMode displayMode;
  final int gridColumnCount;
  final LibraryShelfSortOption sortOption;
  final LibraryFilterSet filters;
  final String? lastCategoryId;

  LibraryShelfViewPreferences copyWith({
    LibraryDisplayMode? displayMode,
    int? gridColumnCount,
    LibraryShelfSortOption? sortOption,
    LibraryFilterSet? filters,
    String? lastCategoryId,
    bool clearLastCategoryId = false,
  }) {
    return LibraryShelfViewPreferences(
      moduleKey: moduleKey,
      displayMode: displayMode ?? this.displayMode,
      gridColumnCount: gridColumnCount ?? this.gridColumnCount,
      sortOption: sortOption ?? this.sortOption,
      filters: filters ?? this.filters,
      lastCategoryId: clearLastCategoryId
          ? null
          : (lastCategoryId ?? this.lastCategoryId),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LibraryShelfViewPreferences &&
        other.moduleKey == moduleKey &&
        other.displayMode == displayMode &&
        other.gridColumnCount == gridColumnCount &&
        other.sortOption.field == sortOption.field &&
        other.sortOption.direction == sortOption.direction &&
        other.filters.downloaded == filters.downloaded &&
        other.filters.unread == filters.unread &&
        other.filters.read == filters.read &&
        other.filters.hasTags == filters.hasTags &&
        other.filters.bookmarked == filters.bookmarked &&
        other.lastCategoryId == lastCategoryId;
  }

  @override
  int get hashCode => Object.hash(
    moduleKey,
    displayMode,
    gridColumnCount,
    sortOption.field,
    sortOption.direction,
    filters.downloaded,
    filters.unread,
    filters.read,
    filters.hasTags,
    filters.bookmarked,
    lastCategoryId,
  );
}
