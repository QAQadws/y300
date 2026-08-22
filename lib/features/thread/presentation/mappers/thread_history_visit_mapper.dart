import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/services/forum_post_image_source_collector.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';

class ThreadHistoryVisitMapper {
  const ThreadHistoryVisitMapper({
    ForumPostImageSourceCollector imageSourceCollector =
        const ForumPostImageSourceCollector(),
  }) : _imageSourceCollector = imageSourceCollector;

  final ForumPostImageSourceCollector _imageSourceCollector;

  HistoryVisitDraft map({
    required ThreadDetailPageState state,
    required String routeTid,
    String? routeSubject,
    String? routeForumName,
    int? routePage,
  }) {
    final tid = _nonEmpty(state.tid) ?? _nonEmpty(routeTid) ?? '';
    final page = state.currentPage > 0
        ? state.currentPage
        : (routePage != null && routePage > 0 ? routePage : null);
    final forumName = _nonEmpty(state.forumName) ?? _nonEmpty(routeForumName);
    final firstPost = _firstFloor(state.posts);
    final firstPostImageUrl = firstPost == null
        ? null
        : _firstOrNull(_imageSourceCollector.collect(firstPost));

    return HistoryVisitDraft(
      target: HistoryTargetKey(type: HistoryTargetType.thread, id: tid),
      surface: HistoryVisitSurface.threadNative,
      title: _nonEmpty(state.subject) ?? _nonEmpty(routeSubject),
      contextLabel:
          forumName ?? (page != null && page > 1 ? '第 $page 页' : null),
      thumbnail: firstPostImageUrl == null
          ? null
          : HistoryThumbnailSnapshot(remoteUrl: firstPostImageUrl),
      canonicalUri:
          _resolveForumUrl(state.desktopUrl) ?? _fallbackThreadUri(tid, page),
      page: page,
      forumName: forumName,
    );
  }

  ThreadPost? _firstFloor(List<ThreadPost> posts) {
    for (final post in posts) {
      if (post.isFirst || post.number == 1) {
        return post;
      }
    }
    return null;
  }

  String? _firstOrNull(List<String> values) {
    return values.isEmpty ? null : values.first;
  }

  Uri? _resolveForumUrl(String? value) {
    final normalized = _nonEmpty(value);
    if (normalized == null) {
      return null;
    }
    final parsed = Uri.tryParse(normalized);
    if (parsed == null) {
      return null;
    }
    return Uri.parse(AppConfig.siteBaseUrl).resolveUri(parsed);
  }

  Uri? _fallbackThreadUri(String tid, int? page) {
    if (tid.isEmpty) {
      return null;
    }
    return Uri.parse(AppConfig.siteBaseUrl).replace(
      path: '/forum.php',
      queryParameters: <String, String>{
        'mod': 'viewthread',
        'tid': tid,
        if (page != null && page > 1) 'page': page.toString(),
      },
    );
  }

  String? _nonEmpty(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
