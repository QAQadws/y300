class ComicShelfItem {
  const ComicShelfItem({
    required this.comicId,
    this.sourceTypeId,
    this.sourceTagName,
    required this.title,
    this.sourceTitle,
    this.customTitle,
    required this.author,
    this.sourceAuthor,
    this.customAuthor,
    this.translationGroup,
    this.sourceTranslationGroup,
    this.customTranslationGroup,
    this.customSearchTitle,
    required this.coverImageUrl,
    this.customCoverImageUrl,
    this.coverLocalPath,
    this.customCoverLocalPath,
    required this.categoryId,
    required this.addedAt,
  });

  final String comicId;
  final String? sourceTypeId;
  final String? sourceTagName;
  /// 最终展示标题。自定义标题由仓储提前合成到这里。
  final String title;
  final String? sourceTitle;
  final String? customTitle;
  /// 最终展示作者。自定义作者由仓储提前合成到这里。
  final String? author;
  final String? sourceAuthor;
  final String? customAuthor;
  final String? translationGroup;
  final String? sourceTranslationGroup;
  final String? customTranslationGroup;
  final String? customSearchTitle;
  final String? coverImageUrl;
  final String? customCoverImageUrl;
  final String? coverLocalPath;
  final String? customCoverLocalPath;
  final String categoryId;
  final DateTime addedAt;
}

class ComicShelfCategory {
  const ComicShelfCategory({
    required this.categoryId,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
  });

  final String categoryId;
  final String name;
  final int sortOrder;
  final DateTime createdAt;

  bool get isDefault => categoryId == 'default';
}

class ComicShelfDisplaySettings {
  const ComicShelfDisplaySettings({
    required this.gridColumnCount,
  });

  final int gridColumnCount;

  static const ComicShelfDisplaySettings defaults = ComicShelfDisplaySettings(
    gridColumnCount: 3,
  );
}

