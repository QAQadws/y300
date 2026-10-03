import 'dart:async';

import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

typedef ProfileFriendRead =
    DataReadResult<ForumFriendPreparation, ForumFriendReadCapabilities>;

ForumUserProfileActionLink profileFriendLink({
  bool remove = false,
}) => ForumUserProfileActionLink(
  kind: remove
      ? ForumUserProfileActionKind.removeFriend
      : ForumUserProfileActionKind.addFriend,
  uri: Uri.parse(
    'https://bbs.yamibo.com/home.php?mod=spacecp&ac=friend&op=${remove ? 'ignore' : 'add'}&uid=202&handlekey=${remove ? 'ignorefriendhk' : 'addfriendhk'}_202',
  ),
);

final class ProfileFriendOperationFixture implements ForumFriendOperations {
  final preparations =
      <({ForumFriendQuery query, Completer<ProfileFriendRead> result})>[];
  final submissions =
      <
        ({
          ForumFriendSubmission submission,
          Completer<DataCommandResult<ForumFriendReceipt>> result,
        })
      >[];

  @override
  Future<ProfileFriendRead> prepare(ForumFriendQuery query) {
    final result = Completer<ProfileFriendRead>();
    preparations.add((query: query, result: result));
    return result.future;
  }

  @override
  Future<DataCommandResult<ForumFriendReceipt>> submit(
    ForumFriendSubmission submission,
  ) {
    final result = Completer<DataCommandResult<ForumFriendReceipt>>();
    submissions.add((submission: submission, result: result));
    return result.future;
  }

  void prepared({
    ForumFriendAction? action,
    ForumFriendAction? capabilityAction,
    String? actor,
    String? target,
    List<ForumFriendGroup>? groups,
    int noteMaxLength = 30,
    DataReadMetadata metadata = const DataReadMetadata.network(),
  }) {
    final request = preparations.last;
    final effectiveAction =
        action ??
        (request.query.actionLink.kind ==
                ForumUserProfileActionKind.removeFriend
            ? ForumFriendAction.remove
            : ForumFriendAction.request);
    request.result.complete(
      DataReadSuccess(
        data: ForumFriendPreparation(
          actorUserId: actor ?? request.query.actorUserId,
          targetUserId: target ?? request.query.targetUserId,
          action: effectiveAction,
          token: _FriendToken(),
          groups:
              groups ??
              (effectiveAction == ForumFriendAction.remove
                  ? const []
                  : const [
                      ForumFriendGroup(id: '0', name: '未分组'),
                      ForumFriendGroup(id: '2', name: '同好'),
                    ]),
          selectedGroupId: '2',
          noteMaxLength: noteMaxLength,
        ),
        capabilities: ForumFriendReadCapabilities(
          action: capabilityAction ?? effectiveAction,
        ),
        metadata: metadata,
      ),
    );
  }

  void applied({String? actor, String? target, ForumFriendAction? action}) {
    final submission = submissions.last.submission;
    submissions.last.result.complete(
      DataCommandApplied(
        ForumFriendReceipt(
          actorUserId: actor ?? submission.actorUserId,
          targetUserId: target ?? submission.preparation.targetUserId,
          action: action ?? submission.preparation.action,
        ),
      ),
    );
  }
}

final class _FriendToken implements ForumFriendOperationToken {}

const profileFriendWriteFailure = DataCommandFailure(
  kind: DataCommandFailureKind.unknown,
  retryPolicy: DataCommandRetryPolicy.explicitOnly,
  code: 'fixture_failed',
  diagnosticMessage: '<html>untrusted server response</html>',
);
