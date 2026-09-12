import 'dart:async';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

typedef BlogActionRead =
    DataReadResult<
      UserBlogActionPreparation,
      DataCapabilitySet<UserBlogAction>
    >;

UserBlogTarget blogActionTarget(UserBlogAction action) => UserBlogTarget(
  actorUserId: '101',
  ownerUserId: '101',
  blogId: '11',
  action: action,
);

final class BlogOperationFixture implements UserBlogOperations {
  BlogOperationFixture({this.autoPrepare = false});
  final bool autoPrepare;
  final preparations =
      <
        ({
          UserBlogTarget target,
          ForumRequestCancellation? cancellation,
          Completer<BlogActionRead> result,
        })
      >[];
  final submissions =
      <
        ({
          UserBlogActionPreparation preparation,
          String actor,
          ForumRequestCancellation? cancellation,
          Completer<DataCommandResult<UserBlogReceipt>> result,
        })
      >[];

  @override
  Future<BlogActionRead> prepareAction(
    UserBlogTarget target, {
    ForumRequestCancellation? cancellation,
  }) {
    final result = Completer<BlogActionRead>();
    preparations.add((
      target: target,
      cancellation: cancellation,
      result: result,
    ));
    if (autoPrepare) prepared();
    return result.future;
  }

  void prepared({UserBlogTarget? target, bool supported = true, int? index}) {
    final request = preparations[index ?? preparations.length - 1];
    request.result.complete(
      DataReadSuccess(
        data: UserBlogActionPreparation(
          target: target ?? request.target,
          token: _Token(),
        ),
        capabilities: DataCapabilitySet.supported(
          supported ? [request.target.action] : [],
        ),
        metadata: const DataReadMetadata.network(),
      ),
    );
  }

  @override
  Future<DataCommandResult<UserBlogReceipt>> executeAction(
    UserBlogActionPreparation preparation, {
    required String actorUserId,
    ForumRequestCancellation? cancellation,
  }) {
    final result = Completer<DataCommandResult<UserBlogReceipt>>();
    submissions.add((
      preparation: preparation,
      actor: actorUserId,
      cancellation: cancellation,
      result: result,
    ));
    return result.future;
  }

  void applied({UserBlogTarget? target, String? blogId}) {
    final request = submissions.last;
    request.result.complete(
      DataCommandApplied(
        UserBlogReceipt(
          target: target ?? request.preparation.target,
          blogId: blogId ?? request.preparation.target.blogId!,
        ),
      ),
    );
  }

  @override
  Future<
    DataReadResult<UserBlogEditorPreparation, DataCapabilitySet<UserBlogAction>>
  >
  prepareEditor(
    UserBlogTarget target, {
    ForumRequestCancellation? cancellation,
  }) => throw StateError('Unexpected editor request');

  @override
  Future<DataCommandResult<UserBlogReceipt>> save(
    UserBlogEditorSubmission submission,
  ) => throw StateError('Unexpected editor submission');
}

final class _Token implements UserBlogOperationToken {}

const blogActionReadFailure =
    DataReadFailure<
      UserBlogActionPreparation,
      DataCapabilitySet<UserBlogAction>
    >(
      kind: DataReadFailureKind.network,
      diagnosticMessage: 'fixture prepare failed',
    );
const blogActionWriteFailure = DataCommandFailure(
  kind: DataCommandFailureKind.network,
  retryPolicy: DataCommandRetryPolicy.explicitOnly,
  diagnosticMessage: 'fixture write failed',
);
