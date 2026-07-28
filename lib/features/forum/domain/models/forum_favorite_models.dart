enum ForumFavoriteMutationCode { applied, alreadyApplied }

class ForumFavoriteMutationResult {
  const ForumFavoriteMutationResult({
    this.message = '',
    this.alreadyApplied = false,
    this.code = ForumFavoriteMutationCode.applied,
  });

  @Deprecated('Use code and presentation localization instead.')
  final String message;
  final bool alreadyApplied;
  final ForumFavoriteMutationCode code;
}
