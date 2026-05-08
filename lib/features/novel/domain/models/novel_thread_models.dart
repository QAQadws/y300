import 'package:y300/features/novel/domain/models/novel_parsing_models.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

class NovelEpisodeDraft {
  const NovelEpisodeDraft({
    required this.episodeId,
    required this.novelId,
    required this.sourceTid,
    required this.sourcePid,
    required this.sourcePage,
    required this.episodeTitle,
    required this.orderIndex,
    required this.datelineText,
    required this.rawHtml,
    required this.plainText,
    required this.paragraphs,
    this.imageUrls = const <String>[],
  });

  final String episodeId;
  final String novelId;
  final String sourceTid;
  final String sourcePid;
  final int sourcePage;
  final String episodeTitle;
  final int orderIndex;
  final String datelineText;
  final String rawHtml;
  final String plainText;
  final List<String> paragraphs;
  final List<String> imageUrls;
}

class NovelRefreshPlan {
  const NovelRefreshPlan({
    required this.tid,
    required this.subject,
    required this.author,
    required this.episodes,
    this.intro,
    this.coverImageUrl,
    this.inlineImageUrls = const <String>[],
    this.debugInfo,
  });

  final String tid;
  final String subject;
  final String author;
  final List<NovelEpisodeDraft> episodes;
  final String? intro;
  final String? coverImageUrl;
  final List<String> inlineImageUrls;
  final NovelParsingDebugInfo? debugInfo;
}

abstract class NovelThreadGateway {
  Future<ThreadDetailData> getThreadDetail({required String tid, required int page});
}
