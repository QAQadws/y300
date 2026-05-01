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
