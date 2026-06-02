class ThreadFavoriteRequest {
  const ThreadFavoriteRequest({
    required this.tid,
  });

  final String tid;
}

class ThreadFavoriteResult {
  const ThreadFavoriteResult({
    required this.message,
    this.alreadyFavorited = false,
  });

  final String message;
  final bool alreadyFavorited;
}

class ThreadFavoriteActionResult {
  const ThreadFavoriteActionResult({
    required this.message,
    required this.refreshedFavoriteModule,
    required this.alreadyFavorited,
  });

  final String message;
  final bool refreshedFavoriteModule;
  final bool alreadyFavorited;
}

/// 取消收藏请求。删除以帖子 tid 为键（`op=delete&type=thread&id=<tid>`），
/// 不依赖 favid。
class ThreadUnfavoriteRequest {
  const ThreadUnfavoriteRequest({
    required this.tid,
  });

  final String tid;
}

/// 取消收藏结果。
///
/// [alreadyRemoved] 表示远端已无该收藏（删除不存在的收藏视为幂等成功），
/// 让上层「取消整部作品」逐个 tid 删除时不会因历史残留而报错。
class ThreadUnfavoriteResult {
  const ThreadUnfavoriteResult({
    required this.message,
    this.alreadyRemoved = false,
  });

  final String message;
  final bool alreadyRemoved;
}
