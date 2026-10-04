/// Identity of one opening or revision of image reader content.
///
/// Keeping the token object distinguishes a retired session even when its
/// owner and revision are later opened again.
class ReaderImageSessionToken {
  const ReaderImageSessionToken._({
    required this.ownerId,
    required this.revision,
    required this.generation,
  });

  final String ownerId;
  final int revision;
  final int generation;
}

/// Owns content identity only; positions, controllers and image work retain
/// their existing owners in the reader engine and preload coordinator.
class ReaderImageSessionCoordinator {
  ReaderImageSessionToken? _current;
  int _generation = 0;
  bool _closed = false;

  ReaderImageSessionToken? get current => _current;
  int get generation => _generation;

  ReaderImageSessionToken activate({
    required String ownerId,
    required int revision,
  }) {
    if (_closed) {
      throw StateError('The image reader session is closed.');
    }
    final current = _current;
    if (current != null &&
        current.ownerId == ownerId &&
        current.revision == revision) {
      return current;
    }
    return _current = ReaderImageSessionToken._(
      ownerId: ownerId,
      revision: revision,
      generation: ++_generation,
    );
  }

  bool isCurrent(ReaderImageSessionToken? token) =>
      !_closed && token != null && identical(token, _current);

  void close() {
    _closed = true;
  }
}
