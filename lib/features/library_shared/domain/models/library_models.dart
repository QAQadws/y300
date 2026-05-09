/// 模块标识：用于区分漫画与小说的默认行为差异。
enum LibraryModuleKey {
  comic,
  novel,
  favorite,
}

/// 作品展示方式：网格或列表。
enum LibraryDisplayMode {
  grid,
  list,
}

/// 标签模型。
class LibraryTag {
  const LibraryTag({
    required this.tagId,
    required this.name,
    required this.createdAt,
  });

  final String tagId;
  final String name;
  final DateTime createdAt;
}

/// 通用分类模型。
class LibraryCategory {
  const LibraryCategory({
    required this.categoryId,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
    this.visibleMatchCount = 0,
  });

  final String categoryId;
  final String name;
  final int sortOrder;
  final DateTime createdAt;

  /// 搜索模式下该分类命中数。
  final int visibleMatchCount;

  bool get isDefault => categoryId == 'default';

  LibraryCategory copyWith({
    String? categoryId,
    String? name,
    int? sortOrder,
    DateTime? createdAt,
    int? visibleMatchCount,
  }) {
    return LibraryCategory(
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      visibleMatchCount: visibleMatchCount ?? this.visibleMatchCount,
    );
  }
}

/// 统一书架“作品卡片”最小视图模型。
///
/// - [secondaryName]：漫画可放汉化组，小说可放作者。
/// - [unreadCount]：用于网格左上角/列表右侧角标。
class LibraryWorkItem {
  const LibraryWorkItem({
    required this.workId,
    required this.categoryId,
    required this.title,
    this.secondaryName,
    this.coverImageUrl,
    this.coverLocalPath,
    this.customCoverLocalPath,
    required this.unreadCount,
    required this.totalChapterCount,
    required this.readChapterCount,
    required this.addedAt,
    this.lastReadAt,
    this.workUpdatedAt,
    this.lastCheckedAt,
    this.lastFetchedAt,
    this.hasTags = false,
    this.isDownloaded = false,
  });

  final String workId;
  final String categoryId;
  final String title;
  final String? secondaryName;
  final String? coverImageUrl;
  final String? coverLocalPath;
  final String? customCoverLocalPath;
  final int unreadCount;
  final int totalChapterCount;
  final int readChapterCount;
  final DateTime addedAt;
  final DateTime? lastReadAt;
  final DateTime? workUpdatedAt;
  final DateTime? lastCheckedAt;
  final DateTime? lastFetchedAt;
  final bool hasTags;
  final bool isDownloaded;
}

/// 统一详情页头部信息模型。
class LibraryDetailHeader {
  const LibraryDetailHeader({
    required this.workId,
    required this.title,
    this.coverImageUrl,
    this.coverLocalPath,
    this.customCoverLocalPath,
    this.author,
    this.translationGroup,
    this.intro,
    this.sourceTid,
    this.sourceTypeId,
    this.sourceTagName,
    this.customTags = const <LibraryTag>[],
    required this.inShelf,
  });

  final String workId;
  final String title;
  final String? coverImageUrl;
  final String? coverLocalPath;
  final String? customCoverLocalPath;
  final String? author;
  final String? translationGroup;
  final String? intro;
  final String? sourceTid;
  final String? sourceTypeId;
  final String? sourceTagName;
  final List<LibraryTag> customTags;
  final bool inShelf;
}

/// 通用章节行模型。
class LibraryChapterItem {
  const LibraryChapterItem({
    required this.episodeId,
    required this.workId,
    required this.title,
    required this.orderIndex,
    this.sourceTid,
    this.sourcePid,
    this.publishTimeText,
    this.threadPostDateText,
    this.threadTidText,
    this.isRead = false,
    this.isDownloaded = false,
    this.isBookmarked = false,
  });

  final String episodeId;
  final String workId;
  final String title;
  final int orderIndex;
  final String? sourceTid;
  final String? sourcePid;
  final String? publishTimeText;
  final String? threadPostDateText;
  final String? threadTidText;
  final bool isRead;
  final bool isDownloaded;
  final bool isBookmarked;
}
