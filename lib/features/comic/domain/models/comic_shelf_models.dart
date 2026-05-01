class ComicShelfItem {
  const ComicShelfItem({
    required this.comicId,
    required this.title,
    required this.author,
    required this.coverImageUrl,
    required this.categoryId,
    required this.addedAt,
  });

  final String comicId;
  final String title;
  final String? author;
  final String? coverImageUrl;
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

