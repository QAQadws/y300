/// 本地 works 表记录。
class NovelWorkRecord {
  const NovelWorkRecord({
    required this.workId,
    required this.contentType,
    required this.sourceTid,
    required this.sourceFid,
    this.sourceTypeId,
    this.sourceTagName,
    required this.title,
    this.author,
    this.customTitle,
    this.coverImageUrl,
    this.coverLocalPath,
    this.customCoverLocalPath,
    this.customCoverFocusX,
    this.customCoverFocusY,
    required this.updatedAt,
  });

  final String workId;
  final String contentType;
  final String sourceTid;
  final String sourceFid;
  final String? sourceTypeId;
  final String? sourceTagName;
  final String title;
  final String? author;
  final String? customTitle;
  final String? coverImageUrl;
  final String? coverLocalPath;
  final String? customCoverLocalPath;
  final double? customCoverFocusX;
  final double? customCoverFocusY;
  final int updatedAt;
}

/// 本地 work_episodes 表记录。
class NovelEpisodeRecord {
  const NovelEpisodeRecord({
    required this.episodeId,
    required this.workId,
    required this.contentType,
    required this.sourceTid,
    this.sourcePid,
    this.sourcePage,
    this.episodeTitle,
    required this.orderIndex,
    this.datelineText,
  });

  final String episodeId;
  final String workId;
  final String contentType;
  final String sourceTid;
  final String? sourcePid;
  final int? sourcePage;
  final String? episodeTitle;
  final int orderIndex;
  final String? datelineText;
}
