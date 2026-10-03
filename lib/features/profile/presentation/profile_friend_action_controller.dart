import 'package:flutter/foundation.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';

typedef PrepareProfileFriendAction =
    Future<DataReadResult<ForumFriendPreparation, ForumFriendReadCapabilities>>
    Function(ForumFriendQuery query);
typedef SubmitProfileFriendAction =
    Future<DataCommandResult<ForumFriendReceipt>> Function(
      ForumFriendSubmission submission,
    );

enum ProfileFriendActionPhase {
  idle,
  preparing,
  ready,
  submitting,
  failed,
  unknown,
  applied,
  expired,
}

@immutable
final class ProfileFriendActionState {
  const ProfileFriendActionState({
    this.phase = ProfileFriendActionPhase.idle,
    this.preparation,
    this.failure,
  });

  final ProfileFriendActionPhase phase;
  final ForumFriendPreparation? preparation;
  final Object? failure;

  bool get busy =>
      phase == ProfileFriendActionPhase.preparing ||
      phase == ProfileFriendActionPhase.submitting;
}

/// A sheet owns one freshly read, single-use server form and one account epoch.
final class ProfileFriendActionController
    extends ValueNotifier<ProfileFriendActionState> {
  ProfileFriendActionController({
    required this.owner,
    required this.targetUserId,
    required this.actionLink,
    required VerifiedProfileOwner? Function() currentOwner,
    required PrepareProfileFriendAction prepare,
    required SubmitProfileFriendAction submit,
  }) : _currentOwner = currentOwner,
       _prepare = prepare,
       _submit = submit,
       super(const ProfileFriendActionState());

  final VerifiedProfileOwner owner;
  final String targetUserId;
  final ForumUserProfileActionLink actionLink;
  final VerifiedProfileOwner? Function() _currentOwner;
  final PrepareProfileFriendAction _prepare;
  final SubmitProfileFriendAction _submit;
  ForumRequestCancellation? _cancellation;
  ForumFriendPreparation? _ticket;
  int _generation = 0;
  bool _disposed = false;

  Future<void> prepare() async {
    if (_disposed ||
        !{
          ProfileFriendActionPhase.idle,
          ProfileFriendActionPhase.failed,
        }.contains(value.phase)) {
      return;
    }
    if (_currentOwner() != owner || targetUserId == owner.uid) {
      expire();
      return;
    }
    final generation = ++_generation;
    _cancellation?.cancel();
    final cancellation = _cancellation = ForumRequestCancellation();
    _ticket = null;
    value = const ProfileFriendActionState(
      phase: ProfileFriendActionPhase.preparing,
    );
    try {
      final result = await _prepare(
        ForumFriendQuery(
          actorUserId: owner.uid,
          targetUserId: targetUserId,
          actionLink: actionLink,
          cancellation: cancellation,
        ),
      );
      if (!_accept(generation, cancellation)) return;
      if (result
          case DataReadSuccess(
            :final data,
            :final capabilities,
            :final metadata,
          )
          when data.actorUserId == owner.uid &&
              data.targetUserId == targetUserId &&
              metadata.origin == DataReadOrigin.network &&
              metadata.freshness == DataReadFreshness.current &&
              capabilities.action == data.action &&
              (!data.acceptsNote || data.noteMaxLength > 0) &&
              data.groups.map((group) => group.id).toSet().length ==
                  data.groups.length &&
              _actionMatches(data.action)) {
        _ticket = data;
        value = ProfileFriendActionState(
          phase: ProfileFriendActionPhase.ready,
          preparation: data,
        );
      } else {
        value = ProfileFriendActionState(
          phase: ProfileFriendActionPhase.failed,
          failure: result.failureOrNull ?? _invalidPreparation,
        );
      }
    } on Object {
      if (_accept(generation, cancellation)) {
        value = const ProfileFriendActionState(
          phase: ProfileFriendActionPhase.failed,
          failure: _readFailed,
        );
      }
    }
  }

  bool _actionMatches(ForumFriendAction action) =>
      actionLink.kind == ForumUserProfileActionKind.removeFriend
      ? action == ForumFriendAction.remove
      : actionLink.kind == ForumUserProfileActionKind.addFriend &&
            (action == ForumFriendAction.request ||
                action == ForumFriendAction.approve);

  Future<bool> submit({String note = '', String? groupId}) async {
    final prepared = _ticket;
    if (_disposed ||
        value.phase != ProfileFriendActionPhase.ready ||
        prepared == null) {
      return false;
    }
    if (_currentOwner() != owner) {
      expire();
      return false;
    }
    if ((prepared.acceptsNote && note.runes.length > prepared.noteMaxLength) ||
        (prepared.groups.isNotEmpty &&
            !prepared.groups.any((group) => group.id == groupId))) {
      return false;
    }
    // Consuming the ticket before awaiting also suppresses rapid double taps.
    _ticket = null;
    final generation = ++_generation;
    final cancellation = _cancellation = ForumRequestCancellation();
    value = ProfileFriendActionState(
      phase: ProfileFriendActionPhase.submitting,
      preparation: prepared,
    );
    try {
      final result = await _submit(
        ForumFriendSubmission(
          preparation: prepared,
          actorUserId: owner.uid,
          note: prepared.acceptsNote ? note : '',
          groupId: groupId,
          cancellation: cancellation,
        ),
      );
      if (!_accept(generation, cancellation)) return false;
      if (result case DataCommandApplied(:final receipt)) {
        if (receipt.actorUserId == owner.uid &&
            receipt.targetUserId == targetUserId &&
            receipt.action == prepared.action) {
          value = ProfileFriendActionState(
            phase: ProfileFriendActionPhase.applied,
            preparation: prepared,
          );
          return true;
        }
        value = ProfileFriendActionState(
          phase: ProfileFriendActionPhase.unknown,
          preparation: prepared,
          failure: _unknownResult,
        );
      } else {
        value = ProfileFriendActionState(
          phase: result is DataCommandOutcomeUnknown
              ? ProfileFriendActionPhase.unknown
              : ProfileFriendActionPhase.failed,
          preparation: prepared,
          failure: result.failureOrNull,
        );
      }
    } on Object {
      if (_accept(generation, cancellation)) {
        value = ProfileFriendActionState(
          phase: ProfileFriendActionPhase.unknown,
          preparation: prepared,
          failure: _unknownResult,
        );
      }
    }
    return false;
  }

  void expire() {
    if (_disposed || value.phase == ProfileFriendActionPhase.expired) return;
    ++_generation;
    _cancellation?.cancel();
    _ticket = null;
    value = const ProfileFriendActionState(
      phase: ProfileFriendActionPhase.expired,
    );
  }

  bool _accept(int generation, ForumRequestCancellation cancellation) {
    if (_disposed || generation != _generation || cancellation.isCancelled) {
      return false;
    }
    if (_currentOwner() != owner) {
      expire();
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _cancellation?.cancel();
    _ticket = null;
    super.dispose();
  }
}

const _invalidPreparation = DataReadFailure<Object?, Object?>(
  kind: DataReadFailureKind.parse,
  code: 'profile_friend_preparation_mismatch',
  diagnosticMessage: 'profile_friend_preparation_mismatch',
);
const _readFailed = DataReadFailure<Object?, Object?>(
  kind: DataReadFailureKind.network,
  code: 'profile_friend_preparation_failed',
  diagnosticMessage: 'profile_friend_preparation_failed',
);
const _unknownResult = DataCommandFailure(
  kind: DataCommandFailureKind.unknown,
  retryPolicy: DataCommandRetryPolicy.explicitOnly,
  code: 'profile_friend_result_unconfirmed',
  diagnosticMessage: 'profile_friend_result_unconfirmed',
);
