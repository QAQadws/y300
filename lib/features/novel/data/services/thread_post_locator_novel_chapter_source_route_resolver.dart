import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/novel/domain/models/novel_interaction_models.dart';
import 'package:y300/features/novel/domain/services/novel_chapter_source_route_resolver.dart';
import 'package:y300/features/thread/data/services/thread_post_locator.dart';
import 'package:y300/features/thread/domain/models/thread_post_target.dart';
import 'package:y300/features/thread/domain/services/thread_post_route_resolver.dart';

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
    late final ApiResult<ThreadPostLocation> result;
    try {
      result = await ThreadPostRouteResolver(
        _locator,
      ).resolve(ThreadPostTarget(tid: tid, pid: pid));
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
