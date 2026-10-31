/// Commands implemented by the mounted paged viewport. Layout, visible proof,
/// chapter policy and persistence stay with their existing owners.
abstract interface class NovelReaderPagedNavigationTarget {
  bool turnPrevious();
  bool turnNext();
  bool confirmChapterEndNavigation();
  void cancelChapterTurn();
}

/// Reader chrome bridge shared by native and comparison viewports.
final class NovelReaderPagedNavigationController {
  ({NovelReaderPagedNavigationTarget target, Object token})? _binding;
  bool _disposed = false;

  bool turnPrevious() => _binding?.target.turnPrevious() ?? false;
  bool turnNext() => _binding?.target.turnNext() ?? false;

  /// Call only after the owner accepts the forward chapter turn, before it
  /// retires that chapter. The target still verifies actual visible end proof.
  bool confirmChapterEndNavigation() =>
      _binding?.target.confirmChapterEndNavigation() ?? false;

  void cancelChapterTurn() => _binding?.target.cancelChapterTurn();

  NovelReaderPagedNavigationBinding bind(
    NovelReaderPagedNavigationTarget target,
  ) {
    if (_disposed) return NovelReaderPagedNavigationBinding._(null);
    final token = Object();
    _binding = (target: target, token: token);
    return NovelReaderPagedNavigationBinding._(() {
      // Even rebinding the same target gets a new lifetime. An old unmount
      // cannot detach its replacement after a reader-mode/layout handoff.
      if (identical(_binding?.token, token)) _binding = null;
    });
  }

  void dispose() {
    _disposed = true;
    _binding = null;
  }
}

final class NovelReaderPagedNavigationBinding {
  NovelReaderPagedNavigationBinding._(this._release);
  void Function()? _release;

  void dispose() {
    final release = _release;
    _release = null;
    release?.call();
  }
}
