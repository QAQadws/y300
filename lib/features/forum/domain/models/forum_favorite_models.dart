class ForumFavoriteMutationResult {
  const ForumFavoriteMutationResult({
    required this.message,
    this.alreadyApplied = false,
  });

  final String message;
  final bool alreadyApplied;
}
