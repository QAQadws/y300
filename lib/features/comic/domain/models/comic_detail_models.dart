class ComicDetail {
  const ComicDetail({
    required this.comicId,
    required this.sourceTid,
    required this.sourceFid,
    required this.title,
    required this.author,
    required this.coverImageUrl,
    required this.updatedAt,
    required this.episodeCount,
  });

  final String comicId;
  final String sourceTid;
  final String sourceFid;
  final String title;
  final String? author;
  final String? coverImageUrl;
  final DateTime updatedAt;
  final int episodeCount;
}

class ComicEpisodeItem {
  const ComicEpisodeItem({
    required this.episodeId,
    required this.comicId,
    required this.episodeTitle,
    required this.sourceTid,
    required this.sourceUrl,
    required this.orderIndex,
    required this.publishTimeText,
  });

  final String episodeId;
  final String comicId;
  final String? episodeTitle;
  final String sourceTid;
  final String sourceUrl;
  final int orderIndex;
  final String? publishTimeText;
}

class ComicEpisodeRefreshResult {
  const ComicEpisodeRefreshResult({
    required this.insertedCount,
    required this.updatedCount,
    required this.totalCount,
  });

  final int insertedCount;
  final int updatedCount;
  final int totalCount;
}
