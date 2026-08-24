import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';

final class PackageNovelThreadGateway implements NovelThreadGateway {
  const PackageNovelThreadGateway(this._repository);

  final ThreadAuthorPostRepository _repository;

  @override
  Future<ThreadDetailData> loadAuthorPostsPage({
    required String tid,
    required String authorId,
    required int page,
    int postsPerPage = 200,
  }) async {
    final result = await _repository.load(
      ThreadAuthorPostQuery(
        tid: tid,
        authorId: authorId,
        page: page,
        pageSize: postsPerPage,
      ),
    );
    if (result case DataReadFailure<
      ThreadAuthorPostPage,
      ThreadAuthorPostReadCapabilities
    >(
      :final diagnosticMessage,
    )) {
      throw StateError(diagnosticMessage);
    }
    final data =
        (result
                as DataReadSuccess<
                  ThreadAuthorPostPage,
                  ThreadAuthorPostReadCapabilities
                >)
            .data;
    return ThreadDetailData(
      tid: data.tid,
      fid: '',
      subject: data.subject,
      author: data.posts.isEmpty ? '' : data.posts.first.author,
      replies: data.totalReplyHint,
      views: 0,
      currentPage: data.currentPage,
      perPage: data.pageSize,
      posts: data.posts,
      nextPageUrl: data.hasNext ? 'author-page:${data.currentPage + 1}' : null,
    );
  }
}

final novelThreadGatewayProvider = Provider<NovelThreadGateway>((ref) {
  return PackageNovelThreadGateway(
    ref.watch(yamiboForumClientProvider).threadAuthorPosts!,
  );
});
