import 'dart:async';

import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

typedef FriendFeedRead =
    DataReadResult<ForumFriendFeedPage, ForumFriendFeedReadCapabilities>;

final class FriendFeedFixture implements ForumFriendFeedRepository {
  FriendFeedFixture({this.autoComplete = false});

  final bool autoComplete;
  final requests = <FriendFeedRequest>[];
  List<ForumFriendFeedItem> items = [friendFeedItem('202')];
  int? totalPages = 3;
  bool hasNext = true;

  @override
  final capabilities = ForumFriendFeedSourceCapabilities(
    values: DataCapabilitySet.supported(ForumFriendFeedCapability.values),
  );

  @override
  Future<FriendFeedRead> load(
    ForumFriendFeedQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) {
    final request = FriendFeedRequest(query, cachePolicy);
    requests.add(request);
    if (autoComplete) {
      succeed(
        requests.length - 1,
        items: items,
        totalPages: totalPages,
        hasNext: hasNext,
      );
    }
    return request.result.future;
  }

  void succeed(
    int index, {
    List<ForumFriendFeedItem>? items,
    int? page,
    int? totalPages = 3,
    bool hasNext = true,
    String? currentUserId,
    ForumFriendFeedScope? scope,
    DataReadMetadata metadata = const DataReadMetadata.network(),
  }) {
    final request = requests[index];
    request.result.complete(
      DataReadSuccess(
        data: ForumFriendFeedPage(
          scope: scope ?? request.query.scope,
          currentUserId: currentUserId ?? request.query.accountUserId,
          items: items ?? [friendFeedItem('202')],
          page: page ?? request.query.page,
          totalPages: totalPages,
          hasNext: hasNext,
        ),
        capabilities: ForumFriendFeedReadCapabilities(
          values: capabilities.values,
        ),
        metadata: metadata,
      ),
    );
  }

  void fail(int index, DataReadFailureKind kind) {
    requests[index].result.complete(
      DataReadFailure(
        kind: kind,
        code: 'fixture_failure',
        diagnosticMessage: 'fixture_failure',
      ),
    );
  }
}

final class FriendFeedRequest {
  FriendFeedRequest(this.query, this.cachePolicy);

  final ForumFriendFeedQuery query;
  final CacheLoadPolicy cachePolicy;
  final result = Completer<FriendFeedRead>();
}

ForumFriendFeedItem friendFeedItem(
  String userId, {
  String? username,
  String? profileUrl,
  String? note,
  String? visitedAtText,
  bool? isOnline,
  bool canRemove = true,
}) => ForumFriendFeedItem(
  userId: userId,
  username: username ?? 'Member $userId',
  profileUrl:
      profileUrl ??
      (userId.isEmpty
          ? null
          : 'https://bbs.yamibo.com/home.php?mod=space&uid=$userId'),
  note: note,
  visitedAtText: visitedAtText,
  isOnline: isOnline,
  canRemove: canRemove,
);

final class FriendRemovalFixture implements ForumFriendRemovalCommand {
  final requests = <FriendRemovalRequest>[];

  @override
  Future<DataCommandResult<ForumFriendRemovalReceipt>> execute(
    ForumFriendRemovalSubmission submission,
  ) {
    final request = FriendRemovalRequest(submission);
    requests.add(request);
    return request.result.future;
  }

  void applied({int? index, String? actorUserId, String? userId}) {
    final request = requests[index ?? requests.length - 1];
    request.result.complete(
      DataCommandApplied(
        ForumFriendRemovalReceipt(
          actorUserId: actorUserId ?? request.submission.actorUserId,
          userId: userId ?? request.submission.userId,
        ),
      ),
    );
  }

  void outcomeUnknown({int? index}) {
    requests[index ?? requests.length - 1].result.complete(
      const DataCommandOutcomeUnknown(
        DataCommandFailure(
          kind: DataCommandFailureKind.network,
          retryPolicy: DataCommandRetryPolicy.never,
          code: 'fixture_unknown',
          diagnosticMessage: 'private server payload must not be shown',
        ),
      ),
    );
  }

  void rejected({int? index}) {
    requests[index ?? requests.length - 1].result.complete(
      const DataCommandRejected(
        DataCommandFailure(
          kind: DataCommandFailureKind.permissionDenied,
          retryPolicy: DataCommandRetryPolicy.never,
          code: 'fixture_rejected',
          diagnosticMessage: 'fixture_rejected',
        ),
      ),
    );
  }
}

final class FriendRemovalRequest {
  FriendRemovalRequest(this.submission);

  final ForumFriendRemovalSubmission submission;
  final result = Completer<DataCommandResult<ForumFriendRemovalReceipt>>();
}
