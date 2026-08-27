/// Source-neutral commands for changing forum and thread favorite state.
library;

import '../network/forum_request.dart';
import 'data_command_contract.dart';
import 'data_read_contract.dart';

/// Desired final state of a forum or thread favorite.
enum FavoriteTargetState {
  /// The target must be present in the authenticated user's favorites.
  favorited,

  /// The target must be absent from the authenticated user's favorites.
  unfavorited,
}

/// Whether a confirmed command changed server state or was already satisfied.
enum FavoriteMutationDisposition {
  /// The server reported that the mutation changed state.
  changed,

  /// The requested target state was already in effect.
  alreadyApplied,
}

/// Business capabilities exposed by a favorite command source.
enum FavoriteMutationCapability {
  /// The source can make a target favorited.
  favorite,

  /// The source can make a target unfavorited.
  unfavorite,

  /// The source confirms the final state through a separate directory read.
  readBackConfirmation,
}

/// Fail-closed capability declaration for favorite mutation commands.
final class FavoriteMutationCapabilities {
  /// Creates capabilities from explicit support values.
  const FavoriteMutationCapabilities({required this.values});

  /// Support values for every known capability.
  final DataCapabilitySet<FavoriteMutationCapability> values;

  /// Whether [capability] is explicitly supported.
  bool supports(FavoriteMutationCapability capability) =>
      values.supports(capability);
}

/// Requests a target state for one forum favorite.
final class SetForumFavoriteRequest {
  /// Creates a forum favorite state request.
  const SetForumFavoriteRequest({
    required this.fid,
    required this.targetState,
    this.knownRemoteFavoriteId,
    this.cancellation,
  });

  /// Stable forum identity.
  final String fid;

  /// Desired final favorite state.
  final FavoriteTargetState targetState;

  /// Optional remote favorite identity supplied as an untrusted hint.
  final String? knownRemoteFavoriteId;

  /// Optional caller-owned cancellation signal.
  final ForumRequestCancellation? cancellation;
}

/// Proof returned after a forum favorite state was read back successfully.
final class ForumFavoriteReceipt {
  /// Creates a confirmed forum favorite receipt.
  const ForumFavoriteReceipt({
    required this.fid,
    required this.targetState,
    required this.disposition,
    this.remoteFavoriteId,
  });

  /// Confirmed forum identity.
  final String fid;

  /// Confirmed final state.
  final FavoriteTargetState targetState;

  /// Whether the command changed state or was already satisfied.
  final FavoriteMutationDisposition disposition;

  /// Confirmed remote favorite identity when the final state is favorited.
  final String? remoteFavoriteId;
}

/// Requests a target state for one thread favorite.
final class SetThreadFavoriteRequest {
  /// Creates a thread favorite state request.
  const SetThreadFavoriteRequest({
    required this.tid,
    required this.targetState,
    this.cancellation,
  });

  /// Stable thread identity.
  final String tid;

  /// Desired final favorite state.
  final FavoriteTargetState targetState;

  /// Optional caller-owned cancellation signal.
  final ForumRequestCancellation? cancellation;
}

/// Proof returned after a thread favorite state was read back successfully.
final class ThreadFavoriteReceipt {
  /// Creates a confirmed thread favorite receipt.
  const ThreadFavoriteReceipt({
    required this.tid,
    required this.targetState,
    required this.disposition,
    this.remoteFavoriteId,
  });

  /// Confirmed thread identity.
  final String tid;

  /// Confirmed final state.
  final FavoriteTargetState targetState;

  /// Whether the command changed state or was already satisfied.
  final FavoriteMutationDisposition disposition;

  /// Confirmed remote favorite identity when available.
  final String? remoteFavoriteId;
}

/// Command that sets the authenticated user's favorite state for a forum.
abstract interface class FavoriteForumCommand {
  /// Capabilities proved by this source.
  FavoriteMutationCapabilities get capabilities;

  /// Executes [request] and returns only after read-back confirmation.
  Future<DataCommandResult<ForumFavoriteReceipt>> execute(
    SetForumFavoriteRequest request,
  );
}

/// Command that sets the authenticated user's favorite state for a thread.
abstract interface class FavoriteThreadCommand {
  /// Capabilities proved by this source.
  FavoriteMutationCapabilities get capabilities;

  /// Executes [request] and returns only after read-back confirmation.
  Future<DataCommandResult<ThreadFavoriteReceipt>> execute(
    SetThreadFavoriteRequest request,
  );
}
