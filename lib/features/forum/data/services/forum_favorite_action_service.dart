import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/favorites/data/providers/favorite_directory_providers.dart';

/// Applies the server-declared forum favorite action without duplicating the
/// Discuz favorite endpoints in presentation code.
class ForumFavoriteActionService {
  const ForumFavoriteActionService({required FavoriteForumCommand command})
    : _command = command;

  final FavoriteForumCommand _command;

  Future<DataCommandResult<ForumFavoriteReceipt>> apply({
    required String fid,
    required ForumDisplayFavoriteAction action,
  }) async {
    final normalizedFid = fid.trim();
    if (normalizedFid.isEmpty || action == ForumDisplayFavoriteAction.unknown) {
      return const DataCommandNotSent<ForumFavoriteReceipt>(
        DataCommandFailure(
          kind: DataCommandFailureKind.validation,
          retryPolicy: DataCommandRetryPolicy.afterInputChange,
          code: 'favorite_forum_target_invalid',
          diagnosticMessage: 'favorite_forum_target_invalid',
        ),
      );
    }

    return _command.execute(
      SetForumFavoriteRequest(
        fid: normalizedFid,
        targetState: action == ForumDisplayFavoriteAction.favorite
            ? FavoriteTargetState.favorited
            : FavoriteTargetState.unfavorited,
      ),
    );
  }
}

final forumFavoriteActionServiceProvider = Provider<ForumFavoriteActionService>(
  (ref) {
    return ForumFavoriteActionService(
      command: ref.watch(favoriteForumCommandProvider),
    );
  },
);
