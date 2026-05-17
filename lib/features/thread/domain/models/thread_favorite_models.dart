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
