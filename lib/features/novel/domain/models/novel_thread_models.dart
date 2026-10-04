import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

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

abstract interface class NovelThreadGateway {
  Future<ThreadDetailData> loadAuthorPostsPage({
    required String tid,
    required String authorId,
    required int page,
    int postsPerPage = 200,
  });
}

abstract interface class NovelSourceMetadataRecoveryGateway {
  Future<ThreadDetailData> loadFirstPage({required String tid});
}
