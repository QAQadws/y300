import 'dart:async';

import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

typedef ThreadDirectoryRead =
    DataReadResult<
      UserThreadDirectoryData,
      UserThreadDirectoryReadCapabilities
    >;

final class ThreadDirectoryFixture implements UserThreadDirectoryRepository {
  ThreadDirectoryFixture({this.autoComplete = false});

  final bool autoComplete;
  final requests = <ThreadDirectoryRequest>[];

  @override
  final capabilities = UserThreadDirectorySourceCapabilities(
    values: DataCapabilitySet.from(
      supported: UserThreadDirectoryCapability.values,
    ),
  );

  @override
  Future<ThreadDirectoryRead> load(
    UserThreadDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    ForumRequestCancellation? cancellation,
  }) {
    final request = ThreadDirectoryRequest(query, cachePolicy, cancellation);
    requests.add(request);
    if (autoComplete) succeed(requests.length - 1);
    return request.completion.future;
  }

  void succeed(
    int index, {
    List<UserThreadSummary>? items,
    bool hasMore = false,
  }) {
    final request = requests[index];
    request.completion.complete(
      DataReadSuccess(
        data: UserThreadDirectoryData(
          items: items ?? threadItems(request.query.type),
          pagination: UserThreadDirectoryPagination(
            currentPage: request.query.page,
            hasNext: hasMore,
            hasPrevious: request.query.page > 1,
          ),
        ),
        capabilities: UserThreadDirectoryReadCapabilities(
          values: capabilities.values,
        ),
        metadata: const DataReadMetadata.network(),
      ),
    );
  }

  void fail(int index, DataReadFailureKind kind) =>
      requests[index].completion.complete(
        DataReadFailure(
          kind: kind,
          code: 'fixture_failure',
          diagnosticMessage: '<html>raw server diagnostic</html>',
        ),
      );
}

final class ThreadDirectoryRequest {
  ThreadDirectoryRequest(this.query, this.policy, this.cancellation);

  final UserThreadDirectoryQuery query;
  final CacheLoadPolicy policy;
  final ForumRequestCancellation? cancellation;
  final completion = Completer<ThreadDirectoryRead>();
}

List<UserThreadSummary> threadItems(UserThreadDirectoryType type) => [
  threadSummary(
    '100',
    replies: type == UserThreadDirectoryType.replies ? ['501', '502'] : [],
  ),
];

UserThreadSummary threadSummary(
  String id, {
  List<String> replies = const [],
}) => UserThreadSummary(
  threadId: id,
  title: 'Thread $id: a source title with enough words to wrap on phones',
  uri: Uri.parse('https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$id'),
  authorName: 'Source author',
  forumName: 'Source forum',
  publishedAtText: '2026-10-02',
  excerpt: 'Source topic excerpt',
  views: 123,
  replies: 8,
  replyPreviews: [
    for (final pid in replies)
      UserThreadReplyPreview(
        postId: pid,
        excerpt: 'Reply $pid: source preview for this individual post',
        uri: Uri.parse(
          'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&ptid=$id&pid=$pid',
        ),
      ),
  ],
);
