enum ReaderInitialRestoreStatus { pending, consumed }

class ReaderPendingPagedSeek {
  const ReaderPendingPagedSeek({
    required this.logicalIndex,
    required this.generation,
  });

  final int logicalIndex;
  final int generation;
}

/// Position state owned by one reader content owner.
///
/// Initial position is consumed at most once per owner. Rebuilds update the
/// committed logical index without making the initial position eligible again.
class ReaderPositionState {
  ReaderPositionState({
    required this.ownerId,
    required this.initialLogicalIndex,
  }) : assert(initialLogicalIndex >= 0),
       _committedLogicalIndex = initialLogicalIndex;

  final String ownerId;
  final int initialLogicalIndex;

  ReaderInitialRestoreStatus _initialRestoreStatus =
      ReaderInitialRestoreStatus.pending;
  int _committedLogicalIndex;
  ReaderPendingPagedSeek? _pendingPagedSeek;

  ReaderInitialRestoreStatus get initialRestoreStatus => _initialRestoreStatus;
  int get committedLogicalIndex => _committedLogicalIndex;
  ReaderPendingPagedSeek? get pendingPagedSeek => _pendingPagedSeek;

  bool get needsInitialRestore =>
      _initialRestoreStatus == ReaderInitialRestoreStatus.pending;

  void consumeInitialRestore() {
    _initialRestoreStatus = ReaderInitialRestoreStatus.consumed;
  }

  void commitLogicalIndex(int index) {
    assert(index >= 0);
    _committedLogicalIndex = index;
  }

  void queuePagedSeek({required int index, required int generation}) {
    assert(index >= 0);
    _pendingPagedSeek = ReaderPendingPagedSeek(
      logicalIndex: index,
      generation: generation,
    );
  }

  void clearPendingPagedSeek(ReaderPendingPagedSeek pending) {
    if (identical(_pendingPagedSeek, pending)) {
      _pendingPagedSeek = null;
    }
  }
}
