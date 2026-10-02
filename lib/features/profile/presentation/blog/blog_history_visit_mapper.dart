import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/history/domain/models/blog_history_target.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

class BlogHistoryVisitMapper {
  const BlogHistoryVisitMapper({this.siteBaseUrl = AppConfig.siteBaseUrl});

  final String siteBaseUrl;

  HistoryVisitDraft map({
    required UserBlogDetailData data,
    UserBlogNavigation? navigation,
  }) {
    final target = BlogHistoryTarget(
      ownerUserId: data.ownerUserId,
      blogId: data.blogId,
    );
    final images = DefaultForumImageSourcePipeline.collectDomImageSources(
      data.bodyHtml,
      siteBaseUrl: siteBaseUrl,
    );
    return HistoryVisitDraft(
      target: target.key,
      surface: HistoryVisitSurface.blogDetail,
      title: data.title,
      contextLabel: data.authorName,
      thumbnail: images.isEmpty
          ? null
          : HistoryThumbnailSnapshot(remoteUrl: images.first.normalizedUrl),
      canonicalUri: navigation?.detail(
        UserBlogDetailQuery(
          ownerUserId: target.ownerUserId,
          blogId: target.blogId,
        ),
      ),
    );
  }
}
