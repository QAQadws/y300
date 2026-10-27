class ThreadFavoriteActionResult {
  const ThreadFavoriteActionResult({
    required this.parseQueued,
    required this.alreadyFavorited,
  });

  final bool parseQueued;
  final bool alreadyFavorited;
}
