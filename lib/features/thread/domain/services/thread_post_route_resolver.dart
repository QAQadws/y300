import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/thread/domain/models/thread_post_target.dart';
import 'package:y300/features/thread/domain/repositories/thread_post_locator.dart';
import 'package:y300/features/thread/domain/services/thread_floor_link_builder.dart';

final class ThreadPostRouteResolver {
  const ThreadPostRouteResolver(this.locator);

  final ThreadPostLocator locator;

  Future<ApiResult<ThreadPostLocation>> resolve(ThreadPostTarget target) async {
    if (!target.isValid) return _failure('thread_post_target_invalid');
    final uri = ThreadFloorLinkBuilder().build(
      tid: target.tid,
      pid: target.pid,
    )!;
    if (target.pageHint case final int page) {
      return ApiSuccess(
        ThreadPostLocation(
          tid: target.tid,
          pid: target.pid,
          page: page,
          url: uri.toString(),
        ),
      );
    }
    try {
      final result = await locator.locate(
        tid: target.tid,
        pid: target.pid,
        sourceUri: uri,
      );
      final location = result.dataOrNull;
      if (location != null &&
          (location.tid.trim() != target.tid ||
              location.pid.trim() != target.pid ||
              location.page < 1)) {
        return _failure('thread_post_location_identity_mismatch');
      }
      return result;
    } catch (_) {
      return _failure('thread_post_location_failed');
    }
  }

  ApiFailure<ThreadPostLocation> _failure(String code) =>
      ApiFailure(ApiError(type: ApiErrorType.parse, message: code, code: code));
}
