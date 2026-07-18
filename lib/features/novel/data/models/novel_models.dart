import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';

export 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';

class NovelItem {
  const NovelItem({
    required this.novelId,
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
    this.coverHidden = false,
    required this.updatedAt,
    required this.episodeCount,
    this.categoryId = 'default',
  });

  final String novelId;
  final String sourceTid;
  final String sourceFid;
  final String? sourceTypeId;
  final String? sourceTagName;
  final String title;

  /// 来源发布者名称；小说详情不额外维护作品作者或翻译者。
  final String? author;
  final String? customTitle;
  final String? coverImageUrl;
  final String? coverLocalPath;
  final String? customCoverLocalPath;
  final double? customCoverFocusX;
  final double? customCoverFocusY;
  final bool coverHidden;
  final DateTime updatedAt;
  final int episodeCount;
  final String categoryId;

  String get sourceTitle => title;

  String get displayTitle =>
      _preferredText(customTitle, sourceTitle) ?? sourceTitle;

  String? get publisherName => _preferredText(author, null);
}

String? _preferredText(String? preferred, String? fallback) {
  final normalizedPreferred = preferred?.trim();
  if (normalizedPreferred != null && normalizedPreferred.isNotEmpty) {
    return normalizedPreferred;
  }
  final normalizedFallback = fallback?.trim();
  return normalizedFallback == null || normalizedFallback.isEmpty
      ? null
      : normalizedFallback;
}

class NovelEpisodeItem {
  const NovelEpisodeItem({
    required this.episodeId,
    required this.novelId,
    required this.sourceTid,
    this.sourcePid,
    this.sourcePage,
    required this.episodeTitle,
    required this.orderIndex,
    this.datelineText,
  });

  final String episodeId;
  final String novelId;
  final String sourceTid;
  final String? sourcePid;
  final int? sourcePage;
  final String episodeTitle;
  final int orderIndex;
  final String? datelineText;
}

class NovelChapterContent {
  const NovelChapterContent({
    required this.episodeId,
    required this.rawHtml,
    required this.plainText,
    required this.paragraphs,
  });

  final String episodeId;
  final String rawHtml;
  final String plainText;
  final List<String> paragraphs;
}

class NovelReadingProgress {
  const NovelReadingProgress({
    required this.novelId,
    required this.episodeId,
    required this.scrollOffset,
    required this.updatedAt,
    this.flowMode = NovelReaderFlowMode.vertical,
    this.pageIndex = 0,
    this.anchorNodeId,
    this.progressPercent = 0,
  });

  final String novelId;
  final String episodeId;
  final double scrollOffset;
  final DateTime updatedAt;
  final NovelReaderFlowMode flowMode;
  final int pageIndex;
  final String? anchorNodeId;
  final double progressPercent;
}

class NovelEpisodeRefreshResult {
  const NovelEpisodeRefreshResult({
    required this.insertedCount,
    required this.updatedCount,
    required this.totalCount,
  });

  final int insertedCount;
  final int updatedCount;
  final int totalCount;
}

class NovelRefreshSeed extends NovelSourceSeed {
  const NovelRefreshSeed({
    required super.fid,
    required super.tid,
    super.typeid,
    super.tagName,
  });
}

class NovelShelfCategory {
  const NovelShelfCategory({
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
