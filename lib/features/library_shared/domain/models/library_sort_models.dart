/// 书架层排序字段。
enum LibraryShelfSortField {
  name,
  chapterCount,
  lastReadAt,
  lastCheckedAt,
  unreadCount,
  workUpdatedAt,
  fetchedAt,
  favoriteAddedAt,
}

/// 详情章节层排序字段。
enum LibraryChapterSortField {
  chapterIndex,
  date,
  name,
  tid,
}

/// 通用排序方向。
enum LibrarySortDirection {
  asc,
  desc,
}

/// 书架排序配置。
class LibraryShelfSortOption {
  const LibraryShelfSortOption({
    required this.field,
    this.direction = LibrarySortDirection.desc,
  });

  final LibraryShelfSortField field;
  final LibrarySortDirection direction;

  static const LibraryShelfSortOption defaults = LibraryShelfSortOption(
    field: LibraryShelfSortField.favoriteAddedAt,
    direction: LibrarySortDirection.desc,
  );

  LibraryShelfSortOption copyWith({
    LibraryShelfSortField? field,
    LibrarySortDirection? direction,
  }) {
    return LibraryShelfSortOption(
      field: field ?? this.field,
      direction: direction ?? this.direction,
    );
  }
}

/// 章节排序配置。
class LibraryChapterSortOption {
  const LibraryChapterSortOption({
    required this.field,
    this.direction = LibrarySortDirection.asc,
  });

  final LibraryChapterSortField field;
  final LibrarySortDirection direction;

  static const LibraryChapterSortOption defaults = LibraryChapterSortOption(
    field: LibraryChapterSortField.chapterIndex,
    direction: LibrarySortDirection.asc,
  );
}
