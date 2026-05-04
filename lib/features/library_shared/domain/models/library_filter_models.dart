/// 三态筛选值。
enum TriStateFilterValue {
  /// 不参与筛选。
  ignore,

  /// 只保留满足条件的数据。
  include,

  /// 排除满足条件的数据。
  exclude,
}

/// 通用筛选开关集合。
class LibraryFilterSet {
  const LibraryFilterSet({
    this.downloaded = TriStateFilterValue.ignore,
    this.unread = TriStateFilterValue.ignore,
    this.read = TriStateFilterValue.ignore,
    this.hasTags = TriStateFilterValue.ignore,
    this.bookmarked = TriStateFilterValue.ignore,
  });

  final TriStateFilterValue downloaded;
  final TriStateFilterValue unread;
  final TriStateFilterValue read;
  final TriStateFilterValue hasTags;
  final TriStateFilterValue bookmarked;

  static const LibraryFilterSet defaults = LibraryFilterSet();

  bool get isDefault =>
      downloaded == TriStateFilterValue.ignore &&
      unread == TriStateFilterValue.ignore &&
      read == TriStateFilterValue.ignore &&
      hasTags == TriStateFilterValue.ignore &&
      bookmarked == TriStateFilterValue.ignore;

  LibraryFilterSet copyWith({
    TriStateFilterValue? downloaded,
    TriStateFilterValue? unread,
    TriStateFilterValue? read,
    TriStateFilterValue? hasTags,
    TriStateFilterValue? bookmarked,
  }) {
    return LibraryFilterSet(
      downloaded: downloaded ?? this.downloaded,
      unread: unread ?? this.unread,
      read: read ?? this.read,
      hasTags: hasTags ?? this.hasTags,
      bookmarked: bookmarked ?? this.bookmarked,
    );
  }
}
