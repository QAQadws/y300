abstract interface class NovelSyncRequestGovernor {
  Future<T> schedule<T>(Future<T> Function() request);
}
