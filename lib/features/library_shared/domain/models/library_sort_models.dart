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

/// 通用排序方向。
enum LibrarySortDirection { asc, desc }

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
    direction: LibrarySortDirection.asc,
  );

  /// 公共书架允许用户选择的排序字段，顺序同时作为排序面板展示顺序。
  static const List<LibraryShelfSortField> availableFields =
      <LibraryShelfSortField>[
        LibraryShelfSortField.chapterCount,
        LibraryShelfSortField.unreadCount,
        LibraryShelfSortField.favoriteAddedAt,
      ];

  static LibraryShelfSortOption normalize(LibraryShelfSortOption option) {
    return availableFields.contains(option.field) ? option : defaults;
  }

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
///
/// 公共作品详情仅支持“按来源”：漫画由 adapter 按 TID 排序，小说由
/// adapter 按 PID 排序。共享层只负责编排排序方向。
class LibraryChapterSortOption {
  const LibraryChapterSortOption({this.direction = LibrarySortDirection.asc});

  final LibrarySortDirection direction;

  static const LibraryChapterSortOption defaults = LibraryChapterSortOption(
    direction: LibrarySortDirection.asc,
  );
}
