import 'dart:async';

import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

typedef CommentPreparationRead =
    DataReadResult<
      UserBlogCommentPreparation,
      DataCapabilitySet<UserBlogCommentAction>
    >;

const blogCommentFixtureTarget = UserBlogCommentTarget(
  actorUserId: '101',
  ownerUserId: '202',
  blogId: '11',
  action: UserBlogCommentAction.add,
);

UserBlogCommentTarget blogCommentTarget(UserBlogCommentAction action) =>
    UserBlogCommentTarget(
      actorUserId: '101',
      ownerUserId: '202',
      blogId: '11',
      action: action,
      commentId: action == UserBlogCommentAction.add ? null : '31',
    );

final class BlogCommentFixture implements UserBlogCommentService {
  BlogCommentFixture({this.autoPrepare = false, this.initialMessage = ''});

  final bool autoPrepare;
  String initialMessage;
  final preparations =
      <
        ({
          UserBlogCommentTarget target,
          ForumRequestCancellation? cancellation,
          Completer<CommentPreparationRead> result,
        })
      >[];
  final submissions =
      <
        ({
          UserBlogCommentSubmission input,
          Completer<DataCommandResult<UserBlogCommentReceipt>> result,
        })
      >[];

  @override
  Future<CommentPreparationRead> prepare(
    UserBlogCommentTarget target, {
    ForumRequestCancellation? cancellation,
  }) {
    final result = Completer<CommentPreparationRead>();
    preparations.add((
      target: target,
      cancellation: cancellation,
      result: result,
    ));
    if (autoPrepare) prepared();
    return result.future;
  }

  void prepared({
    int? index,
    UserBlogCommentTarget? target,
    bool supported = true,
  }) {
    final request = preparations[index ?? preparations.length - 1];
    request.result.complete(
      DataReadSuccess(
        data: UserBlogCommentPreparation(
          target: target ?? request.target,
          token: _CommentToken(),
          initialMessage: initialMessage,
        ),
        capabilities: DataCapabilitySet.supported(
          supported ? [request.target.action] : [],
        ),
        metadata: const DataReadMetadata.network(),
      ),
    );
  }

  @override
  Future<DataCommandResult<UserBlogCommentReceipt>> execute(
    UserBlogCommentSubmission submission,
  ) {
    final result = Completer<DataCommandResult<UserBlogCommentReceipt>>();
    submissions.add((input: submission, result: result));
    return result.future;
  }

  void applied({int? index, UserBlogCommentTarget? target, String? commentId}) {
    final request = submissions[index ?? submissions.length - 1];
    request.result.complete(
      DataCommandApplied(
        UserBlogCommentReceipt(
          target: target ?? request.input.preparation.target,
          commentId:
              commentId ?? request.input.preparation.target.commentId ?? '41',
        ),
      ),
    );
  }
}

final class _CommentToken implements UserBlogCommentPreparationToken {}

const blogCommentReadFailure =
    DataReadFailure<
      UserBlogCommentPreparation,
      DataCapabilitySet<UserBlogCommentAction>
    >(
      kind: DataReadFailureKind.network,
      diagnosticMessage: 'fixture_prepare_failed',
    );

const blogCommentWriteFailure = DataCommandFailure(
  kind: DataCommandFailureKind.network,
  retryPolicy: DataCommandRetryPolicy.explicitOnly,
  diagnosticMessage: 'fixture_write_failed',
);
