import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/thread/domain/models/thread_favorite_models.dart';

abstract class ThreadFavoriteRepository {
  Future<ApiResult<ThreadFavoriteResult>> favoriteThread({
    required ThreadFavoriteRequest request,
  });

  /// 取消收藏（按帖子 tid 删除）。删除不存在的收藏应作为幂等成功返回，
  /// 便于上层逐个 tid 取消整部作品时容忍历史残留。
  Future<ApiResult<ThreadUnfavoriteResult>> unfavoriteThread({
    required ThreadUnfavoriteRequest request,
  });
}
