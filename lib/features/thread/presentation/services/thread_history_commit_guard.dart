class ThreadHistoryCommitGuard {
  String? _committedTid;

  bool tryCommit(String tid) {
    final normalized = tid.trim();
    if (normalized.isEmpty || normalized == _committedTid) {
      return false;
    }
    _committedTid = normalized;
    return true;
  }
}
