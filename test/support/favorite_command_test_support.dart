import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

typedef ForumFavoriteCommandHandler =
    Future<DataCommandResult<ForumFavoriteReceipt>> Function(
      SetForumFavoriteRequest request,
    );
typedef ThreadFavoriteCommandHandler =
    Future<DataCommandResult<ThreadFavoriteReceipt>> Function(
      SetThreadFavoriteRequest request,
    );

final FavoriteMutationCapabilities allFavoriteMutationCapabilities =
    FavoriteMutationCapabilities(
      values: DataCapabilitySet.supported(FavoriteMutationCapability.values),
    );

DataCommandApplied<ForumFavoriteReceipt> appliedForumFavorite({
  required String fid,
  required FavoriteTargetState targetState,
  FavoriteMutationDisposition disposition = FavoriteMutationDisposition.changed,
  String? remoteFavoriteId,
}) => DataCommandApplied<ForumFavoriteReceipt>(
  ForumFavoriteReceipt(
    fid: fid,
    targetState: targetState,
    disposition: disposition,
    remoteFavoriteId: remoteFavoriteId,
  ),
);

DataCommandApplied<ThreadFavoriteReceipt> appliedThreadFavorite({
  required String tid,
  required FavoriteTargetState targetState,
  FavoriteMutationDisposition disposition = FavoriteMutationDisposition.changed,
  String? remoteFavoriteId,
}) => DataCommandApplied<ThreadFavoriteReceipt>(
  ThreadFavoriteReceipt(
    tid: tid,
    targetState: targetState,
    disposition: disposition,
    remoteFavoriteId: remoteFavoriteId,
  ),
);

DataCommandFailure fixtureFavoriteFailure({
  DataCommandFailureKind kind = DataCommandFailureKind.network,
  String code = 'fixture_favorite_failure',
  DataCommandRetryPolicy retryPolicy = DataCommandRetryPolicy.explicitOnly,
}) => DataCommandFailure(
  kind: kind,
  retryPolicy: retryPolicy,
  code: code,
  diagnosticMessage: code,
);

final class FakeFavoriteForumCommand implements FavoriteForumCommand {
  FakeFavoriteForumCommand({ForumFavoriteCommandHandler? handler})
    : _handler =
          handler ??
          ((request) async => appliedForumFavorite(
            fid: request.fid,
            targetState: request.targetState,
            remoteFavoriteId: request.knownRemoteFavoriteId,
          ));

  final ForumFavoriteCommandHandler _handler;
  final List<SetForumFavoriteRequest> requests = <SetForumFavoriteRequest>[];

  @override
  FavoriteMutationCapabilities get capabilities =>
      allFavoriteMutationCapabilities;

  @override
  Future<DataCommandResult<ForumFavoriteReceipt>> execute(
    SetForumFavoriteRequest request,
  ) {
    requests.add(request);
    return _handler(request);
  }
}

final class FakeFavoriteThreadCommand implements FavoriteThreadCommand {
  FakeFavoriteThreadCommand({ThreadFavoriteCommandHandler? handler})
    : _handler =
          handler ??
          ((request) async => appliedThreadFavorite(
            tid: request.tid,
            targetState: request.targetState,
          ));

  final ThreadFavoriteCommandHandler _handler;
  final List<SetThreadFavoriteRequest> requests = <SetThreadFavoriteRequest>[];

  @override
  FavoriteMutationCapabilities get capabilities =>
      allFavoriteMutationCapabilities;

  @override
  Future<DataCommandResult<ThreadFavoriteReceipt>> execute(
    SetThreadFavoriteRequest request,
  ) {
    requests.add(request);
    return _handler(request);
  }
}
