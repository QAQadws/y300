import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/thread/data/thread_favorite_repository.dart';
import 'package:y300/features/thread/domain/models/thread_favorite_models.dart';

typedef ThreadFavoriteModuleRefresh = Future<void> Function({
  required String tid,
});
typedef ThreadFavoriteModuleRefreshNotifier = void Function({
  required String reason,
  required String tid,
});

abstract class ThreadFavoriteActionService {
  Future<ApiResult<ThreadFavoriteActionResult>> favoriteThread({
    required String tid,
  });
}

class DefaultThreadFavoriteActionService implements ThreadFavoriteActionService {
  DefaultThreadFavoriteActionService({
    required ThreadFavoriteRepository repository,
    required ThreadFavoriteModuleRefresh refreshFavoriteModule,
    required ThreadFavoriteModuleRefreshNotifier notifyFavoriteModule,
  })  : _repository = repository,
        _refreshFavoriteModule = refreshFavoriteModule,
        _notifyFavoriteModule = notifyFavoriteModule;

  final ThreadFavoriteRepository _repository;
  final ThreadFavoriteModuleRefresh _refreshFavoriteModule;
  final ThreadFavoriteModuleRefreshNotifier _notifyFavoriteModule;

  @override
  Future<ApiResult<ThreadFavoriteActionResult>> favoriteThread({
    required String tid,
  }) async {
    final result = await _repository.favoriteThread(
      request: ThreadFavoriteRequest(tid: tid),
    );
    if (result case ApiFailure<ThreadFavoriteResult>(:final error)) {
      return ApiFailure<ThreadFavoriteActionResult>(error);
    }

    final favoriteResult = (result as ApiSuccess<ThreadFavoriteResult>).data;
    final favoriteMessage = favoriteResult.message.trim().isEmpty
        ? '收藏成功'
        : favoriteResult.message.trim();
    var refreshed = false;
    Object? refreshError;

    try {
      await _refreshFavoriteModule(tid: tid);
      refreshed = true;
    } catch (error) {
      refreshError = error;
    }

    // The favorite shelf listens to this signal and reloads its local snapshot.
    // We still emit it when sync fails so the page can retry from its adapter.
    _notifyFavoriteModule(
      tid: tid,
      reason: refreshed ? 'thread_favorite_added' : 'thread_favorite_added_sync_failed',
    );

    return ApiSuccess<ThreadFavoriteActionResult>(
      ThreadFavoriteActionResult(
        message: refreshed
            ? favoriteMessage
            : '$favoriteMessage；收藏列表刷新失败：$refreshError',
        refreshedFavoriteModule: refreshed,
        alreadyFavorited: favoriteResult.alreadyFavorited,
      ),
    );
  }
}
