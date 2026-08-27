class ThreadFavoriteActionResult {
  const ThreadFavoriteActionResult({
    required this.refreshedFavoriteModule,
    required this.alreadyFavorited,
  });

  final bool refreshedFavoriteModule;
  final bool alreadyFavorited;
}
