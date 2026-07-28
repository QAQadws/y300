import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/novel/domain/models/novel_interaction_models.dart';
import 'package:y300/features/novel/domain/services/novel_chapter_source_route_resolver.dart';
import 'package:y300/features/thread/data/services/thread_post_locator.dart';

class ThreadPostLocatorNovelChapterSourceRouteResolver
    implements NovelChapterSourceRouteResolver {
  const ThreadPostLocatorNovelChapterSourceRouteResolver({
    required ThreadPostLocator locator,
  }) : _locator = locator;

  final ThreadPostLocator _locator;

  @override
  Future<NovelChapterSourceRoute> resolve(
    NovelChapterSourceReference reference,
  ) async {
    final tid = _requirePositiveId(
      reference.tid,
      NovelChapterSourceRouteFailureCode.invalidTid,
    );
    final pid = _requirePositiveId(
      reference.pid,
      NovelChapterSourceRouteFailureCode.invalidPid,
    );
    final sourceUri = Uri.parse('${AppConfig.siteBaseUrl}/forum.php').replace(
      queryParameters: <String, String>{
        'mod': 'redirect',
        'goto': 'findpost',
        'ptid': tid,
        'pid': pid,
      },
    );
    late final ApiResult<ThreadPostLocation> result;
    try {
      result = await _locator.locate(tid: tid, pid: pid, sourceUri: sourceUri);
    } catch (error) {
      throw NovelChapterSourceRouteException(
        NovelChapterSourceRouteFailureCode.locatorFailed,
        detail: error,
      );
    }
    final location = result.dataOrNull;
    if (!result.isSuccess || location == null) {
      throw NovelChapterSourceRouteException(
        NovelChapterSourceRouteFailureCode.emptyResult,
        detail: result.errorOrNull,
      );
    }
    if (location.tid.trim() != tid || location.pid.trim() != pid) {
      throw const NovelChapterSourceRouteException(
        NovelChapterSourceRouteFailureCode.mismatchedResult,
      );
    }
    if (location.page < 1) {
      throw const NovelChapterSourceRouteException(
        NovelChapterSourceRouteFailureCode.invalidPage,
      );
    }
    return NovelChapterSourceRoute(
      tid: tid,
      pid: pid,
      page: location.page,
      url: location.url,
    );
  }

  String _requirePositiveId(
    String value,
    NovelChapterSourceRouteFailureCode failureCode,
  ) {
    final normalized = value.trim();
    if (!RegExp(r'^[1-9]\d*$').hasMatch(normalized)) {
      throw NovelChapterSourceRouteException(failureCode);
    }
    return normalized;
  }
}
