/// Ensures a route-local content presentation callback is committed once per
/// target. The guard is intentionally independent from any analytics or
/// history implementation.
class RouteContentPresentationGuard {
  String? _committedTargetId;

  bool tryCommit(String targetId) {
    final normalized = targetId.trim();
    if (normalized.isEmpty || normalized == _committedTargetId) {
      return false;
    }
    _committedTargetId = normalized;
    return true;
  }
}
