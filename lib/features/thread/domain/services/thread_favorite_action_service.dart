import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/domain/models/thread_favorite_models.dart';

typedef ThreadFavoriteParseEnqueue = Future<void> Function({
  required ThreadFavoriteReceipt receipt,
  String? title,
});
typedef ThreadFavoriteModuleRefreshNotifier = void Function({
  required String reason,
  required String tid,
});

abstract class ThreadFavoriteActionService {
  Future<DataCommandResult<ThreadFavoriteActionResult>> favoriteThread({
    required String tid,
    String? title,
  });
}

class DefaultThreadFavoriteActionService
    implements ThreadFavoriteActionService {
  DefaultThreadFavoriteActionService({
    required FavoriteThreadCommand command,
    required ThreadFavoriteParseEnqueue enqueueFavoriteParse,
    required ThreadFavoriteModuleRefreshNotifier notifyFavoriteModule,
  }) : _command = command,
       _enqueueFavoriteParse = enqueueFavoriteParse,
       _notifyFavoriteModule = notifyFavoriteModule;

  final FavoriteThreadCommand _command;
  final ThreadFavoriteParseEnqueue _enqueueFavoriteParse;
  final ThreadFavoriteModuleRefreshNotifier _notifyFavoriteModule;

  @override
  Future<DataCommandResult<ThreadFavoriteActionResult>> favoriteThread({
    required String tid,
    String? title,
  }) async {
    final result = await _command.execute(
      SetThreadFavoriteRequest(
        tid: tid,
        targetState: FavoriteTargetState.favorited,
      ),
    );
    if (result is! DataCommandApplied<ThreadFavoriteReceipt>) {
      return _retypeFailure(result);
    }

    final favoriteReceipt = result.receipt;
    var parseQueued = false;

    try {
      await _enqueueFavoriteParse(receipt: favoriteReceipt, title: title);
      parseQueued = true;
    } catch (_) {
      // The remote command is already confirmed. Local ingest remains a
      // separate App workflow and is reported through structured state.
    }

    // The favorite shelf listens to this signal and reloads its local snapshot.
    // Admission failures keep remote success and allow a later manual retry.
    _notifyFavoriteModule(
      tid: tid,
      reason: parseQueued
          ? 'thread_favorite_added'
          : 'thread_favorite_added_sync_failed',
    );

    return DataCommandApplied<ThreadFavoriteActionResult>(
      ThreadFavoriteActionResult(
        parseQueued: parseQueued,
        alreadyFavorited:
            favoriteReceipt.disposition ==
            FavoriteMutationDisposition.alreadyApplied,
      ),
    );
  }
}

DataCommandResult<ThreadFavoriteActionResult> _retypeFailure(
  DataCommandResult<ThreadFavoriteReceipt> result,
) => switch (result) {
  DataCommandRejected<ThreadFavoriteReceipt>(:final failure) =>
    DataCommandRejected<ThreadFavoriteActionResult>(failure),
  DataCommandNotSent<ThreadFavoriteReceipt>(:final failure) =>
    DataCommandNotSent<ThreadFavoriteActionResult>(failure),
  DataCommandOutcomeUnknown<ThreadFavoriteReceipt>(:final failure) =>
    DataCommandOutcomeUnknown<ThreadFavoriteActionResult>(failure),
  DataCommandUnsupported<ThreadFavoriteReceipt>(:final failure) =>
    DataCommandUnsupported<ThreadFavoriteActionResult>(failure),
  DataCommandApplied<ThreadFavoriteReceipt>() => throw StateError(
    'Applied favorite results must be handled before failure retyping.',
  ),
};
