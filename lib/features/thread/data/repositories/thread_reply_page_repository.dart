import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/thread/data/models/thread_reply_page.dart';
import 'package:y300/features/thread/data/repositories/thread_repository.dart';

/// JSON-only boundary for consumers that need top-level viewthread pages.
///
/// This deliberately does not use [threadRepositoryProvider], because that
/// provider is the HTML-first repository used by the native thread detail
/// page. The JSON provider keeps comment pagination independent of HTML cache
/// and HTML parser lifecycle.
abstract interface class ThreadReplyPageRepository {
  Future<ApiResult<ThreadReplyPage>> getReplyPage({
    required String tid,
    required int page,
  });
}

class ApiThreadReplyPageRepository implements ThreadReplyPageRepository {
  const ApiThreadReplyPageRepository({required ThreadRepository repository})
    : _repository = repository;

  final ThreadRepository _repository;

  @override
  Future<ApiResult<ThreadReplyPage>> getReplyPage({
    required String tid,
    required int page,
  }) async {
    if (page < 1) {
      return const ApiFailure<ThreadReplyPage>(
        ApiError(
          type: ApiErrorType.business,
          message: '回帖页码必须从 1 开始',
          code: 'invalid_page',
        ),
      );
    }

    final result = await _repository.getThreadDetail(tid: tid, page: page);
    return result.when(
      success: (data) =>
          ApiSuccess<ThreadReplyPage>(ThreadReplyPage.fromThreadDetail(data)),
      failure: ApiFailure.new,
    );
  }
}

final threadReplyPageRepositoryProvider = Provider<ThreadReplyPageRepository>((
  ref,
) {
  return ApiThreadReplyPageRepository(
    repository: ref.watch(threadJsonRepositoryProvider),
  );
});
