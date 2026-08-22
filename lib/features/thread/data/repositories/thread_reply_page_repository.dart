import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/thread/data/providers/thread_repository_providers.dart';
import 'package:y300/features/thread/domain/models/thread_reply_page.dart';
import 'package:y300/features/thread/domain/repositories/thread_reply_page_repository.dart';
import 'package:y300/features/thread/domain/repositories/thread_repository.dart';

class ApiThreadReplyPageRepository implements ThreadReplyPageRepository {
  const ApiThreadReplyPageRepository({required ThreadRepository repository})
    : _repository = repository;

  final ThreadRepository _repository;

  @override
  Future<DataReadResult<ThreadReplyPage, ThreadReplyPageReadCapabilities>>
  loadPage({required String tid, required int page}) async {
    final normalizedTid = tid.trim();
    if (normalizedTid.isEmpty || page < 1) {
      return const DataReadFailure(
        kind: DataReadFailureKind.business,
        diagnosticMessage: 'Reply page identity or page number is invalid.',
        code: 'invalid_reply_page_request',
      );
    }

    final result = await _repository.getThreadDetail(
      tid: normalizedTid,
      page: page,
    );
    return result.when(
      success: (data, _, metadata) {
        if (data.tid.trim() != normalizedTid || data.currentPage != page) {
          return const DataReadFailure(
            kind: DataReadFailureKind.parse,
            code: 'reply_page_identity_mismatch',
            diagnosticMessage: 'Reply page identity does not match request.',
          );
        }
        final seenPids = <String>{};
        final entries = <ThreadReplyEntry>[];
        for (final post in data.posts) {
          final pid = post.pid.trim();
          if (pid.isEmpty || !seenPids.add(pid)) {
            return const DataReadFailure(
              kind: DataReadFailureKind.parse,
              code: 'reply_page_post_identity_invalid',
              diagnosticMessage:
                  'Reply page contains an invalid post identity.',
            );
          }
          entries.add(
            ThreadReplyEntry(
              pid: pid,
              authorId: post.authorId.trim(),
              authorName: post.author.trim(),
              dateline: post.dateline.trim(),
              floorNumber: post.number,
              isFirst: post.isFirst,
              rawMessage: post.message,
            ),
          );
        }
        return DataReadSuccess(
          data: ThreadReplyPage(
            tid: normalizedTid,
            page: data.currentPage,
            perPage: data.perPage,
            replyCount: data.replies,
            posts: List<ThreadReplyEntry>.unmodifiable(entries),
            lastPage: data.lastPage,
            hasNext: data.nextPageUrl != null || data.hasMore,
          ),
          capabilities: _replyPageCapabilities,
          metadata: metadata,
        );
      },
      failure: (failure) => failure.retype(),
    );
  }
}

final _replyPageCapabilities = ThreadReplyPageReadCapabilities(
  DataCapabilitySet<ThreadReplyPageCapability>.supported(
    ThreadReplyPageCapability.values,
  ),
);

final threadReplyPageRepositoryProvider = Provider<ThreadReplyPageRepository>((
  ref,
) {
  return ApiThreadReplyPageRepository(
    repository: ref.watch(threadJsonRepositoryProvider),
  );
});
