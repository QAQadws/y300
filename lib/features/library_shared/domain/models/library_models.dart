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

/// 统一书架的元数据快照。
///
/// Snapshot 是 Milestone B 的查询边界：适配器/仓储一次性返回 UI 首屏所需
/// 的分类、作品和搜索命中数，避免控制器再按分类或按作品触发多轮查询。
class LibraryShelfSnapshot {
  const LibraryShelfSnapshot({
    required this.categories,
    required this.itemsByCategory,
    required this.visibleMatchCountByCategory,
  });

  final List<LibraryCategory> categories;
  final Map<String, List<LibraryWorkItem>> itemsByCategory;
  final Map<String, int> visibleMatchCountByCategory;
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
    this.customCoverImageUrl,
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
  final String? customCoverImageUrl;
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

  LibraryWorkItem copyWith({
    String? title,
    String? secondaryName,
    String? coverImageUrl,
    String? customCoverImageUrl,
    String? coverLocalPath,
    String? customCoverLocalPath,
    int? unreadCount,
    int? totalChapterCount,
    int? readChapterCount,
    DateTime? addedAt,
    DateTime? lastReadAt,
    DateTime? workUpdatedAt,
    DateTime? lastCheckedAt,
    DateTime? lastFetchedAt,
    bool? hasTags,
    bool? isDownloaded,
    bool clearCoverLocalPath = false,
    bool clearCustomCoverLocalPath = false,
  }) {
    return LibraryWorkItem(
      workId: workId,
      categoryId: categoryId,
      title: title ?? this.title,
      secondaryName: secondaryName ?? this.secondaryName,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      customCoverImageUrl: customCoverImageUrl ?? this.customCoverImageUrl,
      coverLocalPath: clearCoverLocalPath ? null : (coverLocalPath ?? this.coverLocalPath),
      customCoverLocalPath: clearCustomCoverLocalPath
          ? null
          : (customCoverLocalPath ?? this.customCoverLocalPath),
      unreadCount: unreadCount ?? this.unreadCount,
      totalChapterCount: totalChapterCount ?? this.totalChapterCount,
      readChapterCount: readChapterCount ?? this.readChapterCount,
      addedAt: addedAt ?? this.addedAt,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      workUpdatedAt: workUpdatedAt ?? this.workUpdatedAt,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
      hasTags: hasTags ?? this.hasTags,
      isDownloaded: isDownloaded ?? this.isDownloaded,
    );
  }
}

/// 统一详情页头部信息模型。
class LibraryDetailHeader {
  const LibraryDetailHeader({
    required this.workId,
    required this.title,
    this.coverImageUrl,
    this.customCoverImageUrl,
    this.coverLocalPath,
    this.customCoverLocalPath,
    this.author,
    this.sourceAuthor,
    this.customAuthor,
    this.translationGroup,
    this.sourceTitle,
    this.customTitle,
    this.sourceTranslationGroup,
    this.customTranslationGroup,
    this.customSearchTitle,
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
  final String? customCoverImageUrl;
  final String? coverLocalPath;
  final String? customCoverLocalPath;
  final String? author;
  final String? sourceAuthor;
  final String? customAuthor;
  final String? translationGroup;
  final String? sourceTitle;
  final String? customTitle;
  final String? sourceTranslationGroup;
  final String? customTranslationGroup;
  final String? customSearchTitle;
  final String? intro;
  final String? sourceTid;
  final String? sourceTypeId;
  final String? sourceTagName;
  final List<LibraryTag> customTags;
  final bool inShelf;
}

/// 通用章节阅读进度展示模型。
class LibraryChapterProgressInfo {
  const LibraryChapterProgressInfo({
    required this.label,
    required this.isCurrent,
    this.fraction,
    this.semanticLabel,
  });

  final String label;
  final bool isCurrent;
  final double? fraction;
  final String? semanticLabel;
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
    this.progressInfo,
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
  final LibraryChapterProgressInfo? progressInfo;
}
